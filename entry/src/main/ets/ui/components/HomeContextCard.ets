import { AppGlobal } from '../../app/AppGlobal';
import { HomeContextRepository } from '../../data/home/HomeContextRepository';
import { HomeDigest } from '../../features/home/HomeDigest';
import { HOME_DEFAULT_REGION, HomeAppearance, HomeAtmosphere, HomeContextRules, HomeCourseContext, HomePhrase,
  HomePhraseBatch, HomePhraseContext, HomeReading, HomeRegion, HomeWeather } from '../../features/home/HomeContext';
import { HOME_LOCAL_PHRASES } from '../../features/home/HomePhrases';
import { HomeAtmosphereIcon, homeAtmosphereFeedback } from './HomeAtmosphereIcon';
import { Tokens } from '../theme/Tokens';

@Component
export struct HomeContextCard {
  @Prop @Watch('changeAccount') account: string = '';
  @Prop name: string = '';
  @Prop @Watch('update') now: number = Date.now();
  @Prop @Watch('update') openedAt: number = 0;
  @Prop @Watch('update') appearance: HomeAppearance = new HomeAppearance();
  @Prop @Watch('update') region: HomeRegion = HOME_DEFAULT_REGION;
  @Prop @Watch('update') weather: HomeWeather | undefined = undefined;
  @Prop @Watch('update') course: HomeCourseContext = new HomeCourseContext();
  @Prop @Watch('update') batch: HomePhraseBatch | undefined = undefined;
  @Prop @Watch('update') contentReady: boolean = true;
  @Prop @Watch('update') active: boolean = true;

  @State private reading: HomeReading | undefined = undefined;
  @State private response: HomeAtmosphere = HomeAtmosphere.None;
  private history: Map<string, number> = new Map();
  private shown: boolean = false;
  private lastRecorded: string = '';
  private revision: number = 0;
  private ready: boolean = false;
  private feedbackTimer: number = -1;

  aboutToAppear(): void {
    this.changeAccount();
  }

  aboutToDisappear(): void {
    this.revision += 1;
    this.clearFeedback();
    this.shown = false;
  }

  private async changeAccount(): Promise<void> {
    const revision = ++this.revision;
    const sid = this.account;
    this.ready = false;
    this.reading = undefined;
    this.history = new Map();
    this.lastRecorded = '';
    this.clearFeedback();
    const history = await HomeContextRepository.readHistory(sid, this.now);
    const reading = await HomeContextRepository.reading(sid);
    if (revision !== this.revision || sid !== this.account) return;
    this.history = history;
    this.reading = reading;
    this.ready = true;
    this.update();
  }

  private facts(): HomeWeather | undefined {
    return HomeContextRules.validWeather(this.weather, this.region.id, this.now) ? this.weather : undefined;
  }

  private context(): HomePhraseContext {
    return new HomePhraseContext(this.now, this.region.id, this.facts(), this.course);
  }

  private scene(): HomeAtmosphere {
    return this.appearance.funContent
      ? HomeContextRules.atmosphere(this.facts(), this.context(), this.now) : HomeAtmosphere.None;
  }

  private seed(context: HomePhraseContext): number {
    const date = new Date(this.now);
    return date.getDate() * 31 + date.getMonth() + context.time.length * 13 + this.account.length;
  }

  private fallback(): HomePhrase | undefined {
    const context = new HomePhraseContext(this.now, this.region.id, undefined, new HomeCourseContext());
    const fallback = HomeAppearance.read(JSON.stringify(this.appearance));
    fallback.english = false;
    return HomeContextRules.pick(HOME_LOCAL_PHRASES, context, fallback, this.history, this.now, this.seed(context));
  }

  private visiblePhrase(): HomePhrase | undefined {
    if (!this.appearance.funContent) return undefined;
    const current = this.reading;
    return current && HomeContextRules.keep(current, this.context(), this.appearance, this.now)
      ? current.phrase : this.fallback();
  }

  private update(): void {
    if (!this.active || this.response !== this.scene()) this.clearFeedback();
    if (!this.active || !this.ready || !this.appearance.funContent) return;
    if (this.appearance.onlineContent && !this.contentReady) return;
    const context = this.context();
    const current = this.reading;
    if (current && current.openedAt === this.openedAt && HomeContextRules.keep(current, context, this.appearance, this.now)) {
      this.recordSoon();
      return;
    }
    if (current && this.course.status === '正在读取课表' &&
      ['UPCOMING', 'ONGOING', 'BREAK', 'NO_CLASS', 'ENDED'].indexOf(current.phrase.topic) >= 0) return;
    const batch = this.batch;
    const available = batch && Date.parse(batch.expiresAt) > this.now
      ? HOME_LOCAL_PHRASES.concat(batch.entries) : HOME_LOCAL_PHRASES;
    const next = HomeContextRules.pick(available, context, this.appearance, this.history, this.now,
      this.seed(context), current?.phrase.id ?? this.lastSeen());
    if (!next) return;
    const expiry = HomeContextRules.online(next) ? Date.parse(batch?.expiresAt ?? '') : 0;
    this.reading = new HomeReading(next, context, expiry, this.openedAt);
    this.recordSoon();
  }

  private lastSeen(): string {
    let latest = 0;
    let result = '';
    this.history.forEach((seen: number, id: string) => {
      if (seen >= latest && seen <= this.now) {
        latest = seen;
        result = id;
      }
    });
    return result;
  }

  private recordSoon(): void {
    const id = this.reading?.phrase.id;
    const openedAt = this.openedAt;
    const record = openedAt + '/' + id;
    if (!this.shown || !this.active || !id || this.lastRecorded === record) return;
    const revision = this.revision;
    setTimeout(() => {
      const current = this.reading;
      if (revision !== this.revision || !this.shown || !this.active || !current || this.lastRecorded === record ||
        current.openedAt !== openedAt || this.openedAt !== openedAt ||
        current.phrase.id !== id || this.visiblePhrase()?.id !== id) return;
      this.lastRecorded = record;
      this.history.set(id, this.now);
      HomeContextRepository.remember(this.account, current, this.history);
    }, 32);
  }

  private clearFeedback(): void {
    clearTimeout(this.feedbackTimer);
    this.feedbackTimer = -1;
    this.response = HomeAtmosphere.None;
  }

  private showResponse(scene: HomeAtmosphere): void {
    if (!this.active || scene !== this.scene()) return;
    clearTimeout(this.feedbackTimer);
    this.response = scene;
    this.feedbackTimer = setTimeout(() => { this.clearFeedback(); }, 2200);
  }

  private weatherLabel(): string {
    const facts = this.facts();
    if (!facts) return '';
    const temp = typeof facts.temperatureC === 'number' ? ' · ' + Math.round(facts.temperatureC) + ' ℃' : '';
    const time = new Date(Date.parse(facts.validTime) + 8 * 60 * 60 * 1000);
    return this.region.label + ' · ' + facts.conditionText + temp + ' · ' +
      HomeDigest.pad2(time.getUTCHours()) + ':' + HomeDigest.pad2(time.getUTCMinutes());
  }

  private greeting(): string {
    const hello = HomeDigest.hello(new Date(this.now).getHours());
    const name = this.name.trim();
    return name.length > 0 ? hello + '，' + name : hello;
  }

  build() {
    Column({ space: Tokens.SPACE_8 }) {
      Row({ space: Tokens.SPACE_4 }) {
        Column({ space: Tokens.SPACE_8 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(HomeDigest.dateText(new Date(this.now)) + ' ' + ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][new Date(this.now).getDay()])
              .fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY).margin({ right: Tokens.SPACE_12 })
            Text(this.greeting()).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY)
              .constraintSize({ maxWidth: '100%' }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .id('home_context_greeting')
          }.width('100%')
          if (this.visiblePhrase() !== undefined) {
            Text(this.visiblePhrase()?.text ?? '')
              .fontSize(this.visiblePhrase()?.translation && this.appearance.onlineContent &&
                this.batch && Date.parse(this.batch.expiresAt) > this.now && this.batch.englishTypography === 'extraLarge'
                ? Tokens.F_TITLE : Tokens.F_HEADING)
              .fontWeight(FontWeight.Medium).fontColor(Tokens.TEXT_PRIMARY)
              .width('100%').id('home_context_phrase')
              .onVisibleAreaChange([0, 0.15], (visible: boolean, ratio: number) => {
                this.shown = visible && ratio >= 0.15;
                this.recordSoon();
              })
            if (this.visiblePhrase()?.translation) {
              Text(this.visiblePhrase()?.translation ?? '').fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY).width('100%').id('home_context_translation')
            }
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.scene() !== HomeAtmosphere.None) {
          HomeAtmosphereIcon({
            scene: this.scene(), motion: this.appearance.motion, active: this.active,
            onTap: (scene: HomeAtmosphere) => { this.showResponse(scene); }
          })
        }
      }.width('100%').alignItems(VerticalAlign.Top)
      if (this.facts() !== undefined) {
        if (this.visiblePhrase() !== undefined) Divider().color(Tokens.DIVIDER)
        Text(this.weatherLabel()).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_PRIMARY)
          .width('100%').id('home_context_weather')
        HomeWeatherAttribution({ attributions: this.facts()?.attributions ?? [] })
      }
      if (this.response !== HomeAtmosphere.None) {
        Text(homeAtmosphereFeedback(this.response)).fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY)
          .width('100%').id('home_context_feedback')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD_STRONG).borderRadius(Tokens.RADIUS_CARD).border({ width: 1, color: Tokens.CARD_EDGE })
  }
}

class WeatherCredit {
  label: string;
  url: string;

  constructor(label: string, url: string = '') {
    this.label = label;
    this.url = url;
  }
}

@Component
export struct HomeWeatherAttribution {
  @Prop attributions: string[] = [];

  private credits(): WeatherCredit[] {
    const names = new Set<string>(['和风天气']);
    const other: WeatherCredit[] = [];
    let qweather = '';
    for (const value of new Set(this.attributions)) {
      if (typeof value !== 'string') continue;
      const match = /^https:\/\/([a-z0-9.-]+)(?::443)?(?:[/?#]|$)[^\s\\]*$/i.exec(value);
      if (match) {
        const host = match[1].toLowerCase();
        if (qweather.length === 0 && (host === 'qweather.com' || host.endsWith('.qweather.com'))) {
          qweather = value;
        } else {
          other.push(new WeatherCredit(' · ' + host, value));
        }
      } else if (value.indexOf('://') < 0) {
        names.add(value);
      }
    }
    return [new WeatherCredit(Array.from(names).join(' · '), qweather)].concat(other);
  }

  build() {
    Text() {
      ForEach(this.credits(), (credit: WeatherCredit) => {
        if (credit.url.length > 0) {
          Span(credit.label).onClick(() => { AppGlobal.context?.openLink(credit.url).catch(() => {}); })
        } else {
          Span(credit.label)
        }
      }, (credit: WeatherCredit) => credit.label + credit.url)
    }.fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY).width('100%')
  }
}
