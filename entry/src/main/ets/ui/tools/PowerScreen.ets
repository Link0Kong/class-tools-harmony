import { Services } from '../../app/Services';
import { Blob } from '../../data/sync/JsonBlob';
import {
  PowerPoint,
  PowerCompare,
  SlowEstimate,
  PowerEstimate,
  PowerRange,
  PowerRangeKey,
  PowerRooms,
  PowerRow,
  PowerStats,
  RangeStats,
  RoomInfo
} from '../../data/power/PowerModels';
import { PowerHistoryResult, PowerRepository, PowerRowResult } from '../../data/power/PowerRepository';
import { PowerPrefs, PowerPrefsData } from '../../data/power/PowerPrefs';
import { PowerNotifier } from '../../data/power/PowerNotifier';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/**
 * 电费工具：宿舍选择（17 间，4 楼栋）+ 剩余电量 + 24h/7d/30d 趋势 + 区间统计 + 低电阈值。
 *
 * 口径：关注宿舍/阈值写 `userdata.power={sel,at,low}`（v6 整段 LWW）；
 * 13/16 号楼为网关日更，隐藏 24h 档并默认 7 天（与网页 §4b-34 一致）。
 */
@Component
export struct PowerScreen {
  onClose: () => void = () => {
  };

  @State private sel: string = '';
  @State private low: number = PowerStats.defaultLow();
  @State private row: PowerRow | undefined = undefined;
  @State private points: PowerPoint[] = [];
  @State private stats: RangeStats = new RangeStats();
  @State private rangeKey: string = PowerRangeKey.D7;
  @State private loading: boolean = false;
  @State private errorMsg: string = '';
  @State private picking: boolean = true;
  @State private pickBuilding: string = '13号楼';
  @State private chartW: number = 0;
  @State private chartH: number = 170;
  @State private comparePoints: PowerPoint[] = [];
  @State private compare: PowerCompare = new PowerCompare();
  @State private slow: SlowEstimate = new SlowEstimate();
  @State private estimate: PowerEstimate = new PowerEstimate();
  @State private estimateDays: number = 0;
  @State private cursor: number = -1;
  @State private cursorText: string = '';
  @State private now: number = Date.now();

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    const prefs: PowerPrefsData = PowerPrefs.read(Services.userdata.currentSections());
    this.low = prefs.low;
    this.sel = prefs.sel;
    if (this.sel.length > 0) {
      this.picking = false;
      this.pickBuilding = PowerRooms.buildingOf(this.sel);
      this.rangeKey = PowerRooms.isSlowBuilding(this.pickBuilding) ? PowerRangeKey.D7 : PowerRangeKey.H24;
      this.load(false);
    }
  }

  private range(): PowerRange {
    return PowerRange.fromKey(this.rangeKey);
  }

  private async load(force: boolean): Promise<void> {
    if (this.sel.length === 0) {
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    this.now = Date.now();
    const rowResult: PowerRowResult = await Services.power.loadRow(this.sel, force);
    this.row = rowResult.row;
    if (!rowResult.ok) {
      this.errorMsg = rowResult.message;
    } else if (rowResult.message.length > 0) {
      this.errorMsg = rowResult.message;
    }
    const historyResult: PowerHistoryResult = await Services.power.loadHistory(this.sel, this.range(), force);
    this.points = historyResult.points;
    this.stats = PowerStats.deriveRange(this.points, this.range(), this.now);
    this.cursor = -1;
    this.cursorText = '';
    await this.refreshCompare(force);
    if (rowResult.row !== undefined && PowerPrefs.isLow(rowResult.row.q, rowResult.row.hasValue, this.low)) {
      PowerNotifier.notifyIfLow(PowerRooms.labelOf(this.sel), rowResult.row.q, this.low);
    }
    if (!historyResult.ok && this.errorMsg.length === 0) {
      this.errorMsg = historyResult.message;
    }
    this.loading = false;
    setTimeout(() => {
      this.drawChart();
    }, 60);
  }

  private async savePrefs(sel: string, low: number): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = PowerPrefs.write(current, sel, low, Date.now());
    await Services.userdata.updateCurrent(next);
  }

  private pickRoom(rv: string): void {
    this.sel = rv;
    this.picking = false;
    this.pickBuilding = PowerRooms.buildingOf(rv);
    this.rangeKey = PowerRooms.isSlowBuilding(this.pickBuilding) ? PowerRangeKey.D7 : PowerRangeKey.H24;
    this.row = undefined;
    this.points = [];
    this.stats = new RangeStats();
    this.savePrefs(rv, this.low);
    this.load(false);
  }

  private rechargePoints(): PowerPoint[] {
    return PowerStats.recharges(PowerStats.windowPoints(this.points, this.range(), this.now));
  }

  private compareWindowMs(): number {
    if (this.rangeKey === PowerRangeKey.H24) {
      return 48 * 60 * 60 * 1000;
    }
    if (this.rangeKey === PowerRangeKey.D7) {
      return 14 * 24 * 60 * 60 * 1000;
    }
    return 70 * 24 * 60 * 60 * 1000;
  }

  private async refreshCompare(force: boolean): Promise<void> {
    const windowResult: PowerHistoryResult = await Services.power.loadHistoryWindow(this.sel,
      this.compareWindowMs(), force);
    this.comparePoints = windowResult.points;
    this.compare = PowerStats.compare(this.comparePoints, this.range(), this.now);
    this.slow = new SlowEstimate();
    if (PowerRooms.isSlowBuilding(PowerRooms.buildingOf(this.sel)) && this.rangeKey !== PowerRangeKey.H24) {
      this.slow = PowerStats.slowEstimate(this.comparePoints);
    }
    const estPoints: PowerPoint[] = this.comparePoints.length > 1 ? this.comparePoints : this.points;
    this.estimate = PowerStats.estimate(estPoints);
    this.estimateDays = this.hasValue() ? PowerStats.daysLeft(this.quantity(), this.estimate.ratePerDay) : 0;
  }

  private async onRange(key: string): Promise<void> {
    this.rangeKey = key;
    this.cursor = -1;
    this.cursorText = '';
    const result: PowerHistoryResult = await Services.power.loadHistory(this.sel, this.range(), false);
    this.points = result.points;
    this.now = Date.now();
    this.stats = PowerStats.deriveRange(this.points, this.range(), this.now);
    await this.refreshCompare(false);
    setTimeout(() => {
      this.drawChart();
    }, 40);
  }

  private onLow(value: number): void {
    this.low = PowerStats.normalizeLow(value);
    this.savePrefs(this.sel, this.low);
  }

  private updatedText(): string {
    if (this.row === undefined || this.row.updatedAt.length === 0) {
      return '';
    }
    const stamp: number = Date.parse(this.row.updatedAt);
    if (!Number.isFinite(stamp)) {
      return this.row.updatedAt;
    }
    const d: Date = new Date(stamp);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  private hasValue(): boolean {
    return this.row !== undefined && this.row.hasValue;
  }

  private quantity(): number {
    return this.row !== undefined ? this.row.q : 0;
  }

  private isLow(): boolean {
    return PowerPrefs.isLow(this.quantity(), this.hasValue(), this.low);
  }

  private rangeChips(): PowerRange[] {
    const slow: boolean = PowerRooms.isSlowBuilding(PowerRooms.buildingOf(this.sel));
    const out: PowerRange[] = [];
    for (let i = 0; i < PowerRange.ALL.length; i++) {
      const range: PowerRange = PowerRange.ALL[i];
      if (slow && range.key === PowerRangeKey.H24) {
        continue;
      }
      out.push(range);
    }
    return out;
  }

  /** 趋势绘制（Canvas，单位 vp）。 */
  private drawChart(): void {
    const w: number = this.chartW > 0 ? this.chartW : 320;
    const h: number = this.chartH;
    this.ctx.clearRect(0, 0, w, h);
    const view: PowerPoint[] = PowerStats.windowPoints(this.points, this.range(), this.now);
    if (view.length < 2) {
      this.ctx.fillStyle = Tokens.TEXT_TERTIARY;
      this.ctx.font = '12vp sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.fillText('暂无趋势数据', w / 2, h / 2);
      return;
    }
    let minQ: number = view[0].q;
    let maxQ: number = view[0].q;
    for (let i = 1; i < view.length; i++) {
      minQ = Math.min(minQ, view[i].q);
      maxQ = Math.max(maxQ, view[i].q);
    }
    if (maxQ - minQ < 0.01) {
      maxQ = minQ + 0.01;
    }
    const padLeft: number = 34;
    const padRight: number = 8;
    const padTop: number = 8;
    const padBottom: number = 18;
    const plotW: number = w - padLeft - padRight;
    const plotH: number = h - padTop - padBottom;
    const t0: number = view[0].t;
    const t1: number = view[view.length - 1].t;
    const span: number = Math.max(1, t1 - t0);
    const xOf = (t: number): number => padLeft + (t - t0) / span * plotW;
    const yOf = (q: number): number => padTop + (1 - (q - minQ) / (maxQ - minQ)) * plotH;

    // 坐标轴与网格
    this.ctx.strokeStyle = Tokens.DIVIDER;
    this.ctx.lineWidth = 0.5;
    this.ctx.beginPath();
    this.ctx.moveTo(padLeft, padTop);
    this.ctx.lineTo(padLeft, padTop + plotH);
    this.ctx.lineTo(padLeft + plotW, padTop + plotH);
    this.ctx.stroke();

    // 折线
    this.ctx.strokeStyle = Tokens.MIST_TEAL;
    this.ctx.lineWidth = 1.6;
    this.ctx.beginPath();
    for (let i = 0; i < view.length; i++) {
      const px: number = xOf(view[i].t);
      const py: number = yOf(view[i].q);
      if (i === 0) {
        this.ctx.moveTo(px, py);
      } else {
        this.ctx.lineTo(px, py);
      }
    }
    this.ctx.stroke();

    // 最后一点
    const last: PowerPoint = view[view.length - 1];
    this.ctx.fillStyle = Tokens.MIST_TEAL;
    this.ctx.beginPath();
    this.ctx.arc(xOf(last.t), yOf(last.q), 3, 0, Math.PI * 2);
    this.ctx.fill();

    // 充值/上调事件标记
    const rises: PowerPoint[] = PowerStats.recharges(view);
    this.ctx.fillStyle = Tokens.WARM_SAND;
    for (let i = 0; i < rises.length; i++) {
      this.ctx.beginPath();
      this.ctx.arc(xOf(rises[i].t), yOf(rises[i].q), 2.5, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // 触摸游标：竖线 + 圆点
    if (this.cursor >= 0 && this.cursor < view.length) {
      const cursorPoint: PowerPoint = view[this.cursor];
      const cx: number = xOf(cursorPoint.t);
      this.ctx.strokeStyle = Tokens.tint(Tokens.SLATE_BLUE, 0.5);
      this.ctx.lineWidth = 1;
      this.ctx.beginPath();
      this.ctx.moveTo(cx, padTop);
      this.ctx.lineTo(cx, padTop + plotH);
      this.ctx.stroke();
      this.ctx.fillStyle = Tokens.SLATE_BLUE;
      this.ctx.beginPath();
      this.ctx.arc(cx, yOf(cursorPoint.q), 3.5, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // 轴标签
    this.ctx.fillStyle = Tokens.TEXT_TERTIARY;
    this.ctx.font = '10vp sans-serif';
    this.ctx.textAlign = 'right';
    this.ctx.fillText(maxQ.toFixed(1), padLeft - 4, padTop + 8);
    this.ctx.fillText(minQ.toFixed(1), padLeft - 4, padTop + plotH);
    this.ctx.textAlign = 'left';
    this.ctx.fillText(shortTime(t0), padLeft, h - 4);
    this.ctx.textAlign = 'right';
    this.ctx.fillText(shortTime(t1), w - padRight, h - 4);
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
      Text(info.building)
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
  rangeChip(range: PowerRange) {
    Text(range.label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.rangeKey === range.key ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.rangeKey === range.key ? Tokens.SLATE_BLUE : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.onRange(range.key);
      })
  }

  @Builder
  lowChip(value: number) {
    Text('' + value)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.low === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.low === value ? Tokens.WARM_SAND : Tokens.BG)
      .borderRadius(8)
      .margin({ right: 6 })
      .onClick(() => {
        this.onLow(value);
      })
  }

  @Builder
  heroCard() {
    Column() {
      Row() {
        Text(PowerRooms.labelOf(this.sel))
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
          .layoutWeight(1)
        Text('切换')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.picking = true;
          })
      }
      .width('100%')

      Row() {
        Text(PowerStats.fmtMain(this.quantity(), this.hasValue()))
          .fontSize(52)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isLow() ? Tokens.DANGER : Tokens.TEXT_PRIMARY)
        Text(this.row !== undefined ? this.row.unit : '度')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ left: 6, bottom: 10 })
        Blank()
        if (this.isLow()) {
          Text('低电')
            .fontSize(Tokens.F_CAPTION)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(Tokens.DANGER)
            .borderRadius(6)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Text((this.updatedText().length > 0 ? '更新于 ' + this.updatedText() : '暂无更新时间')
        + (PowerRooms.isSlowBuilding(PowerRooms.buildingOf(this.sel)) ? ' · 网关日更' : ''))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  trendCard() {
    Column() {
      Row() {
        Text(this.range().title)
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        if (this.rechargePoints().length > 0) {
          Text('充值 ' + this.rechargePoints().length)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.WARM_SAND)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(Tokens.tint(Tokens.WARM_SAND, 0.12))
            .borderRadius(Tokens.RADIUS_PILL)
            .margin({ right: 8 })
        }
        Text(this.cursorText.length > 0 ? this.cursorText : (this.stats.n + ' 个采样'))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.cursorText.length > 0 ? Tokens.SLATE_BLUE : Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Canvas(this.ctx)
        .width('100%')
        .height(this.chartH)
        .margin({ top: 8 })
        .onReady(() => {
          this.drawChart();
        })
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const width: number = Number(newArea.width);
          if (width > 0 && Math.abs(width - this.chartW) > 1) {
            this.chartW = width;
            this.drawChart();
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.touches.length === 0) {
            return;
          }
          const w: number = this.chartW > 0 ? this.chartW : 320;
          const plotW: number = w - 34 - 8;
          if (plotW <= 0) {
            return;
          }
          const ratio: number = (event.touches[0].x - 34) / plotW;
          const view: PowerPoint[] = PowerStats.windowPoints(this.points, this.range(), this.now);
          const idx: number = PowerStats.cursorIndex(view, ratio);
          if (idx >= 0 && idx < view.length) {
            this.cursor = idx;
            const point: PowerPoint = view[idx];
            this.cursorText = shortTime(point.t) + ' · ' + point.q.toFixed(2) + ' 度';
            this.drawChart();
          }
        })

      Row() {
        Column() {
          Text(PowerStats.fmtDrop(this.stats.drop, this.stats.valid))
            .fontSize(Tokens.F_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text(this.range().dropLabel + '（度）')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text(PowerStats.fmtRate(this.estimate.valid ? this.estimate.ratePerDay : this.stats.perDay,
          this.estimate.valid || this.stats.valid))
            .fontSize(Tokens.F_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text('日均（度）')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.rechargePoints().length > 0) {
        Text('最近充值 ' + shortTime(this.rechargePoints()[this.rechargePoints().length - 1].t)
          + ' · 当前 ' + this.rechargePoints()[this.rechargePoints().length - 1].q.toFixed(2) + ' 度')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.WARM_SAND)
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.estimate.valid) {
        Text('预计可用 ' + this.estimateDays.toFixed(1) + ' 天 · 日均 ' + this.estimate.ratePerDay.toFixed(2) + ' 度')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.estimate.deductCount > 0) {
        Text('异常扣减 ' + this.estimate.deductCount + ' 次 · ' + this.estimate.deductDeg.toFixed(2) + ' 度（已忽略不计入日耗）')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.WARM_SAND)
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.slow.valid) {
        Text('慢频估算 日均 ' + this.slow.perDay.toFixed(2) + ' 度'
          + (this.slow.ref ? '（参考）' : '（' + this.slow.segments + ' 段）'))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.compare.label.length > 0) {
        Row({ space: 8 }) {
          Text(this.compare.valid
            ? (this.compare.label + ' ' + (this.compare.deltaPct >= 0 ? '+' : '')
              + this.compare.deltaPct.toFixed(1) + '% · 上期 ' + this.compare.previousText)
            : (this.compare.label + ' · 历史数据不足'))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.compare.valid
              ? (this.compare.deltaPct <= 0 ? Tokens.MIST_TEAL : Tokens.WARM_SAND)
              : Tokens.TEXT_TERTIARY)
        }
        .width('100%')
        .margin({ top: 6 })
      }
      if (!this.stats.valid) {
        Text('样本不足，暂不估算用电速度')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.WARM_SAND)
          .width('100%')
          .margin({ top: 4 })
      }
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
        title: '电费',
        actionText: this.picking ? '' : (this.loading ? '' : '刷新'),
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.load(true);
        }
      })

      if (this.picking) {
        Scroll() {
          Column() {
            Text('选择关注的宿舍')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 4 })

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
              }, (info: RoomInfo) => info.rv + (this.sel === info.rv ? '_on' : ''))
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
              Button('返回电费')
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
            this.heroCard()

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .width('100%')
                .margin({ top: 8 })
            }

            Row({ space: 6 }) {
              ForEach(this.rangeChips(), (range: PowerRange) => {
                this.rangeChip(range)
              }, (range: PowerRange) => range.key)
              Blank()
            }
            .width('100%')
            .margin({ top: 12 })

            this.trendCard()

            Column() {
              Text('低电提醒阈值')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
              Row() {
                ForEach(PowerStats.LOW_OPTIONS, (value: number) => {
                  this.lowChip(value)
                }, (value: number) => 'low_' + value)
                Blank()
              }
              .width('100%')
              .margin({ top: 8 })
            }
            .width('100%')
            .padding(14)
            .margin({ top: 12 })
            .backgroundColor(Tokens.CARD)
            .borderRadius(Tokens.RADIUS_CARD)
            .alignItems(HorizontalAlign.Start)
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

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function shortTime(ms: number): string {
  const d: Date = new Date(ms);
  return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}
