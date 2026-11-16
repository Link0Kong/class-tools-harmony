import { VerifyResult } from '../../data/auth/AuthRepository';
import { Session } from '../../data/session/Session';
import { Services } from '../../app/Services';
import { Tokens } from '../theme/Tokens';
import { BrandMark } from '../components/BrandMark';

/** 身份页（唯一入口）：学号 + 姓名 → 云端班级 token。 */
@Component
export struct IdentityScreen {
  @Prop notice: string = '';
  onSignedIn: (session: Session) => void = () => {
  };

  @State private sid: string = '';
  @State private userName: string = '';
  @State private submitting: boolean = false;
  @State private errorMsg: string = '';

  private canSubmit(): boolean {
    return !this.submitting && this.sid.length === 10 && this.userName.trim().length > 0;
  }

  private async submit(): Promise<void> {
    if (!this.canSubmit()) {
      return;
    }
    this.submitting = true;
    this.errorMsg = '';
    const result: VerifyResult = await Services.auth.verify(this.sid, this.userName);
    this.submitting = false;
    if (result.ok && result.session !== undefined) {
      await Services.sessionStore.save(result.session);
      this.onSignedIn(result.session);
      return;
    }
    this.errorMsg = result.message;
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          BrandMark({ markSize: 28 })
          Blank()
        }
        .width('100%')
        .margin({ top: 28 })

        Text('班级工具站')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 22 })

        Text('学号 + 姓名，进入班级数据')
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 6 })

        Column() {
          Text('学号')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')

          TextInput({ placeholder: '10 位学号', text: this.sid })
            .type(InputType.Number)
            .maxLength(10)
            .height(48)
            .width('100%')
            .margin({ top: 6 })
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
            .margin({ top: 16 })

          TextInput({ placeholder: '与班级名单逐字一致', text: this.userName })
            .maxLength(20)
            .height(48)
            .width('100%')
            .margin({ top: 6 })
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

          Button(this.submitting ? '验证中…' : '进入班级')
            .width('100%')
            .height(48)
            .margin({ top: 20 })
            .backgroundColor(this.canSubmit() ? Tokens.MIST_TEAL : Tokens.tint(Tokens.MIST_TEAL, 0.45))
            .fontColor('#FFFFFF')
            .fontSize(Tokens.F_BODY)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Tokens.RADIUS_PILL)
            .enabled(this.canSubmit())
            .onClick(() => {
              this.submit();
            })
        }
        .width('100%')
        .padding(18)
        .margin({ top: 26 })
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)

        Text('仅本班成员可进入 · 数据来自班级云端')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 18 })

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
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(Tokens.BG)
    .scrollBar(BarState.Off)
  }
}
