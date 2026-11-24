import { ExportCardSpec, ExportChip, ExportParam } from '../../features/export/ExportCard';
import { Tokens } from '../theme/Tokens';

/**
 * 导出卡 v2 版式（ArkUI 组件实现；规格见 web/tools/tests/export_card_v2_spec.md）。
 *
 * 逻辑宽度 760，白卡 + 渐变底 + 参数配置区 + 结果胶囊 + 斜向平铺水印 + 页脚时间/编号。
 * 通过 `componentSnapshot` 截图为图片（PNG）。
 */
@Component
export struct ExportCardView {
  spec: ExportCardSpec = new ExportCardSpec();

  @State private cardHeight: number = 600;
  private wmCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private drawWatermark(): void {
    const width: number = 716;
    const height: number = this.cardHeight;
    if (height <= 0) {
      return;
    }
    this.wmCtx.clearRect(0, 0, width, height);
    this.wmCtx.globalAlpha = 0.04;
    this.wmCtx.fillStyle = '#23302E';
    this.wmCtx.font = 'bold 15px sans-serif';
    for (let y = -40; y < height + 80; y += 140) {
      for (let x = -120; x < width + 120; x += 300) {
        this.wmCtx.save();
        this.wmCtx.translate(x, y);
        this.wmCtx.rotate(-20 * Math.PI / 180);
        this.wmCtx.fillText('枫丹工具箱', 0, 0);
        this.wmCtx.restore();
      }
    }
  }

  @Builder
  blockTitle(text: string, topMargin: number) {
    Row({ space: 8 }) {
      Rect()
        .width(5)
        .height(5)
        .radius(1.5)
        .fill(Tokens.MIST_TEAL)
      Text(text)
        .fontSize(12.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
    }
    .height(20)
    .alignItems(VerticalAlign.Center)
    .margin({ top: topMargin })
  }

  @Builder
  brandRow() {
    Row({ space: 10 }) {
      Circle().width(6).height(6).fill(Tokens.MIST_TEAL)
      Circle().width(6).height(6).fill(Tokens.SLATE_BLUE)
      Circle().width(6).height(6).fill(Tokens.WARM_SAND)
      Text('枫丹工具箱')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ left: 2 })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  paramCell(param: ExportParam) {
    Row() {
      Text(param.label)
        .fontSize(12.5)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(104)
      Text(param.value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(2)
    }
    .width('50%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  chipView(chip: ExportChip) {
    Row({ space: 4 }) {
      Text('' + chip.n)
        .fontSize(13.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.MIST_TEAL)
      if (chip.nm.length > 0) {
        Text(chip.nm)
          .fontSize(12)
          .fontColor(Tokens.TEXT_SECONDARY)
      }
    }
    .height(30)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E3E9E6' })
    .borderRadius(15)
    .margin({ right: 8, bottom: 8 })
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.wmCtx)
          .width(716)
          .height(this.cardHeight)
          .onReady(() => {
            this.drawWatermark();
          })
          .hitTestBehavior(HitTestMode.None)

        Column() {
          this.brandRow()

          Text(this.spec.title)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 14 })
            .maxLines(1)

          Text(this.spec.subtitle)
            .fontSize(13)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 6 })

          Divider()
            .color('#E6E9E8')
            .strokeWidth(1)
            .margin({ top: 14, bottom: 16 })

          this.blockTitle('参数配置', 0)

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.spec.params, (param: ExportParam) => {
              this.paramCell(param)
            }, (param: ExportParam) => param.label)
          }
          .width('100%')
          .padding(14)
          .margin({ top: 8 })
          .backgroundColor('#F4F8F7')
          .border({ width: 1, color: '#E8EEEC' })
          .borderRadius(14)

          if (this.spec.chips.length > 0) {
            this.blockTitle(this.spec.chipLabel, 18)

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.spec.chips, (chip: ExportChip) => {
                this.chipView(chip)
              }, (chip: ExportChip, index: number) => index + '_' + chip.n)
            }
            .width('100%')
            .margin({ top: 8 })
          }

          if (this.spec.groups.length > 0) {
            this.blockTitle(this.spec.groupLabel, 18)

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.spec.groups, (group: ExportChip[], index: number) => {
                Column() {
                  Row() {
                    Text('第 ' + (index + 1) + ' 组')
                      .fontSize(12.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Tokens.TEXT_PRIMARY)
                    Blank()
                    Text(group.length + ' 人')
                      .fontSize(10.5)
                      .fontColor(Tokens.TEXT_TERTIARY)
                  }
                  .width('100%')

                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(group, (chip: ExportChip, memberIndex: number) => {
                      Text(chip.nm.length > 0 ? chip.n + ' ' + chip.nm : '' + chip.n)
                        .fontSize(12)
                        .fontColor(Tokens.TEXT_PRIMARY)
                        .margin({ right: 10, top: 6 })
                    }, (chip: ExportChip, memberIndex: number) => index + '_' + memberIndex + '_' + chip.n)
                  }
                  .width('100%')
                  .margin({ top: 2 })
                }
                .width('48.5%')
                .padding(12)
                .margin({ bottom: 12 })
                .backgroundColor('#FAFCFB')
                .border({ width: 1, color: '#E8EEEC' })
                .borderRadius(14)
              }, (group: ExportChip[], index: number) => 'group_' + index)
            }
            .width('100%')
            .margin({ top: 8 })
          }

          if (this.spec.lines.length > 0) {
            this.blockTitle(this.spec.linesLabel, 18)

            Column() {
              ForEach(this.spec.lines, (line: string, index: number) => {
                Text(line)
                  .fontSize(12.5)
                  .fontColor(Tokens.TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 4 })
              }, (line: string, index: number) => 'line_' + index)
            }
            .width('100%')
            .margin({ top: 6 })
          }

          if (this.spec.noteLines.length > 0) {
            this.blockTitle(this.spec.noteLabel, 12)
            Column() {
              ForEach(this.spec.noteLines, (line: string) => {
                Text(line)
                  .fontSize(12)
                  .fontColor(Tokens.TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 4 })
              }, (line: string) => line)
            }
            .width('100%')
            .margin({ top: 4 })
          }

          Divider()
            .color('#E6E9E8')
            .strokeWidth(1)
            .margin({ top: 18, bottom: 12 })

          Row() {
            Column() {
              Text(this.spec.footer)
                .fontSize(11.5)
                .fontColor(Tokens.TEXT_TERTIARY)
              Text('编号 ' + this.spec.recordId)
                .fontSize(11)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row({ space: 8 }) {
              Circle().width(5).height(5).fill(Tokens.MIST_TEAL)
              Circle().width(5).height(5).fill(Tokens.SLATE_BLUE)
              Circle().width(5).height(5).fill(Tokens.WARM_SAND)
              Text('枫丹工具箱')
                .fontSize(11.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.MIST_TEAL)
            }
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
        }
        .padding(32)
        .width('100%')
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const raw: Length = newArea.height;
          const height: number = typeof raw === 'number' ? raw : parseFloat(raw as string);
          if (height > 0 && Math.abs(height - this.cardHeight) > 0.5) {
            this.cardHeight = height;
            this.drawWatermark();
          }
        })
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(22)
      .clip(true)
      .border({ width: 1, color: '#E6E9E8' })
    }
    .width(760)
    .padding(22)
    .backgroundColor('#F2F6F4')
    .id('exportCard')
  }
}
