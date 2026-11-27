import { Services } from '../../app/Services';
import { HomeContextRepository } from '../../data/home/HomeContextRepository';
import { HOME_DEFAULT_REGION, HomeAppearance, HomeRegion } from '../../features/home/HomeContext';
import { Tokens } from '../theme/Tokens';

@Component
export struct HomeContentSettings {
  onClose: () => void = () => {};
  @State private choice: HomeAppearance = new HomeAppearance();
  @State private loading: boolean = true;
  @State private picking: boolean = false;
  @State private query: string = '';
  private sid: string = '';

  aboutToAppear(): void {
    this.sid = Services.currentSid;
    HomeContextRepository.settings(this.sid).then((value: HomeAppearance) => {
      if (Services.currentSid === this.sid) {
        this.choice = value;
        this.loading = false;
      }
    });
  }

  private update(change: (value: HomeAppearance) => void): void {
    if (!this.sid.length || this.sid !== Services.currentSid || this.loading) return;
    const next = HomeAppearance.read(JSON.stringify(this.choice));
    change(next);
    this.choice = next;
    HomeContextRepository.saveSettings(this.sid, next);
  }

  private results(): HomeRegion[] {
    const needle = this.query.trim();
    const all = HomeContextRepository.regions();
    if (needle.length === 0) {
      return all.filter((region: HomeRegion) => region.id === this.choice.regionId || region.parent === '福建省').slice(0, 18);
    }
    return all.filter((region: HomeRegion) => region.label.includes(needle)).slice(0, 80);
  }

  private select(id: string): void {
    this.update((value: HomeAppearance) => { value.regionId = id; });
    this.picking = false;
    this.query = '';
  }

  @Builder
  setting(title: string, checked: boolean, change: (value: boolean) => void) {
    Row() {
      Text(title).fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(Tokens.MIST_TEAL).accessibilityText(title).onChange(change)
    }
    .width('100%').constraintSize({ minHeight: 48 })
  }

  @Builder
  regionsPanel() {
    TextInput({ placeholder: '搜索城市或区县', text: this.query })
      .constraintSize({ minHeight: 48 }).width('100%')
      .onChange((value: string) => { this.query = value.slice(0, 40); })
    Button('恢复默认 · 福州市闽侯县').constraintSize({ minHeight: 48 }).width('100%')
      .onClick(() => { this.select(HOME_DEFAULT_REGION.id); })
    if (this.results().length === 0) {
      Text('没有匹配的市县').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_SECONDARY)
    }
    ForEach(this.results(), (region: HomeRegion) => {
      Button(region.label).type(ButtonType.Normal).width('100%').constraintSize({ minHeight: 48 })
        .fontColor(Tokens.TEXT_PRIMARY).backgroundColor(region.id === this.choice.regionId ? Tokens.TINT_TEAL : Color.Transparent)
        .onClick(() => { this.select(region.id); })
    }, (region: HomeRegion) => region.id)
    Text('地名资料来自 GeoNames（CC BY 4.0）').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY)
    Button('返回首页内容').constraintSize({ minHeight: 48 }).type(ButtonType.Normal)
      .onClick(() => { this.picking = false; })
  }

  @Builder
  settingsPanel() {
    this.setting(this.choice.funContent ? '趣味内容' : '简洁模式', this.choice.funContent,
      (on: boolean) => { this.update((value: HomeAppearance) => { value.funContent = on; }); })
    if (this.choice.funContent) {
      this.setting('联网文案', this.choice.onlineContent,
        (on: boolean) => { this.update((value: HomeAppearance) => { value.onlineContent = on; }); })
      this.setting('偶尔显示英语', this.choice.english,
        (on: boolean) => { this.update((value: HomeAppearance) => { value.english = on; }); })
      this.setting('装饰动效', this.choice.motion,
        (on: boolean) => { this.update((value: HomeAppearance) => { value.motion = on; }); })
      Text('语气').fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(['SIMPLE', 'GENTLE', 'PLAYFUL'], (tone: string) => {
          Button(tone === 'SIMPLE' ? '简洁' : (tone === 'GENTLE' ? '温柔' : '俏皮'))
            .constraintSize({ minHeight: 48 }).margin({ right: Tokens.SPACE_8, bottom: Tokens.SPACE_8 })
            .fontColor(Tokens.TEXT_PRIMARY).backgroundColor(this.choice.tone === tone ? Tokens.TINT_TEAL : Tokens.CARD)
            .accessibilityDescription(this.choice.tone === tone ? '已选' : '')
            .onClick(() => { this.update((value: HomeAppearance) => { value.tone = tone; }); })
        }, (tone: string) => tone)
      }.width('100%')
    }
    Divider().color(Tokens.DIVIDER)
    Column({ space: Tokens.SPACE_4 }) {
      Text('天气地区').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_PRIMARY)
      Text(HomeContextRepository.region(this.choice.regionId).label).fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY)
    }.width('100%').alignItems(HorizontalAlign.Start).constraintSize({ minHeight: 48 })
    .justifyContent(FlexAlign.Center).onClick(() => { this.picking = true; })
    Button('完成').width('100%').constraintSize({ minHeight: 48 }).onClick(() => { this.onClose(); })
  }

  build() {
    Scroll() {
      Column({ space: Tokens.SPACE_8 }) {
        Text(this.picking ? '选择天气地区' : '首页内容')
          .fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Medium).fontColor(Tokens.TEXT_PRIMARY)
        if (this.loading) {
          Text('正在读取设置').fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_SECONDARY)
        } else if (this.picking) {
          this.regionsPanel()
        } else {
          this.settingsPanel()
        }
      }.width('100%').padding(Tokens.SPACE_16).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }
}

