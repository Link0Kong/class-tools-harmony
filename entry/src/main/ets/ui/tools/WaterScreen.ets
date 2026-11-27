import { showFeedback } from '../components/AppFeedback';
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
import { SharedLedger, LedgerData, WaterIntent } from '../../features/water/SharedLedger';
import { WaterLedgerFile } from '../../features/water/WaterLedgerFile';
import { PowerPrefs } from '../../data/power/PowerPrefs';
import { WaterMutator } from '../../features/water/WaterMutator';
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { ShareSpecs } from '../../features/share/ShareSpecs';
import { ExportCardSpec } from '../../features/export/ExportCard';
import { ExportCardView } from '../components/ExportCardView';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/**
 * 水量工具：1–6 人间自选 + 按月抄表（读数 → 用量/水费/折合扣电）+ 记录列表 + 规则卡。
 *
 * 新读数按真实房间读写共享表，userdata.water 保留为个人历史。
 * 口径：水 3.03 元/吨、免费 2 吨/人/月、折合扣电 = 水费 ÷ 0.58；无上一条不伪造用量。
 */
@Component
export struct WaterScreen {
  onClose: () => void = () => {
  };

  @State private sel: string = '';
  @State private state: WaterState = new WaterState();
  @State private shared: WaterRoomState = new WaterRoomState();
  @State private status: string = '';
  @State private pending: string = '';
  @State private legacyMode: boolean = false;
  @State private denied: boolean = false;
  @State private busy: boolean = false;
  @StorageProp('waterForeground') @Watch('resumeLedger') private foreground: number = 0;
  private ledger?: SharedLedger;
  private alive: () => boolean = () => false;
  private serial: number = 0;
  @State private persons: number = WaterRules.PERSONS_DEFAULT;
  @State private monthText: string = '';
  @State private readingText: string = '';
  @State private errorMsg: string = '';
  @State private confirmReplace: boolean = false;
  @State private picking: boolean = true;
  @State private pickBuilding: string = '13号楼';
  @State private now: number = Date.now();
  private shareSpec: ExportCardSpec = new ExportCardSpec();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.now = Date.now();
    this.monthText = WaterMonth.current(this.now);
    const sections: Blob = Services.userdata.currentSections();
    this.state = WaterCodec.fromJson(JsonBlob.get(sections, 'water'));
    const selected = PowerPrefs.read(sections).sel;
    if (selected.length > 0) this.pickRoom(selected);
  }

  aboutToDisappear(): void {
    this.serial++;
  }

  private resumeLedger(): void {
    if (!this.picking && !this.busy && this.alive()) this.reload();
  }

  private roomLabel(): string {
    return this.sel.length > 0 ? PowerRooms.labelOf(this.sel) : '';
  }

  private roomState(): WaterRoomState {
    return this.alive() && !this.denied ? this.shared : new WaterRoomState();
  }

  private stats(): WaterMonthStats {
    return WaterCalculator.stats(this.roomState(), this.monthText, this.now);
  }

  private reflect(ledger: SharedLedger): void {
    if (!this.alive() || this.ledger !== ledger) return;
    this.denied = ledger.data.denied;
    this.shared = ledger.roomState();
    this.persons = this.shared.persons;
    this.status = ledger.status;
    const op: WaterIntent | null = ledger.data.pending;
    this.pending = !op || this.denied ? '' : (op.kind === 'persons' ? '修改人数为 ' + op.persons :
      (op.kind === 'delete' ? '删除 ' + op.month : op.month + ' 读数 ' + op.reading + ' 吨（' + op.persons + ' 人）'));
  }

  private pickRoom(rv: string): void {
    const serial = ++this.serial;
    const sid = Services.currentSid;
    const token = Services.currentToken;
    const session = Services.userdata;
    this.sel = rv;
    this.picking = false;
    this.pickBuilding = PowerRooms.buildingOf(rv);
    this.confirmReplace = false;
    this.errorMsg = '';
    this.legacyMode = false;
    this.pending = '';
    this.readingText = '';
    this.denied = false;
    this.busy = false;
    this.ledger = undefined;
    this.shared = new WaterRoomState();
    this.monthText = WaterMonth.current(this.now);
    this.alive = () => serial === this.serial && session === Services.userdata && sid.length > 0 &&
      sid === Services.currentSid && token === Services.currentToken;
    try {
      const file = new WaterLedgerFile(sid, rv);
      const ledger = new SharedLedger(Services.api, sid, rv, file.load(), this.alive,
        (data: LedgerData) => file.save(data));
      this.ledger = ledger;
      this.reflect(ledger);
      this.reload();
    } catch (e) {
      this.status = '本机账本不可用，请重新进入房间';
    }
  }

  private async reload(): Promise<void> {
    const ledger = this.ledger;
    if (!ledger || this.busy || !this.alive()) return;
    this.busy = true;
    try {
      await ledger.refresh();
      this.reflect(ledger);
    } catch (e) {
      if (this.ledger === ledger && this.alive()) this.status = '暂时无法刷新';
    } finally {
      if (this.ledger === ledger && this.alive()) this.busy = false;
    }
  }

  private async send(kind: string, month: string, reading: number, count: number,
    reconfirm: boolean = false): Promise<void> {
    const ledger = this.ledger;
    if (!ledger || this.busy || !this.alive()) return;
    this.busy = true;
    try {
      if (kind.length > 0) ledger.prepare(kind, month, reading, count);
      const result = await ledger.submit(reconfirm);
      if (this.ledger !== ledger || !this.alive()) return;
      this.reflect(ledger);
      this.status = result;
      this.confirmReplace = false;
      if (!this.pending && !this.denied) this.readingText = '';
    } catch (e) {
      if (this.ledger === ledger && this.alive()) {
        this.reflect(ledger);
        this.status = this.denied ? '班级身份未获授权' : '操作尚未确认，请核对待提交项';
      }
    } finally {
      if (this.ledger === ledger && this.alive()) this.busy = false;
    }
  }

  private async onPersons(value: number): Promise<void> {
    await this.send('persons', '', 0, value);
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
      showFeedback(this.getUIContext(), '该月已有记录，请点「确认覆盖」');
      return;
    }
    const record: WaterRecord = review.record as WaterRecord;
    await this.send('save', record.month, record.reading, this.persons);
  }

  private async deleteRecord(month: string): Promise<void> {
    await this.send('delete', month, 0, this.persons);
  }

  @Builder
  ledgerActions() {
    Column({ space: 6 }) {
      Text(this.status).fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY)
      Row({ space: 8 }) {
        Button('刷新共享账本').enabled(!this.busy).onClick(() => this.reload())
        Button(this.legacyMode ? '收起个人旧账' : '查看个人旧账').enabled(!this.denied)
          .onClick(() => { this.legacyMode = !this.legacyMode; })
      }
      if (this.pending.length > 0 && !this.denied) {
        Text('待确认 · ' + this.pending).fontColor(Tokens.TEXT_PRIMARY)
        Row({ space: 8 }) {
          Button('按当前共享值确认').enabled(!this.busy).onClick(() => this.send('', '', 0, 4, true))
          Button('放弃草稿').enabled(!this.busy).onClick(() => {
            if (this.ledger && this.alive()) { this.ledger.discard(); this.reflect(this.ledger); }
          })
        }
      }
      if (this.legacyMode && !this.denied && this.alive()) {
        Text('个人旧账 · ' + this.state.roomOrDefault(this.sel).persons + ' 人').fontColor(Tokens.TEXT_PRIMARY)
        if (this.state.roomOrDefault(this.sel).records.length === 0) {
          Text('这间宿舍没有个人旧记录').fontColor(Tokens.TEXT_SECONDARY)
        }
        ForEach(this.state.roomOrDefault(this.sel).records, (item: WaterRecord) => {
          Row({ space: 8 }) {
            Text(item.month + ' · ' + item.reading + ' 吨').fontColor(Tokens.TEXT_PRIMARY)
            Button('带入录入框').enabled(!this.busy).onClick(() => {
              this.monthText = item.month;
              this.readingText = String(item.reading);
              this.confirmReplace = false;
              this.errorMsg = '核对月份和共享值后，再点保存';
            })
          }
        }, (item: WaterRecord) => item.month)
      }
    }.width('100%')
  }

  @Builder
  buildingChip(building: string) {
    Text(building)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.pickBuilding === building ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.pickBuilding === building ? Tokens.MIST_TEAL : Tokens.CONTROL)
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
      Text(this.state.rooms.has(info.rv) ? '有个人旧账' : '查看共享账本')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.sel === info.rv ? '#E8F2EF' : Tokens.TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .width('31%')
    .padding({ top: 12, bottom: 12 })
    .margin({ bottom: 8 })
    .backgroundColor(this.sel === info.rv ? Tokens.MIST_TEAL : Tokens.CONTROL)
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
      .backgroundColor(this.persons === value ? Tokens.SLATE_BLUE : Tokens.CONTROL)
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
        .backgroundColor(Tokens.CONTROL)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_PILL)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .margin({ left: 10 })
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
          .backgroundColor(Tokens.CONTROL)
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
          .backgroundColor(Tokens.CONTROL)
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
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
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
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
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
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
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
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  /** 当前月份水量 → 分享卡图片 → 系统图片分享。 */
  private shareSummary(): void {
    if (this.picking || this.denied || !this.alive() || !this.ledger || !this.ledger.rowsFresh || !this.ledger.peopleFresh || this.pending.length > 0) {
      showFeedback(this.getUIContext(), '请先刷新并确认共享账本');
      return;
    }
    const stats: WaterMonthStats = this.stats();
    this.shareSpec = ShareSpecs.water(stats, this.roomLabel(), Date.now());
    const builder: CustomBuilder = (): void => {
      this.sharePoster();
    };
    NativeShare.shareCard(this.getUIContext(), builder, this.shareSpec.fileName,
      this.shareSpec.title, this.shareSpec.subtitle).then((result: ShareResult) => {
      if (!result.ok) {
        showFeedback(this.getUIContext(), result.message);
      }
    });
  }

  @Builder
  sharePoster() {
    ExportCardView({ spec: this.shareSpec })
  }

  @State private headerFade: number = 0;

  build() {
    PageHeader({
      progress: this.headerFade,
      title: '水量',
      actionText: this.picking ? '返回水量' : '切换',
      actionText2: this.picking ? '' : '分享',
      scroller: this.scroller,
      onBack: () => {
        this.onClose();
      },
      onAction: () => {
        if (this.picking && this.sel) { this.pickRoom(this.sel); }
        else { this.serial++; this.picking = true; }
      },
      onAction2: () => {
        this.shareSummary();
      }
    }) {
      Column() {
      if (this.picking) {
        Scroll(this.scroller) {
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

          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
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
      } else {
        Scroll() {
          Column() {
            Column() {
              Text(this.roomLabel())
                .fontSize(Tokens.F_TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
                ForEach(WaterRules.PERSONS_OPTIONS, (value: number) => {
                  this.personsChip(value)
                }, (value: number) => 'persons_' + value)
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .width('100%')

            this.ledgerActions()
            if (!this.denied) {
              this.entryCard()
            this.statsCard()
            this.recordsCard()
            this.rulesCard()
            }
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
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
      }
      .width('100%')
      .height('100%')
      .padding({ top: 0 })
    }
  }
}
