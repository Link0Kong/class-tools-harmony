import { HomeTools } from '../../data/home/HomeTools';
import { ToolCatalog, ToolCategory, ToolDef } from '../../data/tool/ToolCatalog';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { AppSymbols } from '../theme/AppSymbols';
import { Breakpoints } from '../theme/Breakpoints';
import { SectionHeader } from '../components/SectionHeader';
import { ToolTile } from '../components/ToolTile';

/**
 * 全部工具：按分类分组；配置态可点按加入/移出首页快捷（≤4），
 * 并对已选工具长按拖动排序（List + ForEach.onMove，落位由系统播放动画）。
 *
 * 自适应（2026-11-15 平板/折叠屏断点）：容器宽 <600 → 2 列；600–899 → 3 列；≥900 → 4 列；
 * 内容最大宽度按 [Breakpoints.contentMaxWidth] 居中（手机/平板 880，大屏 960）。
 */
@Component
export struct AllScreen {
  @Prop editing: boolean = false;
  @Prop @Watch('syncOrder') quickIds: string[] = [];
  @State private layoutWidth: number = 0;
  /** 首页工具的就地顺序，用于拖拽落位动画（与父级 quickIds 保持同步）。 */
  @State private order: string[] = [];
  @State private pulse: number = 0;
  onToggleQuick: (id: string) => void = () => {
  };
  onToggleEdit: () => void = () => {
  };
  onOpenTool: (id: string) => void = () => {
  };
  onReorderQuick: (ids: string[]) => void = () => {
  };

  aboutToAppear(): void {
    this.syncOrder();
  }

  syncOrder(): void {
    this.order = this.quickIds.slice();
  }

  private tileWidth(): string {
    return Breakpoints.gridItemWidthPercent(this.layoutWidth);
  }

  private columns(): number {
    return Breakpoints.gridColumns(this.layoutWidth);
  }

  /** 最后一列不足列数时补空位，避免 SpaceBetween 把零散卡片拉到两端。 */
  private fillers(count: number): number[] {
    const columns: number = this.columns();
    const rest: number = count % columns;
    const out: number[] = [];
    if (rest === 0) {
      return out;
    }
    for (let i = 0; i < columns - rest; i++) {
      out.push(i);
    }
    return out;
  }

  private categories(): ToolCategory[] {
    const out: ToolCategory[] = [];
    const candidates: ToolCategory[] = [ToolCategory.STUDY, ToolCategory.CLASS];
    for (let i = 0; i < candidates.length; i++) {
      if (ToolCatalog.byCategory(candidates[i]).length > 0) {
        out.push(candidates[i]);
      }
    }
    return out;
  }

  private quickTools(): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < this.order.length; i++) {
      const tool: ToolDef | undefined = ToolCatalog.byId(this.order[i]);
      if (tool !== undefined && !ToolCatalog.isHidden(tool.id)) {
        out.push(tool);
      }
    }
    return out;
  }

  private isPicked(id: string): boolean {
    return this.order.indexOf(id) >= 0;
  }

  /** 拖拽落位：只调整顺序（数组长度不变），系统据此播放落位动画。 */
  private moveQuick(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.order.length || to >= this.order.length) {
      return;
    }
    const next: string[] = this.order.slice();
    const moved: string[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    this.order = next;
    this.pulse = this.pulse + 1;
    this.onReorderQuick(next);
  }

  /** 配置态点按工具：已选则移出，未选则交给外层加入（满员由外层提示）。 */
  private tapTool(tool: ToolDef): void {
    if (!this.editing) {
      this.onOpenTool(tool.id);
      return;
    }
    this.pulse = this.pulse + 1;
    if (this.isPicked(tool.id)) {
      const next: string[] = [];
      for (let i = 0; i < this.order.length; i++) {
        if (this.order[i] !== tool.id) {
          next.push(this.order[i]);
        }
      }
      this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.softSpring() }, () => {
        this.order = next;
      });
    }
    this.onToggleQuick(tool.id);
  }

  @Builder
  quickChip(tool: ToolDef) {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(tool.symbol)
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
            .fontColor([tool.accent])
            .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
        }
        .width(40)
        .height(40)
        .backgroundColor(Tokens.tint(tool.accent, 0.14))
        .borderRadius(12)

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(AppSymbols.XMARK)
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor([Color.White])
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), this.pulse)
        }
        .width(17)
        .height(17)
        .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.72))
        .borderRadius(9)
        .margin({ top: -5, right: -6 })
        .onClick(() => {
          this.tapTool(tool);
        })
      }

      Text(tool.name)
        .fontSize(11)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(1)
        .margin({ top: Tokens.SPACE_6 })
    }
    .width(70)
    .height(84)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Tokens.GLASS_STRONG)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(16)
  }

  @Builder
  quickPanel() {
    Column() {
      Row() {
        Text('首页工具')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
        Text(this.order.length + '/' + HomeTools.MAX)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ left: Tokens.SPACE_6 })
        Blank()
        Text('长按拖动排序')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: Tokens.GAP })

      if (this.quickTools().length > 0) {
        List({ space: Tokens.GAP_SM }) {
          ForEach(this.quickTools(), (tool: ToolDef) => {
            ListItem() {
              this.quickChip(tool)
            }
            .transition(Motion.popIn())
          }, (tool: ToolDef) => tool.id)
            .onMove((from: number, to: number) => {
              this.moveQuick(from, to);
            })
        }
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(84)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Text('点下方工具即可加入首页快捷')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .height(84)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD_SOFT)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .shadow({ radius: 18, color: Tokens.CARD_SHADOW, offsetX: 0, offsetY: 6 })
    .margin({ bottom: Tokens.GAP_LG })
    .transition(Motion.listItem())
  }

  @Builder
  card(tool: ToolDef) {
    Stack({ alignContent: Alignment.Top }) {
      ToolTile({
        symbol: tool.symbol,
        name: tool.name,
        subtitle: tool.subtitle,
        accent: tool.accent,
        onTap: () => {
          this.tapTool(tool);
        }
      })
      if (this.editing) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.isPicked(tool.id) ? AppSymbols.CHECKMARK : AppSymbols.PLUS)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.isPicked(tool.id) ? Color.White : Tokens.MIST_TEAL])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.pulse)
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), this.pulse)
        }
        .width(22)
        .height(22)
        .backgroundColor(this.isPicked(tool.id) ? Tokens.MIST_TEAL : Tokens.tint('#FFFFFF', 0.86))
        .border({ width: 0.5, color: this.isPicked(tool.id) ? Tokens.MIST_TEAL : Tokens.CARD_EDGE })
        .borderRadius(11)
        .margin({ top: -4, right: -4 })
        .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
        .transition(Motion.popIn())
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          if (this.editing) {
            this.quickPanel()
          }

          ForEach(this.categories(), (category: ToolCategory) => {
            Column() {
              SectionHeader({ title: category })
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                ForEach(ToolCatalog.byCategory(category), (tool: ToolDef) => {
                  Column() {
                    this.card(tool)
                  }
                  .width(this.tileWidth())
                  .margin({ bottom: Tokens.GAP })
                  .border({
                    width: this.editing && this.isPicked(tool.id) ? 1.5 : 0,
                    color: Tokens.tint(tool.accent, 0.55)
                  })
                  .borderRadius(Tokens.RADIUS_CARD)
                  .scale({
                    x: this.editing && this.isPicked(tool.id) ? 0.985 : 1,
                    y: this.editing && this.isPicked(tool.id) ? 0.985 : 1
                  })
                  .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
                }, (tool: ToolDef) => tool.id)
                ForEach(this.fillers(ToolCatalog.byCategory(category).length), (i: number) => {
                  Column()
                    .width(this.tileWidth())
                    .margin({ bottom: Tokens.GAP })
                }, (i: number) => 'fill_' + category + '_' + i)
              }
              .width('100%')
            }
            .width('100%')
            .margin({ bottom: Tokens.GAP_XL })
          }, (category: ToolCategory) => category)
        }
        .width('100%')
        .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.layoutWidth) })
        .padding({
          left: Breakpoints.pagePadding(this.layoutWidth),
          right: Breakpoints.pagePadding(this.layoutWidth),
          top: Tokens.SPACE_12,
          bottom: Breakpoints.contentBottomSpace(this.layoutWidth)
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(Color.Transparent)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const next: number = Number(newArea.width);
        if (Math.abs(next - this.layoutWidth) > 1) {
          this.layoutWidth = next;
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
