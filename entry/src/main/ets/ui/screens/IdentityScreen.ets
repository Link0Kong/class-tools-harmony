import { VerifyResult } from '../../data/auth/AuthRepository';
import { Session } from '../../data/session/Session';
import { Services } from '../../app/Services';
import { AppGlobal } from '../../app/AppGlobal';
import { Tokens } from '../theme/Tokens';
import { BrandMark } from '../components/BrandMark';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HwAuthInfo, HuaweiAccount, HwPrefetchResult } from '../../data/account/HuaweiAccount';
import { AccountBindingRepository, HwLoginResult } from '../../data/account/AccountBindingRepository';

/** 《华为账号用户认证协议》：一键登录页必须可查看。 */
const HW_AUTH_TERMS: string =
  'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN';

/**
 * 身份页（唯一入口）。
 *
 * 按华为账号开放登录规范设计：
 * - 品牌标志 + 华为账号匿名手机号 + 固定文案「华为账号绑定号码」；
 * - 「华为账号一键登录」是首个登录选项，学号登录放在其下方；
 * - 展示《华为账号用户认证协议》并可查看详情；
 * - 华为账号未绑定学号时自动弹出学号认证，认证成功后完成绑定。
 */
@Component
export struct IdentityScreen {
  @Prop notice: string = '';
  onSignedIn: (session: Session) => void = () => {
  };

  @State private sid: string = '';
  @State private userName: string = '';
  @State private submitting: boolean = false;
  @State private hwBusy: boolean = false;
  @State private errorMsg: string = '';
  @State private hwNotice: string = '';
  @State private topInset: number = 0;
  @State private agreed: boolean = false;
  @State private hwPhone: string = '';
  @State private hwPrefetching: boolean = true;
  @State private hwPrefetchMsg: string = '';

  @State private sheetOpen: boolean = false;
  @State private sheetNotice: string = '';
  private pendingOpenId: string = '';

  aboutToAppear(): void {
    this.topInset = px2vp(AppGlobal.statusBarPx);
    this.prefetchHuawei();
  }

  /** 打开登录页即预取华为账号信息（匿名手机号），点击登录前即可确认账号。 */
  private async prefetchHuawei(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    this.hwPrefetching = true;
    this.hwPrefetchMsg = '';
    const result: HwPrefetchResult = await HuaweiAccount.prefetch(context);
    this.hwPrefetching = false;
    if (result.info !== undefined && result.info.anonymousPhone.length > 0) {
      this.hwPhone = result.info.anonymousPhone;
      return;
    }
    if (result.notSignedIn) {
      this.hwPrefetchMsg = '未登录华为账号，请先在系统设置登录，或使用学号登录';
      return;
    }
    if (result.message.length > 0) {
      this.hwPrefetchMsg = result.message;
      return;
    }
    this.hwPrefetchMsg = '未获取到华为账号绑定号码，仍可尝试一键登录';
  }

  private canSubmit(): boolean {
    return !this.submitting && this.sid.length === 10 && this.userName.trim().length > 0;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // toast 失败不影响主流程
    }
  }

  private ensureAgreed(): boolean {
    if (this.agreed) {
      return true;
    }
    this.toast('请先阅读并同意《华为账号用户认证协议》');
    return false;
  }

  private openAgreement(link: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.openLink(link).catch((error: BusinessError) => {
      this.toast('无法打开协议页面，请稍后重试');
    });
  }

  private phoneText(): string {
    if (this.hwPrefetching) {
      return '正在获取华为账号…';
    }
    return this.hwPhone.length > 0 ? this.hwPhone : '华为账号';
  }

  private phoneHint(): string {
    if (this.hwPrefetchMsg.length > 0) {
      return this.hwPrefetchMsg;
    }
    if (this.hwPhone.length > 0) {
      return '请确认是本人账号后点击下方登录';
    }
    return '点击丢键登录后显示绑定号码';
  }

  private async quickLoginWithHuawei(): Promise<void> {
    if (this.hwBusy || this.submitting) {
      return;
    }
    if (!this.ensureAgreed()) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    this.hwBusy = true;
    this.hwNotice = '';
    this.errorMsg = '';
    try {
      const info: HwAuthInfo = await HuaweiAccount.authorize(context);
      if (info.anonymousPhone.length > 0) {
        this.hwPhone = info.anonymousPhone;
      }
      const openId: string = info.openId.trim();
      if (openId.length === 0) {
        this.hwNotice = '未获取到华为账号标识，请使用学号登录';
        return;
      }
      const login: HwLoginResult = await AccountBindingRepository.login(openId);
      if (login.session !== undefined) {
        await Services.sessionStore.save(login.session);
        this.onSignedIn(login.session);
        return;
      }
      if (login.unbound) {
        this.pendingOpenId = openId;
        this.sid = '';
        this.userName = '';
        this.errorMsg = '';
        this.sheetNotice = '当前华为账号尚未绑定学号，认证成功后将自动完成绑定，下次可一键登录';
        this.sheetOpen = true;
        return;
      }
      this.hwNotice = login.reason.length > 0 ? login.reason : '华为账号登录失败，请稍后重试';
    } catch (e) {
      this.hwNotice = HuaweiAccount.message(e as Object);
    } finally {
      this.hwBusy = false;
    }
  }

  private openStudentSheet(): void {
    if (this.hwBusy || this.submitting) {
      return;
    }
    if (!this.ensureAgreed()) {
      return;
    }
    this.pendingOpenId = '';
    this.sheetNotice = '';
    this.errorMsg = '';
    this.sheetOpen = true;
  }

  private closeSheet(): void {
    if (this.submitting) {
      return;
    }
    this.sheetOpen = false;
    this.errorMsg = '';
    this.pendingOpenId = '';
  }

  private async submit(): Promise<void> {
    if (!this.canSubmit()) {
      return;
    }
    this.submitting = true;
    this.errorMsg = '';
    const bindOpenId: string = this.pendingOpenId;
    const result: VerifyResult = await Services.auth.verify(this.sid, this.userName);
    if (!result.ok || result.session === undefined) {
      this.submitting = false;
      this.errorMsg = result.message;
      return;
    }
    let bindError: string = '';
    if (bindOpenId.length > 0) {
      bindError = await AccountBindingRepository.bind(bindOpenId, 'phone');
    }
    await Services.sessionStore.save(result.session);
    this.submitting = false;
    this.sheetOpen = false;
    this.pendingOpenId = '';
    if (bindError.length > 0) {
      this.toast('已登录，但华为账号自动绑定失败：' + bindError);
    }
    this.onSignedIn(result.session);
  }

  @Builder
  brandBlock() {
    Column() {
      Column() {
        BrandMark({ markSize: 38 })
      }
      .width(76)
      .height(76)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Tokens.CARD_STRONG)
      .borderRadius(24)
      .border({ width: 1, color: Tokens.CARD_EDGE })

      Text('班级工具站')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
        .margin({ top: Tokens.SPACE_16 })

      Text('登录后同步班级数据与常用工具')
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_SECONDARY)
        .margin({ top: Tokens.SPACE_6 })
    }
    .width('100%')
    .margin({ top: 36 })
  }

  @Builder
  huaweiCard() {
    Column() {
      Row() {
        Text('华为账号')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
        Blank()
        if (this.hwPrefetching) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(Tokens.MIST_TEAL)
        } else {
          Text('安全快捷登录')
            .fontSize(11)
            .fontColor(Tokens.MIST_TEAL)
            .padding({ left: Tokens.GAP_SM, right: Tokens.GAP_SM, top: Tokens.SPACE_2, bottom: Tokens.SPACE_2 })
            .backgroundColor(Tokens.TINT_TEAL)
            .borderRadius(Tokens.RADIUS_PILL)
        }
      }
      .width('100%')

      Text(this.phoneText())
        .fontSize(26)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: Tokens.SPACE_12 })

      Text('华为账号绑定号码')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 4 })

      Text(this.phoneHint())
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(Tokens.SPACE_16)
    .margin({ top: Tokens.GAP_XL })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .border({ width: 1, color: Tokens.CARD_EDGE })
  }

  @Builder
  huaweiLoginButton() {
    Button(this.hwBusy ? '正在登录…' : '华为账号一键登录')
      .width('100%')
      .height(52)
      .margin({ top: Tokens.SPACE_16 })
      .backgroundColor('#FFFFFF')
      .fontColor(Tokens.TEXT_PRIMARY)
      .fontSize(17)
      .fontWeight(FontWeight.Medium)
      .borderRadius(Tokens.RADIUS_PILL)
      .border({ width: 1, color: Tokens.DIVIDER })
      .shadow({ radius: 14, color: '#141C2629', offsetY: 6 })
      .enabled(!this.hwBusy && !this.submitting)
      .onClick(() => {
        this.quickLoginWithHuawei();
      })
  }

  @Builder
  agreementRow() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Checkbox({ name: 'login_agree', group: 'login_agree' })
        .select(this.agreed)
        .selectedColor(Tokens.MIST_TEAL)
        .width(18)
        .height(18)
        .margin({ right: Tokens.SPACE_6 })
        .onChange((checked: boolean) => {
          this.agreed = checked;
        })
      Text('我已阅读并同意')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
      Text('《华为账号用户认证协议》')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.MIST_TEAL)
        .onClick(() => {
          this.openAgreement(HW_AUTH_TERMS);
        })
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  studentSheet() {
    Column() {
      Row() {
        Column() {
          Text(this.pendingOpenId.length > 0 ? '绑定学号' : '学号认证')
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Bold)
          Text(this.pendingOpenId.length > 0 ? '华为账号 + 学号，一键登录' : '使用学号与姓名进入班级')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: Tokens.TEXT_GAP })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('关闭')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_TERTIARY)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(Tokens.BG)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.closeSheet();
          })
      }
      .width('100%')

      if (this.sheetNotice.length > 0) {
        Text(this.sheetNotice)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.WARM_SAND)
          .width('100%')
          .padding(Tokens.SPACE_12)
          .backgroundColor(Tokens.TINT_SAND)
          .borderRadius(12)
          .margin({ top: Tokens.SPACE_12 })
      }

      Text('学号')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 16 })

      TextInput({ placeholder: '10 位学号', text: this.sid })
        .type(InputType.Number)
        .maxLength(10)
        .height(48)
        .width('100%')
        .margin({ top: Tokens.SPACE_6 })
        .backgroundColor(Tokens.BG)
        .borderRadius(Tokens.RADIUS_INPUT)
        .fontSize(Tokens.F_BODY)
        .onChange((value: string) => {
          this.sid = value;
          this.errorMsg = '';
        })

      Text('姓名')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: Tokens.SPACE_12 })

      TextInput({ placeholder: '与班级名单逐字一致', text: this.userName })
        .maxLength(20)
        .height(48)
        .width('100%')
        .margin({ top: Tokens.SPACE_6 })
        .backgroundColor(Tokens.BG)
        .borderRadius(Tokens.RADIUS_INPUT)
        .fontSize(Tokens.F_BODY)
        .onChange((value: string) => {
          this.userName = value;
          this.errorMsg = '';
        })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.DANGER)
          .width('100%')
          .margin({ top: 12 })
      }

      Button(this.submitting ? '认证中…'
        : (this.pendingOpenId.length > 0 ? '认证并绑定' : '认证并进入'))
        .width('100%')
        .height(48)
        .margin({ top: Tokens.SPACE_16 })
        .backgroundColor(this.canSubmit() ? Tokens.MIST_TEAL : Tokens.tint(Tokens.MIST_TEAL, 0.45))
        .fontColor('#FFFFFF')
        .fontSize(Tokens.F_BODY)
        .fontWeight(FontWeight.Medium)
        .borderRadius(Tokens.RADIUS_PILL)
        .enabled(this.canSubmit())
        .onClick(() => {
          this.submit();
        })
      Text('仅本班成员可认证 · 通过后可用华为账号一键登录')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 560 })
    .padding({ left: Tokens.SPACE_24, right: Tokens.SPACE_24, top: Tokens.SPACE_20, bottom: Tokens.SPACE_24 })
    .backgroundColor(Tokens.CARD_STRONG)
    .borderRadius({ topLeft: 26, topRight: 26 })
    .onClick(() => {
      // 拦截点击，避免冒泡到遮罩关闭面板
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          this.brandBlock()

          this.huaweiCard()

          this.huaweiLoginButton()

          Button('使用学号登录')
            .width('100%')
            .height(48)
            .margin({ top: 12 })
            .backgroundColor(Color.Transparent)
            .fontColor(Tokens.TEXT_PRIMARY)
            .fontSize(Tokens.F_BODY)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Tokens.RADIUS_PILL)
            .border({ width: 1, color: Tokens.DIVIDER })
            .enabled(!this.hwBusy && !this.submitting)
            .onClick(() => {
              this.openStudentSheet();
            })

          if (this.hwNotice.length > 0) {
            Text(this.hwNotice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.DANGER)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 12 })
          }

          this.agreementRow()

          Text('仅本班成员可进入 · 数据来自班级云端')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: Tokens.SPACE_16 })

          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.WARM_SAND)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 520 })
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: this.topInset, bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .backgroundColor(Color.Transparent)
      .scrollBar(BarState.Off)

      if (this.sheetOpen) {
        Column() {
          Blank()
          this.studentSheet()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeSheet();
        })
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
