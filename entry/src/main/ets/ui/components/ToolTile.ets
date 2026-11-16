import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';

/**
 * 工具卡：单字字形 + 名称 + 副标题（2 行）。
 *
 * 2026-11-15 视觉要求：描述最多两行、卡片最小高度 96vp，常见描述不被截断（与安卓 v4.55 口径一致）。
 */
@Component
export struct ToolTile {
  @Prop glyph: string = '';
  @Prop name: string = '';
  @Prop subtitle: string = '';
  @Prop accent: string = Tokens.MIST_TEAL;
  @Prop compact: boolean = false;
  onTap: () => void = () => {
  };

  private minHeight(): number {
    return this.compact ? 76 : 96;
  }

  build() {
    Row() {
      Text(this.glyph)
        .fontSize(this.compact ? 16 : 18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accent)
        .width(this.compact ? 34 : 40)
        .height(this.compact ? 34 : 40)
        .textAlign(TextAlign.Center)
        .backgroundColor(Tokens.tint(this.accent, 0.12))
        .borderRadius(12)

      Column() {
        Text(this.name)
          .fontSize(this.compact ? 14 : 15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.subtitle)
          .fontSize(this.compact ? 11 : 12)
          .fontColor(Tokens.TEXT_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(this.compact ? 15 : 17)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight() })
    .padding(this.compact ? 10 : 12)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .stateStyles({
      normal: {
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .scale({ x: 0.97, y: 0.97 })
        .opacity(0.92)
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .onClick(() => {
      this.onTap();
    })
    .accessibilityText(this.name + '，' + this.subtitle)
  }
}
