import { AppGlobal } from '../../app/AppGlobal';
import { HomeContextRepository } from '../../data/home/HomeContextRepository';
import { SessionInfo } from '../../data/timetable/TimetableModels';
import { TimetableFocus } from '../../data/timetable/TimetableFocus';
import { HomeDigest } from '../../features/home/HomeDigest';
import { HOME_DEFAULT_REGION, HomeAppearance, HomeContextRules, HomeCourseContext, HomePhrase, HomePhraseBatch,
  HomePhraseContext, HomeReading, HomeRegion, HomeWeather } from '../../features/home/HomeContext';
import { HOME_LOCAL_PHRASES } from '../../features/home/HomePhrases';
import { showFeedback } from './AppFeedback';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';

@Component
export struct HomeContextCard {
  @Prop @Watch('changeAccount') account: string = '';
  @Prop @Watch('update') now: number = Date.now();
  @Prop @Watch('update') appearance: HomeAppearance = new HomeAppearance();
  @Prop @Watch('update') region: HomeRegion = HOME_DEFAULT_REGION;
  @Prop @Watch('update') weather: HomeWeather | undefined = undefined;
  @Prop @Watch('update') course: HomeCourseContext = new HomeCourseContext();
  @Prop @Watch('update') batch: HomePhraseBatch | undefined = undefined;
  @Prop @Watch('update') active: boolean = true;
  onOpenCourse: (focus: TimetableFocus) => void = () => {};

  @State private reading: HomeReading | undefined = undefined;
  @State private sourceOpen: boolean = false;
  @State private lit: boolean = false;
  @State private bulbScale: number = 1;
  private history: Map<string, number> = new Map();
  private shown: boolean = false;
  private lastRecorded: string = '';
  private revision: number = 0;
  private choice: number = 0;
  private ready: boolean = false;
  private lampTimer: number = -1;

  aboutToAppear(): void {
    this.changeAccount();
  }

  aboutToDisappear(): void {
    this.revision += 1;
    this.resetLamp();
    this.shown = false;
  }

  private async changeAccount(): Promise<void> {
    const revision = ++this.revision;
    const sid = this.account;
    this.ready = false;
    this.reading = undefined;
    this.history = new Map();
    this.sourceOpen = false;
    this.lastRecorded = '';
    this.choice = 0;
    this.resetLamp();
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

  private seed(context: HomePhraseContext): number {
    const date = new Date(this.now);
    return date.getDate() * 31 + date.getMonth() + context.time.length * 13 + this.choice * 17 + this.account.length;
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
    if (!this.active) {
      this.resetLamp();
      return;
    }
    if (!this.appearance.motion) this.resetLamp();
    if (!this.ready || !this.appearance.funContent) return;
    const current = this.reading;
    if (current && HomeContextRules.keep(current, this.context(), this.appearance, this.now)) {
      this.recordSoon();
      return;
    }
    if (current && this.course.status === '正在读取课表' &&
      ['UPCOMING', 'ONGOING', 'BREAK', 'NO_CLASS', 'ENDED'].indexOf(current.phrase.topic) >= 0) return;
    this.choose(false);
  }

  private pick(manual: boolean): HomePhrase | undefined {
    const context = this.context();
    const batch = this.batch;
    const available = batch && Date.parse(batch.expiresAt) > this.now
      ? HOME_LOCAL_PHRASES.concat(batch.entries) : HOME_LOCAL_PHRASES;
    return HomeContextRules.pick(available, context, this.appearance, this.history, this.now,
      this.seed(context) + (manual ? 17 : 0), this.reading?.phrase.id ?? '', manual);
  }

  private choose(manual: boolean): void {
    const next = this.pick(manual);
    if (!next || (manual && next.id === this.reading?.phrase.id)) return;
    if (manual) this.choice += 1;
    const expiry = HomeContextRules.online(next) ? Date.parse(this.batch?.expiresAt ?? '') : 0;
    this.reading = new HomeReading(next, this.context(), expiry);
    this.sourceOpen = false;
    this.resetLamp();
    this.recordSoon();
  }

  private recordSoon(): void {
    const id = this.reading?.phrase.id;
    if (!this.shown || !this.active || !id || this.lastRecorded === id) return;
    setTimeout(() => {
      const current = this.reading;
      if (!this.shown || !this.active || !current || this.lastRecorded === id ||
        current.phrase.id !== id || this.visiblePhrase()?.id !== id) return;
      this.lastRecorded = id;
      this.history.set(id, this.now);
      HomeContextRepository.remember(this.account, current, this.history);
    }, 32);
  }

  private translation(): void {
    const reading = this.reading;
    if (!reading || !reading.phrase.translation) return;
    reading.expanded = !reading.expanded;
    this.reading = JSON.parse(JSON.stringify(reading)) as HomeReading;
    HomeContextRepository.remember(this.account, reading, this.history);
  }

  private resetLamp(): void {
    clearTimeout(this.lampTimer);
    this.lampTimer = -1;
    this.lit = false;
    this.bulbScale = 1;
  }

  private tapLamp(): void {
    this.resetLamp();
    this.lit = true;
    if (this.appearance.motion) {
      this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => { this.bulbScale = 1.12; });
    }
    this.lampTimer = setTimeout(() => { this.resetLamp(); }, 550);
  }

  private canSwap(): boolean {
    const alternative = this.pick(true);
    return this.ready && alternative !== undefined && alternative.id !== this.visiblePhrase()?.id;
  }

  private primary(): string {
    const phrase = this.visiblePhrase();
    if (phrase?.translation) return this.reading?.expanded ? '收起中文' : '看中文';
    if (this.course.action.length > 0 && (!this.appearance.funContent || this.course.urgent ||
      (this.course.action === '查看明日课表' && phrase !== undefined && !HomeContextRules.online(phrase)))) {
      return this.course.action;
    }
    return this.canSwap() ? '换一句' : '';
  }

  private primaryTap(): void {
    const action = this.primary();
    if (action === '看中文' || action === '收起中文') this.translation();
    else if (action === '换一句') this.choose(true);
    else if (this.course.focus) this.onOpenCourse(this.course.focus);
  }

  private weatherLabel(): string {
    const facts = this.facts();
    if (!facts) return '';
    const temp = typeof facts.temperatureC === 'number' ? ' · ' + Math.round(facts.temperatureC) + ' ℃' : '';
    const time = new Date(Date.parse(facts.validTime) + 8 * 60 * 60 * 1000);
    return this.region.label + ' · ' + facts.conditionText + temp + ' · ' +
      HomeDigest.pad2(time.getUTCHours()) + ':' + HomeDigest.pad2(time.getUTCMinutes());
  }

  private weatherCredit(): string {
    const credits = this.facts()?.attributions;
    const values = Array.isArray(credits) ? credits.filter((value: string) => typeof value === 'string') : [];
    return Array.from(new Set<string>(['和风天气'].concat(values))).join(' · ');
  }

  private openSource(): void {
    const url = this.visiblePhrase()?.sourceUrl;
    if (url && HomeContextRules.validSource(url)) {
      AppGlobal.context?.openLink(url).catch(() => { showFeedback(this.getUIContext(), '原文暂时无法打开'); });
    }
  }

  @Builder
  sourcePanel() {
    Column({ space: Tokens.SPACE_12 }) {
      Text('文案出处').fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Medium).fontColor(Tokens.TEXT_PRIMARY)
      Text('由 DeepSeek 根据公开资料生成。').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_SECONDARY)
      Text(this.visiblePhrase()?.sourceTitle ?? '').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY)
      Button('阅读原文').constraintSize({ minHeight: 48 }).onClick(() => { this.openSource(); })
      Button('关闭').type(ButtonType.Normal).constraintSize({ minHeight: 48 })
        .backgroundColor(Color.Transparent).fontColor(Tokens.TEXT_PRIMARY)
        .onClick(() => { this.sourceOpen = false; })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Tokens.CARD_PADDING)
    .width('100%')
  }

  @Builder
  courseLine(label: string, session: SessionInfo) {
    Text(label + ' · ' + (session.dayOffset > 0 ? session.dayText + ' ' : '') + session.startText + ' · ' + session.name)
      .fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).width('100%')
    if (session.fullRoom.length > 0) {
      Text(session.fullRoom).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY).width('100%')
    }
  }

  build() {
    Column({ space: Tokens.SPACE_8 }) {
      Text(HomeDigest.dateText(new Date(this.now)) + ' ' + ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][new Date(this.now).getDay()])
        .fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY)
      if (this.visiblePhrase() !== undefined) {
        Text(this.visiblePhrase()?.text ?? '')
          .fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Medium).fontColor(Tokens.TEXT_PRIMARY)
          .width('100%').onVisibleAreaChange([0, 0.15], (visible: boolean, ratio: number) => {
            this.shown = visible && ratio >= 0.15;
            this.recordSoon();
          })
        if (this.reading?.expanded && this.visiblePhrase()?.translation) {
          Text(this.visiblePhrase()?.translation ?? '').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).width('100%')
        }
        Divider().color(Tokens.DIVIDER)
      }
      if (this.facts() !== undefined) {
        Text(this.weatherLabel()).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_PRIMARY).width('100%')
        Text(this.weatherCredit()).fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY).width('100%')
      }
      if (this.course.status.length > 0) {
        Text(this.course.status).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_PRIMARY)
      }
      if (this.course.current) this.courseLine('正在上课', this.course.current)
      if (this.course.next) this.courseLine(this.course.cached ? '缓存中的下节课' : '下一节', this.course.next)
      if (this.primary().length > 0) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Button(this.primary())
            .constraintSize({ minWidth: 48, minHeight: 48 })
            .fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).backgroundColor(Tokens.TINT_TEAL)
            .margin({ right: Tokens.SPACE_8 })
            .accessibilityDescription(this.visiblePhrase()?.translation ? (this.reading?.expanded ? '已展开' : '已收起') : '')
            .onClick(() => { this.primaryTap(); })
          if (this.primary() !== '换一句' && this.canSwap()) {
            Button('换一句').type(ButtonType.Normal).constraintSize({ minWidth: 48, minHeight: 48 })
              .fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).backgroundColor(Color.Transparent)
              .onClick(() => { this.choose(true); })
          } else if (HomeContextRules.validSource(this.visiblePhrase()?.sourceUrl)) {
            Button('出处').type(ButtonType.Normal).constraintSize({ minWidth: 48, minHeight: 48 })
              .fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).backgroundColor(Color.Transparent)
              .onClick(() => { this.sourceOpen = true; })
          } else if (this.primary() === '换一句') {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(22)
                .fontColor([this.lit ? Tokens.MIST_TEAL : Tokens.TEXT_PRIMARY])
                .scale({ x: this.bulbScale, y: this.bulbScale })
            }.width(48).height(48).backgroundColor(Color.Transparent)
            .accessibilityText('点亮小灯').accessibilityDescription(this.lit ? '已点亮' : '未点亮')
            .onClick(() => { this.tapLamp(); })
          }
        }.width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD_STRONG).borderRadius(Tokens.RADIUS_CARD).border({ width: 1, color: Tokens.CARD_EDGE })
    .bindSheet($$this.sourceOpen, this.sourcePanel(), {
      height: SheetSize.MEDIUM, showClose: false, dragBar: true, backgroundColor: Tokens.SHEET
    })
  }
}

