import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { PowerRooms, RoomInfo } from '../../data/power/PowerModels';
import {
  WaterMonthStats,
  WaterRecord,
  WaterRecordReview,
  WaterRoomState,
  WaterRules,
  WaterState
} from '../../features/water/WaterModels';
import { WaterCalculator } from '../../features/water/WaterCalculator';
import { WaterCodec } from '../../features/water/WaterCodec';
import { WaterMonth } from '../../features/water/WaterMonth';
import { WaterMutator } from '../../features/water/WaterMutator';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/**
 * 水量工具：4/6 人间 + 按月抄表（读数 → 用量/水费/折合扣电）+ 记录列表 + 规则卡。
 *
 * 数据：`userdata.water = { rooms: { <roomverify>: { p, recs:[{m,r,ts}] } } }`（整段 LWW）。
 * 口径：水 3.03 元/吨、免费 2 吨/人/月、折合扣电 = 水费 ÷ 0.58；无上一条不伪造用量。
 */
@Component
export struct WaterScreen {
  onClose: () => void = () => {
  };

  @State private sel: string = '';
  @State private state: WaterState = new WaterState();
  @State private persons: number = WaterRules.PERSONS_DEFAULT;
  @State private monthText: string = '';
  @State private readingText: string = '';
  @State private errorMsg: string = '';
  @State private notice: string = '';
  @State private confirmReplace: boolean = false;
  @State private picking: boolean = true;
  @State private pickBuilding: string = '13号楼';
  @State private now: number = Date.now();

  aboutToAppear(): void {
    this.now = Date.now();
    this.monthText = WaterMonth.current(this.now);
    const sections: Blob = Services.userdata.currentSections();
    this.state = WaterCodec.fromJson(JsonBlob.get(sections, 'water'));
    const keys: string[] = [];
    this.state.rooms.forEach((room: WaterRoomState, key: string) => {
      keys.push(key);
    });
    if (keys.length > 0) {
      this.sel = keys[0];
      this.picking = false;
      this.pickBuilding = PowerRooms.buildingOf(this.sel);
      this.persons = this.state.roomOrDefault(this.sel).persons;
    }
  }

  private roomLabel(): string {
    return this.sel.length > 0 ? PowerRooms.labelOf(this.sel) : '';
  }

  private roomState(): WaterRoomState {
    return this.state.roomOrDefault(this.sel);
  }

  private stats(): WaterMonthStats {
    return WaterCalculator.stats(this.roomState(), this.monthText, this.now);
  }

  private async persist(): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    next['water'] = WaterCodec.toJson(this.state);
    await Services.userdata.updateCurrent(next);
  }

  private pickRoom(rv: string): void {
    this.sel = rv;
    this.picking = false;
    this.pickBuilding = PowerRooms.buildingOf(rv);
    this.persons = this.state.roomOrDefault(rv).persons;
    this.confirmReplace = false;
    this.errorMsg = '';
    this.notice = '';
    this.monthText = WaterMonth.current(this.now);
  }

  private async onPersons(value: number): Promise<void> {
    this.persons = WaterCodec.normalizePersons(value);
    this.state = WaterMutator.withPersons(this.state, this.sel, this.persons);
    await this.persist();
  }

  private async saveRecord(): Promise<void> {
    this.errorMsg = '';
    if (this.sel.length === 0) {
      this.errorMsg = '请先选择宿舍';
      return;
    }
    const room: WaterRoomState = this.roomState();
    const review: WaterRecordReview = WaterMutator.review(room, this.monthText, this.readingText, Date.now());
    if (!review.valid) {
      this.errorMsg = review.message;
      this.confirmReplace = false;
      return;
    }
    if (review.replaceExisting && !this.confirmReplace) {
      this.confirmReplace = true;
      this.notice = '该月已有记录，再点一次「保存」覆盖';
      return;
    }
    const record: WaterRecord = review.record as WaterRecord;
    this.state = WaterMutator.put(this.state, this.sel, WaterRecordCopy(record));
    await this.persist();
    this.confirmReplace = false;
    this.readingText = '';
    this.notice = record.month + ' 已保存（' + record.reading.toFixed(2) + ' 吨）';
  }

  private async deleteRecord(month: string): Promise<void> {
    this.state = WaterMutator.delete(this.state, this.sel, month);
    await this.persist();
    this.notice = month + ' 记录已删除';
    this.confirmReplace = false;
  }

  @Builder
  buildingChip(building: string) {
    Text(building)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.pickBuilding === building ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.pickBuilding === building ? Tokens.MIST_TEAL : Tokens.CARD)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.pickBuilding = building;
      })
  }

  @Builder
  roomTile(info: RoomInfo) {
    Column() {
      Text(info.room)
        .fontSize(Tokens.F_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.sel === info.rv ? '#FFFFFF' : Tokens.TEXT_PRIMARY)
      Text(this.state.rooms.has(info.rv) ? '已录入' : '未录入')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.sel === info.rv ? '#E8F2EF' : Tokens.TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .width('31%')
    .padding({ top: 12, bottom: 12 })
    .margin({ bottom: 8 })
    .backgroundColor(this.sel === info.rv ? Tokens.MIST_TEAL : Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .onClick(() => {
      this.pickRoom(info.rv);
    })
  }

  @Builder
  personsChip(value: number) {
    Text(value + ' 人间')
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.persons === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.persons === value ? Tokens.SLATE_BLUE : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.onPersons(value);
      })
  }

  @Builder
  statTile(kind: string) {
    Column() {
      Text(this.statValue(kind))
        .fontSize(Tokens.F_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
      Text(this.statLabel(kind))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  private statValue(kind: string): string {
    const stats: WaterMonthStats = this.stats();
    if (kind === 'usage') {
      return WaterCalculator.fmtReading(stats.charge.usage, stats.charge.hasUsage);
    }
    if (kind === 'fee') {
      return WaterCalculator.fmtMoney(stats.charge.fee, stats.charge.hasUsage);
    }
    return WaterCalculator.fmtDegree(stats.charge.degree, stats.charge.hasUsage);
  }

  private statLabel(kind: string): string {
    if (kind === 'usage') {
      return '用量（吨）';
    }
    if (kind === 'fee') {
      return '水费（元）';
    }
    return '折合扣电（度）';
  }

  @Builder
  recordRow(record: WaterRecord) {
    Row() {
      Column() {
        Text(record.month)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text('读数 ' + record.reading.toFixed(2) + ' 吨')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(this.rowUsage(record))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
        Text(this.rowFee(record))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)

      Text('删除')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.DANGER)
        .padding({ left: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.deleteRecord(record.month);
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  private rowUsage(record: WaterRecord): string {
    const charge = WaterCalculator.charge(this.roomState(), record, this.persons);
    return charge.hasUsage ? '用量 ' + charge.usage.toFixed(2) + ' 吨' : '首条';
  }

  private rowFee(record: WaterRecord): string {
    const charge = WaterCalculator.charge(this.roomState(), record, this.persons);
    if (!charge.hasUsage) {
      return '—';
    }
    return '水费 ' + charge.fee.toFixed(2) + ' 元 · ' + charge.degree.toFixed(1) + ' 度';
  }

  @Builder
  entryCard() {
    Column() {
      Row() {
        Text('抄表录入')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(this.roomLabel())
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.MIST_TEAL)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('上月')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.monthText = WaterMonth.shift(WaterMonth.current(Date.now()), -1);
            this.confirmReplace = false;
          })
        Text('本月')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.monthText = WaterMonth.current(Date.now());
            this.confirmReplace = false;
          })
        Text('下月')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.monthText = WaterMonth.shift(WaterMonth.current(Date.now()), 1);
            this.confirmReplace = false;
          })
        Blank()
        Text('当前 ' + this.monthText)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      .margin({ top: 6 })

      Row({ space: 8 }) {
        TextInput({ text: this.monthText, placeholder: 'YYYY-MM' })
          .height(40)
          .layoutWeight(1)
          .backgroundColor(Tokens.BG)
          .borderRadius(8)
          .fontSize(Tokens.F_BODY)
          .onChange((text: string) => {
            this.monthText = text;
            this.confirmReplace = false;
            this.errorMsg = '';
          })
        TextInput({ text: this.readingText, placeholder: '读数（吨）' })
          .type(InputType.NUMBER_DECIMAL)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(Tokens.BG)
          .borderRadius(8)
          .fontSize(Tokens.F_BODY)
          .onChange((text: string) => {
            this.readingText = text;
            this.confirmReplace = false;
            this.errorMsg = '';
          })
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.DANGER)
          .width('100%')
          .margin({ top: 6 })
      }
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.confirmReplace ? Tokens.WARM_SAND : Tokens.MIST_TEAL)
          .width('100%')
          .margin({ top: 6 })
      }

      Button(this.confirmReplace ? '确认覆盖' : '保存')
        .width('100%')
        .height(44)
        .margin({ top: 10 })
        .backgroundColor(this.confirmReplace ? Tokens.WARM_SAND : Tokens.MIST_TEAL)
        .fontColor('#FFFFFF')
        .borderRadius(Tokens.RADIUS_PILL)
        .onClick(() => {
          this.saveRecord();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statsCard() {
    Column() {
      Row() {
        Text(this.stats().month + ' 统计')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('免费 ' + this.stats().charge.free.toFixed(1) + ' 吨')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Row() {
        this.statTile('usage')
        this.statTile('fee')
        this.statTile('degree')
      }
      .width('100%')
      .margin({ top: 10 })

      Text(this.statsSubText())
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  private statsSubText(): string {
    const stats: WaterMonthStats = this.stats();
    if (!stats.charge.hasUsage) {
      return stats.record === undefined ? '本月还没有记录；录入首条后次月可算用量' : '首条记录：下一条起可算用量';
    }
    const parts: string[] = [];
    parts.push('日均 ' + (stats.hasDailyAverage ? stats.dailyAverage.toFixed(2) : '—') + ' 吨');
    if (stats.charge.within) {
      parts.push('定额内');
    } else {
      parts.push('超出 ' + stats.charge.excess.toFixed(2) + ' 吨');
    }
    if (stats.hasDelta) {
      parts.push((stats.deltaVsPreviousMonth >= 0 ? '较上月 +' : '较上月 ') + stats.deltaVsPreviousMonth.toFixed(2) + ' 吨');
    }
    return parts.join(' · ');
  }

  @Builder
  recordsCard() {
    Column() {
      Row() {
        Text('记录')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(this.roomState().records.length + ' 条')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      if (this.roomState().records.length === 0) {
        Text('暂无记录')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.recentRecords(), (record: WaterRecord) => {
          this.recordRow(record)
        }, (record: WaterRecord) => record.month + '_' + record.reading)
      }
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  private recentRecords(): WaterRecord[] {
    const all: WaterRecord[] = this.roomState().records;
    const out: WaterRecord[] = [];
    const start: number = all.length > 12 ? all.length - 12 : 0;
    for (let i = all.length - 1; i >= start; i--) {
      out.push(all[i]);
    }
    return out;
  }

  @Builder
  rulesCard() {
    Column() {
      Text('计费规则')
        .fontSize(Tokens.F_LABEL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
        .width('100%')

      ForEach(WaterCalculator.ruleLines(this.persons), (line: string[]) => {
        Row() {
          Text(line[0])
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width(72)
          Text(line[1])
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 4 })
      }, (line: string[]) => line[0] + line[1])
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      PageHeader({
        title: '水量',
        actionText: this.picking ? '' : '切换',
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.picking = true;
        }
      })

      if (this.picking) {
        Scroll() {
          Column() {
            Text('选择宿舍')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')

            Row() {
              ForEach(PowerRooms.BUILDINGS, (building: string) => {
                this.buildingChip(building)
              }, (building: string) => building)
              Blank()
            }
            .width('100%')
            .margin({ top: 10 })

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(PowerRooms.roomsOfBuilding(this.pickBuilding), (info: RoomInfo) => {
                this.roomTile(info)
              }, (info: RoomInfo) => info.rv + '_' + (this.state.rooms.has(info.rv) ? 'y' : 'n'))
              if (PowerRooms.roomsOfBuilding(this.pickBuilding).length % 3 === 1) {
                Blank().width('31%')
                Blank().width('31%')
              } else if (PowerRooms.roomsOfBuilding(this.pickBuilding).length % 3 === 2) {
                Blank().width('31%')
              }
            }
            .width('100%')
            .margin({ top: 10 })

            if (this.sel.length > 0) {
              Button('返回水量')
                .width('100%')
                .height(44)
                .margin({ top: 12 })
                .backgroundColor(Tokens.CARD)
                .fontColor(Tokens.TEXT_SECONDARY)
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.picking = false;
                })
            }
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        Scroll() {
          Column() {
            Row() {
              Text(this.roomLabel())
                .fontSize(Tokens.F_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
              Blank()
              this.personsChip(4)
              this.personsChip(6)
            }
            .width('100%')
            .margin({ top: 4 })

            this.entryCard()
            this.statsCard()
            this.recordsCard()
            this.rulesCard()
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Tokens.BG)
  }
}

/** 记录深拷贝（避免 Put 后状态引用共享）。 */
function WaterRecordCopy(record: WaterRecord): WaterRecord {
  const copy: WaterRecord = new WaterRecord();
  copy.month = record.month;
  copy.reading = record.reading;
  copy.ts = record.ts;
  return copy;
}
