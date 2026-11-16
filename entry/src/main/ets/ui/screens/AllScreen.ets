import { ToolCatalog, ToolCategory, ToolDef } from '../../data/tool/ToolCatalog';
import { Tokens } from '../theme/Tokens';
import { Breakpoints } from '../theme/Breakpoints';
import { SectionHeader } from '../components/SectionHeader';
import { ToolTile } from '../components/ToolTile';

/**
 * 全部工具：按分类分组；编辑态点按可加入/移出首页快捷（≤4）。
 *
 * 自适应（2026-11-15 平板/折叠屏断点）：容器宽 <600 → 2 列；600–899 → 3 列；≥900 → 4 列；
 * 内容最大宽度按 [Breakpoints.contentMaxWidth] 居中（手机/平板 880，大屏 960）。
 */
@Component
export struct AllScreen {
  @Prop editing: boolean = false;
  @Prop quickIds: string[] = [];
  @State private layoutWidth: number = 0;
  onToggleQuick: (id: string) => void = () => {
  };
  onToggleEdit: () => void = () => {
  };
  onOpenTool: (id: string) => void = () => {
  };

  private tileWidth(): string {
    return Breakpoints.gridItemWidthPercent(this.layoutWidth);
  }

  private columns(): number {
    return Breakpoints.gridColumns(this.layoutWidth);
  }

  private categories(): ToolCategory[] {
    return [ToolCategory.STUDY, ToolCategory.CLASS, ToolCategory.SYSTEM];
  }

  @Builder
  card(tool: ToolDef) {
    Stack({ alignContent: Alignment.TopEnd }) {
      ToolTile({
        glyph: tool.glyph,
        name: tool.name,
        subtitle: tool.subtitle,
        accent: tool.accent,
        onTap: () => {
          if (this.editing) {
            this.onToggleQuick(tool.id);
          } else {
            this.onOpenTool(tool.id);
          }
        }
      })
      if (this.editing && this.quickIds.indexOf(tool.id) >= 0) {
        Text('✓')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .backgroundColor(Tokens.MIST_TEAL)
          .borderRadius(11)
          .margin({ top: -4, right: -4 })
      }
    }
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Text('全部工具')
            .fontSize(Tokens.F_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
          Blank()
          Text(this.editing ? '完成' : '编辑首页')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.MIST_TEAL)
            .padding({ left: 10, right: 4, top: 8, bottom: 8 })
            .onClick(() => {
              this.onToggleEdit();
            })
        }
        .width('100%')
        .margin({ top: 20 })

        Text(this.editing
          ? '点工具加入或移出首页快捷（最多 4 个）'
          : ToolCatalog.ALL.length + ' 个工具 · ' + this.columns() + ' 列 · 与网页/小程序/安卓同一套云端契约')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.editing ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 6, bottom: 20 })

        ForEach(this.categories(), (category: ToolCategory) => {
          Column() {
            SectionHeader({ title: category })
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(ToolCatalog.byCategory(category), (tool: ToolDef) => {
                Column() {
                  this.card(tool)
                }
                .width(this.tileWidth())
                .margin({ bottom: 10 })
              }, (tool: ToolDef) => tool.id)
            }
            .width('100%')
          }
          .width('100%')
          .margin({ bottom: 18 })
        }, (category: ToolCategory) => category)
      }
      .width('100%')
      .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.layoutWidth) })
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: Tokens.BREATH_TOP, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(Tokens.BG)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
