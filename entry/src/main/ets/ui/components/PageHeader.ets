import { Tokens } from '../theme/Tokens';

/** 工具页统一顶栏：返回 + 标题 + 右侧操作。 */
@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onBack: () => void = () => {
  };
  onAction: () => void = () => {
  };

  build() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(Tokens.TEXT_PRIMARY)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onBack();
        })
        .accessibilityText('返回')

      Text(this.title)
        .fontSize(Tokens.F_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)

      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: 10, right: 10 })
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onAction();
          })
      } else {
        Blank().width(44)
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 4, right: 8, top: 4 })
    .backgroundColor(Tokens.BG)
  }
}
