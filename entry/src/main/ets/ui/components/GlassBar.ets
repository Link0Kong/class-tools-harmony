import { Tokens } from '../theme/Tokens';

/**
 * 沉浸光感底部操作条。
 *
 * 只用于"悬浮在内容之上"的交互层：半透明玻璃背板 + 背景模糊 + 发丝高光边，
 * 与内容区拉开 Z 轴层次；条内按钮统一为胶囊，避免多个实色按钮并列造成的割裂感。
 */
@Component
export struct GlassBar {
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      Row({ space: Tokens.GAP_SM }) {
        this.content()
      }
      .width('100%')
      .padding({
        left: Tokens.SPACE_12,
        right: Tokens.SPACE_12,
        top: Tokens.SPACE_10,
        bottom: Tokens.SPACE_10
      })
      .backgroundColor(Tokens.ACTION_BAR)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: Tokens.CARD_EDGE })
      .borderRadius(Tokens.RADIUS_FLOAT)
    }
    .width('100%')
    .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: Tokens.GAP })
  }
}
