interface CardRow {
  title: string;
  detail: string;
  toolId: string;
  homeworkId: string;
  taskId: string;
  noticeId: string;
}

const storage = new LocalStorage();

@Entry(storage)
@Component
struct DeskCard {
  @LocalStorageProp('heading') heading: string = '枫丹工具箱';
  @LocalStorageProp('summary') summary: string = '';
  @LocalStorageProp('empty') empty: string = '点按打开';
  @LocalStorageProp('toolId') toolId: string = 'home';
  @LocalStorageProp('rows') rows: CardRow[] = [];
  @LocalStorageProp('dim') dim: number = 2;
  @LocalStorageProp('palette') palette: number = 0;

  private fill(): Resource {
    return [$r('app.color.desk_jade_fill'), $r('app.color.desk_blue_fill'),
      $r('app.color.desk_amber_fill'), $r('app.color.desk_lilac_fill')][this.palette];
  }
  private accent(): Resource {
    return [$r('app.color.desk_jade_accent'), $r('app.color.desk_blue_accent'),
      $r('app.color.desk_amber_accent'), $r('app.color.desk_lilac_accent')][this.palette];
  }
  private ink(): Resource {
    return [$r('app.color.desk_jade_ink'), $r('app.color.desk_blue_ink'),
      $r('app.color.desk_amber_ink'), $r('app.color.desk_lilac_ink')][this.palette];
  }

  private open(toolId: string, homeworkId: string = '', taskId: string = '', noticeId: string = ''): void {
    postCardAction(this, {
      action: 'router', abilityName: 'EntryAbility',
      params: { toolId: toolId, homeworkId: homeworkId, taskId: taskId, noticeId: noticeId }
    });
  }

  build() {
    Column() {
      Row() {
        Text(this.heading)
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.accent())
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Circle().width(10).height(10).fill(this.accent())
          if (this.dim !== 2) {
            Text(['青瓷', '海蓝', '琥珀', '丁香'][this.palette]).fontSize(11).fontColor(this.accent()).margin({ left: 4 })
          }
        }
        .padding({ left: 7, right: 7 }).height(24).borderRadius(12).backgroundColor($r('app.color.desk_color_chip'))
        .accessibilityText('切换卡片配色')
        .onClick(() => {
          postCardAction(this, { action: 'message', params: { message: 'palette' } });
        })
      }.width('100%')
      Column() {
        if (this.rows.length === 0) {
          Text(this.empty)
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.ink()).maxLines(2)
        }
        ForEach(this.rows, (row: CardRow, index: number) => {
          Column() {
            Text(row.title)
              .fontSize(index === 0 ? 18 : 15).fontWeight(index === 0 ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.ink()).maxLines(this.dim === 2 ? 2 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (row.detail) {
              Text(row.detail)
                .fontSize(12).fontColor(this.accent()).maxLines(this.dim === 2 ? 2 : 1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%').alignItems(HorizontalAlign.Start).margin({ top: index > 0 ? 5 : 0 })
          .onClick(() => this.open(row.toolId, row.homeworkId, row.taskId, row.noticeId))
        }, (row: CardRow, index: number) => index + '/' + row.title + '/' + row.detail + '/' +
          row.homeworkId + '/' + row.taskId + '/' + row.noticeId)
      }
      .width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center).clip(true)
      if (this.summary.length > 0) {
        Text(this.summary)
          .fontSize(11).fontColor(this.accent()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.fill()).onClick(() => this.open(this.toolId))
  }
}
