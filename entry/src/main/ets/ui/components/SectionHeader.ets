import { Tokens } from '../theme/Tokens';

/** 分组小标题：左侧标题 + 右侧可选操作。 */
@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop actionText: string = '';
  onAction: () => void = () => {
  };

  build() {
    Row() {
      Text(this.title)
        .fontSize(Tokens.F_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)

      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.MIST_TEAL)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .margin({ bottom: Tokens.GAP_SM })
  }
}
