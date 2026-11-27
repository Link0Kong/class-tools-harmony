import { PageInsets } from '../theme/PageInsets';
import { showFeedback } from '../components/AppFeedback';
import { LiveActivity } from '../../data/notify/LiveActivity';
import notificationManager from '@ohos.notificationManager';
import { formProvider } from '@kit.FormKit';
import { CloudConfig } from '../../config/CloudConfig';
import { Tokens } from '../theme/Tokens';
import { HomeContentSettings } from './HomeContentSettings';
import { Breakpoints } from '../theme/Breakpoints';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { HuaweiAccount } from '../../data/account/HuaweiAccount';
import { AccountBindingRepository, BindItem } from '../../data/account/AccountBindingRepository';
import { BrandMark } from '../components/BrandMark';
import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { NickLogic } from '../../features/home/NickLogic';
import { AppPush } from '../../features/push/AppPush';
import { NotifyCenter } from '../../data/notify/NotifyCenter';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { AppUpdate, UpdateCheckResult } from '../../features/update/AppUpdate';
import { LegalDoc, LegalInfo, LegalSection, LegalTexts } from '../../data/legal/LegalTexts';

/** 我的：身份卡 + 设置项 + 退出登录。 */
@Component
export struct MeScreen {
  @Prop userName: string = '';
  @Prop @Watch('openNotificationSettings') notifyRequest: boolean = false;
  onNotifyHandled: () => void = () => {};
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop isAdmin: boolean = false;
  @Prop syncState: string = '';
  onSyncNow: () => void = () => {
  };
  onOpenTool: (id: string) => void = () => {
  };
  onLogout: () => void = () => {
  };

  @State private nick: string = '';
  @State private nickEditing: boolean = false;
  @State private nickDraft: string = '';
  @State private pushOn: boolean = false;
  @State private pushSysOn: boolean = false;
  @State private pushBusy: boolean = false;
  @State private pushNotice: string = '';
  @State private homeContentOpen: boolean = false;
  @State private notifyOpen: boolean = false;
  @State private notifySettings: NotifySettings = new NotifySettings();
  @State private testBusy: boolean = false;
  @State private liveEnabled: boolean = false;
  private settingsTouched: boolean = false;
  @State private hwItems: BindItem[] = [];
  @State private hwBusy: boolean = false;
  @State private updateBusy: boolean = false;
  @State private legalOpen: boolean = false;
  @State private legalInfo: LegalInfo = LegalTexts.info(LegalTexts.PRIVACY);
  @State private legalDoc: LegalDoc = LegalTexts.fallback(LegalTexts.info(LegalTexts.PRIVACY));
  @State private legalNotice: string = '';
  @State private layoutWidth: number = 0;
  @State private topFade: number = 0;
  private scroller: Scroller = new Scroller();

  private async checkUpdate(): Promise<void> {
    if (this.updateBusy) {
      return;
    }
    this.updateBusy = true;
    const result: UpdateCheckResult = await AppUpdate.check(true);
    this.updateBusy = false;
    showFeedback(this.getUIContext(), result.message);
  }

  /** 打开端内法律文本：优先 rawfile 正文，读取失败用要点摘要兜底。 */
  private openLegal(kind: string): void {
    this.legalInfo = LegalTexts.info(kind);
    this.legalNotice = '';
    let raw: string = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(this.legalInfo.rawPath);
      raw = util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (e) {
      raw = '';
    }
    this.legalDoc = LegalTexts.loadOrFallback(raw, this.legalInfo);
    if (this.legalDoc.fallback) {
      this.legalNotice = '端内正文读取失败，已显示要点摘要；可在线查看全文。';
    }
    this.notifyOpen = false;
    this.legalOpen = true;
  }

  /** 在线正式文本（2026-11-23 起为正式 HTTPS 域名 `https://tool.furina.fun/legal/...`）。 */
  private openLegalOnline(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.openLink(this.legalInfo.onlineUrl).catch((error: BusinessError) => {
      this.legalNotice = '无法打开浏览器，请手动访问：' + this.legalInfo.onlineUrl;
    });
  }

  private openNotificationSettings(): void {
    if (this.notifyRequest) {
      this.notifyOpen = true;
      this.onNotifyHandled();
    }
  }

  aboutToAppear(): void {
    this.openNotificationSettings();
    const sections: Blob = Services.userdata.currentSections();
    const value = sections['nick'];
    this.nick = value === undefined ? '' : String(value);
    this.refreshPushPermission();
    this.loadNotifySettings();
    this.loadBindings();
  }

  private async loadNotifySettings(): Promise<void> {
    this.liveEnabled = await LiveActivity.available();
    const loaded: NotifySettings = await NotifyCenter.currentSettings();
    if (this.settingsTouched) {
      return;
    }
    this.notifySettings = loaded;
    this.pushOn = loaded.master;
    this.pushSysOn = await AppPush.systemEnabled();
  }

  private async refreshPushPermission(): Promise<void> {
    this.pushSysOn = await AppPush.systemEnabled();
    if (!this.pushSysOn) {
      this.pushNotice = '系统通知权限未开启，打开开关可重新申请';
    }
  }

  private async loadBindings(): Promise<void> {
    this.hwItems = await AccountBindingRepository.list();
  }

  private async bindHuawei(): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const openId: string = await HuaweiAccount.openId(context);
      const err: string = await AccountBindingRepository.bind(openId, 'phone');
      showFeedback(this.getUIContext(), err.length > 0 ? err : '已绑定当前华为账号');
      await this.loadBindings();
    } catch (e) {
      showFeedback(this.getUIContext(), HuaweiAccount.message(e as Object));
    }
    this.hwBusy = false;
  }

  private confirmUnbind(item: BindItem): void {
    if (this.hwBusy) {
      return;
    }
    AlertDialog.show({
      title: '解绑华为账号',
      message: '解绑后该华为账号将无法一键登录，需要使用学号 + 姓名重新绑定。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '解绑',
        fontColor: Tokens.DANGER,
        action: () => {
          this.unbindHuawei(item.openId);
        }
      }
    });
  }

  private async unbindHuawei(openId: string): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    const ok: boolean = await AccountBindingRepository.unbind(openId);
    showFeedback(this.getUIContext(), ok ? '已解绑，可重新绑定当前华为账号' : '解绑失败，请稍后重试');
    await this.loadBindings();
    this.hwBusy = false;
  }

  private async togglePush(next: boolean): Promise<void> {
    if (this.pushBusy || this.notifySettings.master === next) {
      return;
    }
    this.settingsTouched = true;
    this.pushBusy = true;
    this.pushOn = next;
    if (next) {
      const allowed: boolean = await NotifyCenter.ensurePermission();
      this.pushSysOn = allowed;
      if (!allowed) {
        this.pushOn = false;
        this.pushNotice = '系统通知权限未开启，请允许后再试';
        this.pushBusy = false;
        return;
      }
      const ok: boolean = await AppPush.enable();
      const settings: NotifySettings = this.notifySettings.copy();
      settings.master = true;
      this.notifySettings = settings;
      await NotifyCenter.saveSettings(settings);
      this.pushOn = true;
      await NotifyCenter.syncAll(true);
      this.pushNotice = ok ? '已开启系统推送并开始监听'
        : '通知已开启；推送 token 暂不可用，本地提醒仍可用';
    } else {
      await AppPush.disable();
      const settings: NotifySettings = this.notifySettings.copy();
      settings.master = false;
      this.notifySettings = settings;
      await NotifyCenter.saveSettings(settings);
      this.pushOn = false;
      this.pushNotice = '已关闭系统推送与本地提醒';
    }
    this.pushBusy = false;
  }

  private notifyValue(key: string): boolean {
    if (key === 'liveActivities') {
      return this.notifySettings.liveActivities;
    }
    if (key === 'homeworkNew') {
      return this.notifySettings.homeworkNew;
    }
    if (key === 'homeworkDue') {
      return this.notifySettings.homeworkDue;
    }
    if (key === 'classRemind') {
      return this.notifySettings.classRemind;
    }
    if (key === 'noticeNew') {
      return this.notifySettings.noticeNew;
    }
    if (key === 'noticeDeadline') {
      return this.notifySettings.noticeDeadline;
    }
    if (key === 'noticeSignup') {
      return this.notifySettings.noticeSignup;
    }
    if (key === 'voteNew') {
      return this.notifySettings.voteNew;
    }
    if (key === 'voteResult') {
      return this.notifySettings.voteResult;
    }
    return this.notifySettings.waterDeduct;
  }

  private async setNotifyField(key: string, value: boolean): Promise<void> {
    if (this.notifyValue(key) === value) return;
    this.settingsTouched = true;
    const settings: NotifySettings = this.notifySettings.copy();
    if (key === 'liveActivities') {
      settings.liveActivities = value;
    } else if (key === 'homeworkNew') {
      settings.homeworkNew = value;
    } else if (key === 'homeworkDue') {
      settings.homeworkDue = value;
    } else if (key === 'classRemind') {
      settings.classRemind = value;
    } else if (key === 'noticeNew') {
      settings.noticeNew = value;
    } else if (key === 'noticeDeadline') {
      settings.noticeDeadline = value;
    } else if (key === 'noticeSignup') {
      settings.noticeSignup = value;
    } else if (key === 'voteNew') {
      settings.voteNew = value;
    } else if (key === 'voteResult') {
      settings.voteResult = value;
    } else {
      settings.waterDeduct = value;
    }
    this.notifySettings = settings;
    await NotifyCenter.saveSettings(settings);
    await NotifyCenter.syncAll(true);
  }

  private async setNotifyLead(minutes: number): Promise<void> {
    this.settingsTouched = true;
    const settings: NotifySettings = this.notifySettings.copy();
    settings.leadMinutes = NotifySettings.normalizeLead(minutes);
    this.notifySettings = settings;
    await NotifyCenter.saveSettings(settings);
    await NotifyCenter.syncAll(true);
  }

  private async setClassLead(minutes: number, duringBreak: boolean): Promise<void> {
    if (!this.notifySettings.master || !this.notifySettings.classRemind) {
      return;
    }
    this.settingsTouched = true;
    const settings: NotifySettings = this.notifySettings.copy();
    if (duringBreak) settings.breakLeadMinutes = NotifySettings.normalizeBreakLead(minutes);
    else settings.classLeadMinutes = NotifySettings.normalizeClassLead(minutes);
    this.notifySettings = settings;
    await NotifyCenter.saveSettings(settings);
    await NotifyCenter.syncAll(true);
  }

  private async sendTestNotice(): Promise<void> {
    if (this.testBusy) {
      return;
    }
    this.testBusy = true;
    const allowed: boolean = await NotifyCenter.ensurePermission();
    this.pushSysOn = allowed;
    if (!allowed) {
      showFeedback(this.getUIContext(), '请先在系统设置中允许通知，再发送测试');
      this.testBusy = false;
      return;
    }
    const ok: boolean = await NotifyCenter.sendTest();
    showFeedback(this.getUIContext(), ok ? '测试通知已发送，请下拉通知中心查看' : '发送失败，请稍后重试');
    this.testBusy = false;
  }

  private notifySummary(): string {
    if (!this.notifySettings.master) {
      return '未开启';
    }
    return '已开启 ' + this.notifySettings.enabledCount() + ' 项';
  }

  private pushStatusText(): string {
    if (!this.pushSysOn) {
      return '系统通知未授权，打开开关将请求授权';
    }
    if (this.pushOn && !AppPush.enabled()) {
      return '已开启；推送服务注册中或暂不可用';
    }
    return '新通知/作业到达时由系统推送';
  }

  private async saveNick(): Promise<void> {
    const next: string = NickLogic.normalize(this.nickDraft);
    const userdata = Services.userdata;
    const sections: Blob = userdata.currentSections();
    sections['nick'] = next;
    const result = await userdata.saveAndPush(sections, 'nick');
    if (userdata !== Services.userdata) return;
    this.nick = next;
    this.nickEditing = false;
    showFeedback(this.getUIContext(), result.ok() ? '昵称已保存并同步' : '已保存到本机，稍后自动同步');
  }

  @Builder
  linkRow(title: string, value: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(value)
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ right: Tokens.SPACE_4 })
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(16)
        .fontColor([Tokens.TEXT_TERTIARY])
    }
    .width('100%')
    .height(52)
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
    .onClick(onTap)
  }

  @Builder
  row(title: string, value: string, danger: boolean) {
    Row() {
      Text(title)
        .fontSize(Tokens.F_BODY)
        .fontColor(danger ? Tokens.DANGER : Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(value)
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_TERTIARY)
    }
    .width('100%')
    .height(52)
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
  }

  @Builder
  notifySettingsRow() {
    Row() {
      Text('通知设置')
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(this.notifySummary())
        .fontSize(Tokens.F_LABEL)
        .fontColor(this.notifySettings.master ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
        .margin({ right: Tokens.SPACE_4 })
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(16)
        .fontColor([Tokens.TEXT_TERTIARY])
    }
    .width('100%')
    .height(52)
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
    .onClick(() => {
      this.notifyOpen = true;
    })
  }

  @Builder
  notifySwitch(key: string, label: string, sub: string) {
    Row() {
      Column() {
        Text(label)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text(sub)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ right: 10 })
      Toggle({ type: ToggleType.Switch, isOn: this.notifyValue(key) })
        .selectedColor(Tokens.MIST_TEAL)
        .enabled(this.notifySettings.master)
        .onChange((on: boolean) => {
          this.setNotifyField(key, on);
        })
    }
    .width('100%')
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.SPACE_12, bottom: Tokens.SPACE_12 })
    .opacity(this.notifySettings.master ? 1 : 0.55)
  }

  @Builder
  notifySection(title: string) {
    Text(title)
      .fontSize(Tokens.F_CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(Tokens.TEXT_SECONDARY)
      .width('100%')
      .padding({ left: Tokens.SPACE_16, top: Tokens.SPACE_16, bottom: Tokens.GAP_SM })
  }

  @Builder
  notifyDivider() {
    Divider()
      .color(Tokens.DIVIDER)
      .strokeWidth(0.5)
      .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
  }

  @Builder
  classLeadRow(duringBreak: boolean) {
    Column() {
      Text(duringBreak ? '课间提前时间' : '提前时间')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(duringBreak ? NotifySettings.BREAK_LEAD_OPTIONS : NotifySettings.CLASS_LEAD_OPTIONS, (minutes: number, i: number) => {
          Text(minutes + ' 分钟')
            .fontSize(Tokens.F_LABEL)
            .fontColor((duringBreak ? this.notifySettings.breakLeadMinutes : this.notifySettings.classLeadMinutes) === minutes ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
            .backgroundColor((duringBreak ? this.notifySettings.breakLeadMinutes : this.notifySettings.classLeadMinutes) === minutes ? Tokens.MIST_TEAL : '#FFFFFF')
            .border({ width: 1, color: (duringBreak ? this.notifySettings.breakLeadMinutes : this.notifySettings.classLeadMinutes) === minutes
              ? Tokens.MIST_TEAL : Tokens.DIVIDER })
            .borderRadius(Tokens.RADIUS_PILL)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ right: Tokens.GAP_SM, bottom: Tokens.GAP_SM })
            .onClick(() => {
              this.setClassLead(minutes, duringBreak);
            })
        }, (minutes: number, i: number) => 'class_lead_' + minutes)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.SPACE_12, bottom: Tokens.SPACE_12 })
    .opacity(this.notifySettings.master && this.notifySettings.classRemind ? 1 : 0.55)
  }

  @Builder
  notifyPanel() {
    Column() {
      Row()
        .width(38)
        .height(4)
        .borderRadius(2)
        .backgroundColor('#DDE5E1')
        .margin({ top: 8 })

      Row() {
        Column() {
          Text('通知设置')
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text('只接收你关心的班级提醒')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('完成')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.GAP_SM, bottom: Tokens.GAP_SM })
          .backgroundColor('#EEF5F2')
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.notifyOpen = false;
          })
      }
      .width('100%')
      .padding({ left: Tokens.SPACE_20, right: Tokens.SPACE_16, top: Tokens.SPACE_12, bottom: Tokens.GAP_SM })

      Scroll() {
        Column() {
          Row() {
            Column() {
              Row({ space: 6 }) {
                Text('允许通知')
                  .fontSize(Tokens.F_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Tokens.TEXT_PRIMARY)
                Text(this.pushOn ? '已开启' : '已关闭')
                  .fontSize(10)
                  .fontColor(this.pushOn ? '#3F6F66' : Tokens.TEXT_TERTIARY)
                  .backgroundColor(this.pushOn ? '#E4F0EB' : '#ECEFED')
                  .borderRadius(Tokens.RADIUS_PILL)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              Text(this.pushStatusText())
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ right: 10 })
            Toggle({ type: ToggleType.Switch, isOn: this.pushOn })
              .selectedColor(Tokens.MIST_TEAL)
              .enabled(!this.pushBusy)
              .onChange((on: boolean) => {
                this.togglePush(on);
              })
          }
          .width('100%')
          .padding(Tokens.SPACE_16)
          .backgroundColor(this.pushOn ? '#F1F7F4' : '#F5F7F6')
          .borderRadius(18)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.SPACE_4 })

          this.notifySection('作业提醒')
          Column() {
            this.notifySwitch('homeworkNew', '新作业通知', '有新的作业发布时提醒')
            this.notifyDivider()
            this.notifySwitch('homeworkDue', '作业即将截止', '按下方提前时间提醒')
          }
          .width('100%')
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .clip(true)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('上课提醒')
          Column() {
            this.notifySwitch('classRemind', '上课提醒', '按课表在课前提醒')
            this.notifyDivider()
            this.classLeadRow(false)
            this.classLeadRow(true)
          }
          .width('100%')
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .clip(true)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('通知提醒')
          Column() {
            this.notifySwitch('noticeNew', '新通知提醒', '班委发布新通知时提醒')
            this.notifyDivider()
            this.notifySwitch('noticeDeadline', '活动截止提醒', '活动/报名截止前提醒')
            this.notifyDivider()
            this.notifySwitch('noticeSignup', '活动开抢提醒', '报名开始时提前 5 分钟提醒')
          }
          .width('100%')
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .clip(true)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('投票与水费')
          Column() {
            this.notifySwitch('voteNew', '新投票提醒', '发起新投票时提醒')
            this.notifyDivider()
            this.notifySwitch('voteResult', '投票结果可查看', '投票结束后提醒查看结果')
            this.notifyDivider()
            this.notifySwitch('waterDeduct', '水费扣除提醒', '抄表产生用量/水费时提醒')
          }
          .width('100%')
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .clip(true)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('提醒时间')
          Column() {
            Text('截止类提醒统一提前')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
            Text('对新作业截止、通知截止生效')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: Tokens.TEXT_GAP, bottom: Tokens.SPACE_10 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(NotifySettings.LEAD_OPTIONS, (minutes: number, i: number) => {
                Text(minutes >= 1440 ? '1 天' : (minutes >= 60 ? (minutes / 60) + ' 小时' : minutes + ' 分钟'))
                  .fontSize(Tokens.F_LABEL)
                  .fontColor(this.notifySettings.leadMinutes === minutes ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
                  .backgroundColor(this.notifySettings.leadMinutes === minutes ? Tokens.MIST_TEAL : '#FFFFFF')
                  .border({ width: 1, color: this.notifySettings.leadMinutes === minutes
                    ? Tokens.MIST_TEAL : Tokens.DIVIDER })
                  .borderRadius(Tokens.RADIUS_PILL)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.setNotifyLead(minutes);
                  })
              }, (minutes: number, i: number) => 'lead_' + minutes)
            }
            .width('100%')
          }
          .width('100%')
          .padding(Tokens.SPACE_16)
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('实时活动')
          Column() {
            this.notifySwitch('liveActivities', '实时活动', this.liveEnabled ?
              '课前倒计时与演示上传可显示实况窗，限时投票显示在通知中心' :
              '系统实况窗未开启或设备不支持，提醒显示在通知中心')
          }
          .width('100%').backgroundColor('#F7F8F8').borderRadius(16)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          this.notifySection('确认提醒效果')
          Column() {
            Button('系统通知设置').type(ButtonType.Normal).backgroundColor(Color.Transparent)
              .fontColor(Tokens.SLATE_BLUE).onClick(async () => {
                try {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  await notificationManager.openNotificationSettingsWithResult(ctx);
                  await this.refreshPushPermission();
                  this.liveEnabled = await LiveActivity.available();
                  await NotifyCenter.syncAll(true);
                } catch (e) {
                  showFeedback(this.getUIContext(), '请在系统设置的通知管理中打开枫丹工具箱');
                }
              })
            Button(this.testBusy ? '正在发送…' : '发送测试通知')
              .type(ButtonType.Capsule)
              .width('100%')
              .height(42)
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor(this.testBusy ? '#9DBDB4' : Tokens.MIST_TEAL)
              .enabled(!this.testBusy)
              .onClick(() => {
                this.sendTestNotice();
              })
            Button('测试 20 秒定时提醒').type(ButtonType.Normal).backgroundColor(Color.Transparent)
              .fontColor(Tokens.SLATE_BLUE).enabled(!this.testBusy)
              .onClick(async () => {
                this.testBusy = true;
                showFeedback(this.getUIContext(), await NotifyCenter.testScheduled());
                this.testBusy = false;
              })
            Text('立即发出一条本地通知，用于检查系统权限和通知样式。')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(Tokens.SPACE_16)
          .backgroundColor('#F7F8F8')
          .borderRadius(16)
          .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          Text('系统通知权限只会在你首次开启通知或发送测试时请求。')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .padding({ left: 20, right: 20, top: 14, bottom: 32 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('88%')
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: 26, topRight: 26 })
  }

  @Builder
  legalPanel() {
    Column() {
      Row()
        .width(38)
        .height(4)
        .borderRadius(2)
        .backgroundColor('#DDE5E1')
        .margin({ top: 8 })

      Row() {
        Column() {
          Text(this.legalDoc.title.length > 0 ? this.legalDoc.title : this.legalInfo.title)
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text(this.legalInfo.version + ' · 生效 ' + this.legalInfo.effectiveDate)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('关闭')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.GAP_SM, bottom: Tokens.GAP_SM })
          .backgroundColor('#EEF5F2')
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.legalOpen = false;
          })
      }
      .width('100%')
      .padding({ left: Tokens.SPACE_20, right: Tokens.SPACE_16, top: Tokens.SPACE_12, bottom: Tokens.GAP_SM })

      Column() {
        Text('运营者：' + this.legalInfo.operator)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
        Text('联系邮箱：' + this.legalInfo.email)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 4 })
        Text('最近更新：' + this.legalInfo.lastUpdated)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(Tokens.SPACE_12)
      .backgroundColor('#F1F7F4')
      .borderRadius(14)
      .margin({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, bottom: Tokens.GAP_SM })

      if (this.legalNotice.length > 0) {
        Text(this.legalNotice)
          .fontSize(Tokens.F_CAPTION)
          .fontColor('#9C5147')
          .width('100%')
          .padding({ left: Tokens.SPACE_20, right: Tokens.SPACE_20, bottom: Tokens.GAP_SM })
      }

      Scroll() {
        Column() {
          ForEach(this.legalDoc.sections, (section: LegalSection, index: number) => {
            Column() {
              if (section.heading.length > 0) {
                Text(section.heading)
                  .fontSize(section.level === 1 ? Tokens.F_BODY : Tokens.F_LABEL)
                  .fontWeight(section.level === 1 ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(section.level === 1 ? Tokens.TEXT_PRIMARY : Tokens.MIST_TEAL)
                  .width('100%')
                  .margin({ bottom: 6 })
              }
              if (section.body.length > 0) {
                Text(section.body)
                  .fontSize(13)
                  .lineHeight(21)
                  .fontColor(Tokens.TEXT_SECONDARY)
                  .width('100%')
                  .copyOption(CopyOptions.LocalDevice)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ bottom: Tokens.SPACE_12 })
          }, (section: LegalSection, index: number) => index.toString())

          Button('在线查看全文')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(42)
            .fontSize(Tokens.F_LABEL)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.MIST_TEAL)
            .backgroundColor('#EEF5F2')
            .margin({ top: Tokens.GAP_SM })
            .onClick(() => {
              this.openLegalOnline();
            })
          Text(this.legalInfo.onlineUrl)
            .fontSize(10)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 28 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .padding({ left: Tokens.SPACE_20, right: Tokens.SPACE_20 })
    }
    .width('100%')
    .height('92%')
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: 26, topRight: 26 })
  }

  @Builder
  homeSettingsPanel() {
    HomeContentSettings({ onClose: () => { this.homeContentOpen = false; } })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Top }) {
      Scroll(this.scroller) {
      Column() {
        Column() {
          Row() {
            Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '?')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor(Tokens.MIST_TEAL)
              .width(56)
              .height(56)
              .textAlign(TextAlign.Center)
              .backgroundColor(Tokens.TINT_TEAL)
              .borderRadius(28)

            Column() {
              Row() {
                Text(this.userName)
                  .fontSize(Tokens.F_HEADING)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Tokens.TEXT_PRIMARY)
                if (this.roleLabel.length > 0) {
                  Text(this.roleLabel)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.MIST_TEAL)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(Tokens.TINT_TEAL)
                    .borderRadius(Tokens.RADIUS_PILL)
                    .margin({ left: 8 })
                }
              }

              Text('学号 ' + this.maskedSid + (this.isAdmin ? ' · 管理员' : ''))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: Tokens.SPACE_16 })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)

        Column() {
          Row() {
            Text('云同步')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.syncState.length > 0 ? this.syncState : '未同步')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.TEXT_TERTIARY)
            Text('立即同步')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.MIST_TEAL)
              .margin({ left: Tokens.SPACE_16 })
              .onClick(() => {
                this.onSyncNow();
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Text('昵称')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.nick.length > 0 ? this.nick : '未设置')
              .fontSize(Tokens.F_LABEL)
              .fontColor(this.nick.length > 0 ? Tokens.TEXT_SECONDARY : Tokens.TEXT_TERTIARY)
            Text(this.nickEditing ? '取消' : '编辑')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.MIST_TEAL)
              .margin({ left: Tokens.SPACE_16 })
              .onClick(() => {
                this.nickEditing = !this.nickEditing;
                this.nickDraft = this.nick;
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })

          if (this.nickEditing) {
            Row({ space: Tokens.GAP_SM }) {
              TextInput({ text: this.nickDraft, placeholder: '昵称（≤16 字，可留空清除）' })
                .layoutWeight(1)
                .height(40)
                .backgroundColor(Tokens.BG)
                .fontSize(Tokens.F_CAPTION)
                .borderRadius(8)
                .onChange((value: string) => {
                  this.nickDraft = value;
                })
              Button('保存')
                .height(36)
                .fontSize(Tokens.F_CAPTION)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.saveNick();
                })
            }
            .width('100%')
            .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, bottom: Tokens.SPACE_12 })
          }
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.row('通知与提醒', '「通知」工具', false)
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Column() {
              Text('消息推送')
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
              Text(this.pushStatusText())
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pushOn })
              .selectedColor(Tokens.MIST_TEAL)
              .enabled(!this.pushBusy)
              .onChange((isOn: boolean) => {
                this.togglePush(isOn);
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
          if (this.pushNotice.length > 0) {
            Text(this.pushNotice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
              .width('100%')
              .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, bottom: Tokens.SPACE_10 })
          }
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.notifySettingsRow()
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('首页内容', '外观与天气', () => { this.homeContentOpen = true; })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('桌面服务卡片', '预览与添加', () => {
            try {
              formProvider.openFormManager({
                bundleName: 'com.furina.classtools', abilityName: 'DeskFormAbility',
                parameters: { 'ohos.extra.param.key.form_dimension': 2, 'ohos.extra.param.key.form_name': 'home',
                  'ohos.extra.param.key.module_name': 'entry' }
              });
            } catch (_) {
              showFeedback(this.getUIContext(), '请在桌面长按应用图标，选择服务卡片');
            }
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Column() {
              Row({ space: 6 }) {
                Text('华为账号')
                  .fontSize(Tokens.F_BODY)
                  .fontColor(Tokens.TEXT_PRIMARY)
                Text(this.hwItems.length > 0 ? '已绑定 ' + this.hwItems.length + ' 个' : '未绑定')
                  .fontSize(10)
                  .fontColor(this.hwItems.length > 0 ? '#3F6F66' : Tokens.TEXT_TERTIARY)
                  .backgroundColor(this.hwItems.length > 0 ? '#E4F0EB' : '#ECEFED')
                  .borderRadius(Tokens.RADIUS_PILL)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              Text('绑定后可用华为账号一键登录，最多 3 个')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button(this.hwBusy ? '处理中…' : '绑定')
              .height(30)
              .fontSize(13)
              .backgroundColor(Tokens.MIST_TEAL)
              .fontColor('#FFFFFF')
              .borderRadius(15)
              .enabled(!this.hwBusy)
              .onClick(() => {
                this.bindHuawei();
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
          if (this.hwItems.length === 0) {
            Text('暂未绑定华为账号，绑定后可免输学号快捷登录。')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, bottom: Tokens.SPACE_12 })
          }
          ForEach(this.hwItems, (item: BindItem) => {
            Row() {
              Column() {
                Text(item.masked())
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_PRIMARY)
                Text(item.device.length > 0 ? item.device : '华为账号')
                  .fontSize(10)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(this.hwBusy ? '请稍候' : '解绑')
                .fontSize(12)
                .fontColor(Tokens.DANGER)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor('#FBEFEC')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.confirmUnbind(item);
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16 })
          }, (item: BindItem) => item.openId)
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          if (this.isAdmin) {
            this.linkRow('统计', '访问次数 · 登录端 · 设备', () => {
              this.onOpenTool('stats');
            })
            Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          }
          this.linkRow('扫一扫', '网页扫码登录 · 抽签核验 · 任务分享', () => {
            this.onOpenTool('scan');
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('诊断', '服务健康 · 设备自检', () => {
            this.onOpenTool('diag');
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('使用说明', '各功能用法速览', () => {
            this.onOpenTool('usage');
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('隐私政策', 'V1.0', () => {
            this.openLegal(LegalTexts.PRIVACY);
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('用户协议', 'V1.0', () => {
            this.openLegal(LegalTexts.TERMS);
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow('更新说明', 'v' + CloudConfig.APP_VERSION, () => {
            AlertDialog.show({
              title: '枫丹工具箱 ' + CloudConfig.APP_VERSION,
              message: CloudConfig.RELEASE_NOTES,
              confirm: { value: '知道了', action: () => {} }
            });
          })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.linkRow(this.updateBusy ? '检查更新中…' : '检查更新',
            'v' + CloudConfig.APP_VERSION, () => {
              this.checkUpdate();
            })
        }
        .width('100%')
        .margin({ top: Tokens.SPACE_16 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)

        Column() {
          Row() {
            Text('退出登录')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.DANGER)
          }
          .width('100%')
          .height(52)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onLogout();
          })
        }
        .width('100%')
        .margin({ top: Tokens.SPACE_16 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)

        Row() {
          BrandMark({ markSize: 16 })
          Text('枫丹工具箱 · HarmonyOS ' + CloudConfig.APP_VERSION)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 24, bottom: 12 })
      }
      .width('100%')
      .constraintSize({ maxWidth: Breakpoints.isWide(this.layoutWidth) ? 880 : 720 })
      .padding({
        left: PageInsets.HORIZONTAL,
        right: PageInsets.HORIZONTAL,
        top: Tokens.GAP_SM,
        bottom: Breakpoints.contentBottomSpace(this.layoutWidth)
      })
    }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(Color.Transparent)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const next: number = Number(newArea.width);
        if (Math.abs(next - this.layoutWidth) > 1) {
          this.layoutWidth = next;
        }
      })
      .onDidScroll(() => {
        const offset: number = this.scroller.currentOffset().yOffset;
        const next: number = offset > 0 ? Math.min(1, offset / 48) : 0;
        if (Math.abs(next - this.topFade) > 0.02) {
          this.topFade = next;
        }
      })

      Column()
        .width('100%')
        .height(96)
        .linearGradient({
          angle: 180,
          colors: [
            ['#FFF6F7F8', 0.0],
            ['#B8F6F7F8', 0.45],
            ['#00F6F7F8', 1.0]
          ]
        })
        .opacity(this.topFade)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.notifyOpen) {
        Column() {
          this.notifyPanel()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#55000000')
        .onClick(() => {
          this.notifyOpen = false;
        })
      }
      if (this.legalOpen) {
        Column() {
          this.legalPanel()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#55000000')
        .onClick(() => {
          this.legalOpen = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.homeContentOpen, this.homeSettingsPanel(), {
      height: SheetSize.LARGE, dragBar: true, showClose: false, backgroundColor: Tokens.SHEET
    })
  }
}
