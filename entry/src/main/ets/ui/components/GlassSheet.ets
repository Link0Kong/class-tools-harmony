import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';

/**
 * 沉浸光感弹层容器：半透明蒙层 + 厚玻璃面板。
 *
 * 用于工具页内的自定义抽屉（名单选择、详情、总览等）。
 * 厚材质保证大面积内容可读，顶部圆角与发丝高光边让面板悬浮于内容之上。
 */
@Component
export struct GlassSheet {
  @Prop panelHeight: string = '80%';
  @Prop panelRadius: number = Tokens.RADIUS_FLOAT;
  @Prop surface: ResourceColor = Tokens.SHEET;
  @Prop edge: ResourceColor = Tokens.CARD_EDGE;
  @Prop maxWidth: number = 100000;
  onDismiss?: () => void;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Tokens.SCRIM)
        .onClick(() => { this.onDismiss?.(); })
      Column() {
        this.content()
      }
      .width('100%')
      .constraintSize({ maxWidth: this.maxWidth })
      .height(this.panelHeight)
      .padding(Tokens.SPACE_16)
      .backgroundColor(this.surface)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 0.5, color: this.edge })
      .borderRadius({ topLeft: this.panelRadius, topRight: this.panelRadius })
      .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
    }
    .width('100%')
    .height('100%')
    .transition(Motion.scrim())
    .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
  }
}
