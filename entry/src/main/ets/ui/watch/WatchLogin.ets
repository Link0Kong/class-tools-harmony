import { common } from '@kit.AbilityKit';
import { Services } from '../../app/Services';
import { AccountBindingRepository, HwLoginResult } from '../../data/account/AccountBindingRepository';
import { HuaweiAccount } from '../../data/account/HuaweiAccount';
import { Session } from '../../data/session/Session';
import { VerifyResult } from '../../data/auth/AuthRepository';
import { Tokens } from '../theme/Tokens';
import { Breakpoints } from '../theme/Breakpoints';

/** 手表登录：优先华为账号（已绑定学号），保留学号+姓名兜底；圆屏按窗口尺寸自适应。 */
@Component
export struct WatchLogin {
  @Prop notice: string = '';
  onSignedIn: (session: Session) => void = () => {
  };

  @State private sid: string = '';
  @State private name: string = '';
  @State private errorMsg: string = '';
  @State private busy: boolean = false;
  @State private hwBusy: boolean = false;
  @State private screenH: number = 400;

  private px(base: number): number {
    const h: number = this.screenH > 0 ? this.screenH : 400;
    const factor: number = Math.max(0.82, Math.min(1.15, h / 400));
    return Math.round(base * factor);
  }

  private async huaweiLogin(): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    this.errorMsg = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const openId: string = await HuaweiAccount.openId(context);
      const result: HwLoginResult = await AccountBindingRepository.login(openId);
      if (result.session !== undefined) {
        this.onSignedIn(result.session as Session);
      } else {
        this.errorMsg = result.reason.length > 0 ? result.reason : '该华为账号尚未绑定学号';
      }
    } catch (e) {
      this.errorMsg = HuaweiAccount.message(e as Object);
    }
    this.hwBusy = false;
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    const result: VerifyResult = await Services.auth.verify(this.sid, this.name);
    this.busy = false;
    if (result.ok && result.session !== undefined) {
      this.onSignedIn(result.session as Session);
    } else {
      this.errorMsg = result.message;
    }
  }

  build() {
    Scroll() {
      Column({ space: this.px(4) }) {
        Text('枫丹工具箱')
          .fontSize(this.px(16))
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)

        Button(this.hwBusy ? '华为账号验证中…' : '华为账号登录')
          .width('100%')
          .height(this.px(34))
          .fontSize(this.px(13))
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .borderRadius(this.px(17))
          .enabled(!this.hwBusy)
          .onClick(() => {
            this.huaweiLogin();
          })

        Text('或 学号 + 姓名')
          .fontSize(this.px(10))
          .fontColor('#6E747A')
          .margin({ top: this.px(1) })

        TextInput({ text: this.sid, placeholder: '10 位学号' })
          .type(InputType.Number)
          .maxLength(10)
          .height(this.px(38))
          .width('100%')
          .fontSize(this.px(12))
          .padding({ left: 10, right: 10, top: 0, bottom: 0 })
          .backgroundColor('#1C1C1E')
          .fontColor('#FFFFFF')
          .borderRadius(this.px(8))
          .onChange((v: string) => {
            this.sid = v;
          })
        TextInput({ text: this.name, placeholder: '姓名' })
          .height(this.px(38))
          .width('100%')
          .fontSize(this.px(12))
          .padding({ left: 10, right: 10, top: 0, bottom: 0 })
          .backgroundColor('#1C1C1E')
          .fontColor('#FFFFFF')
          .borderRadius(this.px(8))
          .onChange((v: string) => {
            this.name = v;
          })

        if (this.errorMsg.length > 0 || this.notice.length > 0) {
          Text(this.errorMsg.length > 0 ? this.errorMsg : this.notice)
            .fontSize(this.px(10))
            .fontColor(this.errorMsg.length > 0 ? '#E8A87C' : '#9AA0A6')
            .maxLines(2)
            .textAlign(TextAlign.Center)
        }

        Button(this.busy ? '验证中…' : '用学号进入')
          .width('100%')
          .height(this.px(32))
          .fontSize(this.px(12))
          .backgroundColor('#2A2D31')
          .fontColor('#FFFFFF')
          .borderRadius(this.px(16))
          .enabled(!this.busy)
          .onClick(() => {
            this.submit();
          })

        Text('在手表上输入较慢，建议先用手机完成身份验证')
          .fontSize(this.px(8))
          .fontColor('#5A5F63')
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .margin({ top: this.px(1) })
      }
      .width('100%')
      .padding({ left: Breakpoints.WATCH_HORIZONTAL, right: Breakpoints.WATCH_HORIZONTAL,
        top: Breakpoints.WATCH_VERTICAL, bottom: Breakpoints.WATCH_VERTICAL })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const h: number = Number(newValue.height);
      if (h > 0 && Math.abs(h - this.screenH) > 1) {
        this.screenH = h;
      }
    })
  }
}
