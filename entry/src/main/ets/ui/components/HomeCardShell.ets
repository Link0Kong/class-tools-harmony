import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';

/**
 * 工作台卡片外壳：统一圆角、玻璃底、按压反馈与宽度动画。
 *
 * 宽度由父级按断点计算（一行最多两张），这里只负责外观与内容插槽。
 */
@Component
export struct HomeCardShell {
  @Prop cardWidthVp: number = 160;
  @Prop cardHeightVp: number = 150;
  @Prop accentColor: string = Tokens.MIST_TEAL;
  onCardTap: () => void = () => {
  };
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      Row()
        .width('100%')
        .height(3)
        .backgroundColor(Tokens.tint(this.accentColor, 0.55))
        .borderRadius(2)
        .margin({ bottom: 9 })
      Column() {
        this.content()
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(this.cardWidthVp)
    .height(this.cardHeightVp)
    .padding(Tokens.CARD_PADDING)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .shadow({ radius: 14, color: '#0B1C2629', offsetX: 0, offsetY: 4 })
    .clip(true)
    .stateStyles({
      pressed: {
        .scale({ x: 0.985, y: 0.985 })
      }
    })
    .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
    .transition(Motion.popIn())
    .onClick(() => {
      this.onCardTap();
    })
  }
}
