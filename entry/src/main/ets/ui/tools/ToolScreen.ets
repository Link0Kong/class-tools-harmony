import { ToolCatalog, ToolDef } from '../../data/tool/ToolCatalog';
import { Tokens } from '../theme/Tokens';
import { Breakpoints } from '../theme/Breakpoints';
import { PageHeader } from '../components/PageHeader';
import { AmbientBackdrop } from '../components/AmbientBackdrop';
import { RosterScreen } from './RosterScreen';
import { DrawScreen } from './DrawScreen';
import { GroupScreen } from './GroupScreen';
import { FitScreen } from './FitScreen';
import { ClassWebTool } from './ClassWebTool';
import { TimetableScreen } from './TimetableScreen';
import { PowerScreen } from './PowerScreen';
import { WaterScreen } from './WaterScreen';
import { VoteScreen } from './VoteScreen';
import { PptScreen } from './PptScreen';
import { RollScreen } from './RollScreen';
import { DiagScreen } from './DiagScreen';
import { StatsScreen } from './StatsScreen';
import { JwScreen } from './JwScreen';
import { MapScreen } from './MapScreen';
import { FileTransferScreen } from './FileTransferScreen';
import { UsageScreen } from './UsageScreen';
import { AppGlobal } from '../../app/AppGlobal';

/**
 * 工具页路由。
 *
 * - `draw` / `group` / `roster`：已原生实现；
 * - 其余：占位骨架（逐个替换）。
 */
@Component
export struct ToolScreen {
  @Prop toolId: string = '';
  @Prop mapRoom: string = '';
  @State private topInset: number = 0;
  @State private layoutWidth: number = 0;
  private scroller: Scroller = new Scroller();
  onClose: () => void = () => {
  };
  onOpenMap: (room: string) => void = () => {};

  aboutToAppear(): void {
    this.topInset = px2vp(AppGlobal.statusBarPx);
  }

  private tool(): ToolDef | undefined {
    return ToolCatalog.byId(this.toolId);
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      AmbientBackdrop()
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)

    Column() {
    if (this.toolId === 'roster') {
      RosterScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'draw') {
      DrawScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'group') {
      GroupScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'fit') {
      FitScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'hw' || this.toolId === 'nt') {
      ClassWebTool({
        toolId: this.toolId,
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'tt') {
      TimetableScreen({
        onOpenMap: this.onOpenMap,
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'power') {
      PowerScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'water') {
      WaterScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'vote') {
      VoteScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'ppt') {
      PptScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'roll') {
      RollScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'stats') {
      StatsScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'diag') {
      DiagScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'jw') {
      JwScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'map') {
      MapScreen({
        room: this.mapRoom,
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'file') {
      FileTransferScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else if (this.toolId === 'usage') {
      UsageScreen({
        onClose: () => {
          this.onClose();
        }
      })
    } else {
      PageHeader({
      progress: this.headerFade,
        title: this.tool() !== undefined ? this.tool()!.name : '工具',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        }
      }) {
        Column() {
        Scroll(this.scroller) {
          Column() {
            Column() {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph(this.tool() !== undefined ? this.tool()!.symbol : $r('sys.symbol.info_circle'))
                  .fontSize(30)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.tool() !== undefined ? this.tool()!.accent : Tokens.MIST_TEAL])
                  .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
              }
              .width(64)
              .height(64)
              .backgroundColor(Tokens.tint(this.tool() !== undefined ? this.tool()!.accent : Tokens.MIST_TEAL, 0.12))
              .borderRadius(20)

              Text(this.tool() !== undefined ? this.tool()!.subtitle : '')
                .fontSize(Tokens.F_LABEL)
                .fontColor(Tokens.TEXT_SECONDARY)
                .margin({ top: 12 })

              Text('M2 原生实现中')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(Tokens.TINT_SAND)
                .borderRadius(Tokens.RADIUS_PILL)
                .margin({ top: 10 })
            }
            .width('100%')
            .padding({ top: 20, bottom: 24 })

            Column() {
              Text('计划功能')
                .fontSize(Tokens.F_LABEL)
                .fontColor(Tokens.TEXT_SECONDARY)
                .width('100%')
                .margin({ bottom: 8 })

              ForEach(this.tool() !== undefined ? this.tool()!.features : [], (feature: string) => {
                Row() {
                  Circle()
                    .width(5)
                    .height(5)
                    .fill(Tokens.TEXT_TERTIARY)
                  Text(feature)
                    .fontSize(Tokens.F_BODY)
                    .fontColor(Tokens.TEXT_PRIMARY)
                    .layoutWeight(1)
                    .margin({ left: 10 })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }, (feature: string) => feature)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Tokens.CARD)
            .border({ width: 0.5, color: Tokens.CARD_EDGE })
            .borderRadius(Tokens.RADIUS_CARD)
          }
          .width('100%')
          .constraintSize({ maxWidth: 720 })
          .padding({ left: Breakpoints.pagePadding(this.layoutWidth), right: Breakpoints.pagePadding(this.layoutWidth), bottom: Tokens.GAP_XL })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .onDidScroll((offset: number) => {
          const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
          if (Math.abs(next - this.headerFade) > 0.03) {
            this.headerFade = next;
          }
        })
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0 })
      }
    }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: Breakpoints.toolContentMaxWidth(this.layoutWidth) })
    .padding({ top: this.topInset })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
