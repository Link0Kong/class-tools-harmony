import { showFeedback } from '../components/AppFeedback';
import { Services } from '../../app/Services';
import { Blob } from '../../data/sync/JsonBlob';
import {
  PowerPoint,
  PowerCompare,
  PowerRecharge,
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
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { ShareSpecs } from '../../features/share/ShareSpecs';
import { ExportCardSpec } from '../../features/export/ExportCard';
import { ExportCardView } from '../components/ExportCardView';
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
  /** 30d 全量历史（云端只保留 30 天）：仅用于「最近充值」跨区间口径，与所选区间无关。 */
  @State private rechargePoints30: PowerPoint[] = [];
  @State private stats: RangeStats = new RangeStats();
  @State private rangeKey: string = PowerRangeKey.D7;
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  private scroller: Scroller = new Scroller();
  @State private errorMsg: string = '';
  @State private picking: boolean = true;
  @State private pickBuilding: string = '13号楼';
  @State private chartW: number = 0;
  @State private chartH: number = 196;
  @State private comparePoints: PowerPoint[] = [];
  @State private compare: PowerCompare = new PowerCompare();
  @State private slow: SlowEstimate = new SlowEstimate();
  @State private estimate: PowerEstimate = new PowerEstimate();
  @State private estimateDays: number = 0;
  @State private cursor: number = -1;
  @State private cursorText: string = '';
  @State private now: number = Date.now();
  private shareSpec: ExportCardSpec = new ExportCardSpec();

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
    const range: PowerRange = this.range();
    const historyResult: PowerHistoryResult = await Services.power.loadHistory(this.sel, range, force);
    this.points = historyResult.points;
    this.stats = PowerStats.deriveRange(this.points, range, this.now);
    this.cursor = -1;
    this.cursorText = '';
    if (rowResult.row !== undefined && PowerPrefs.isLow(rowResult.row.q, rowResult.row.hasValue, this.low)) {
      PowerNotifier.notifyIfLow(PowerRooms.labelOf(this.sel), rowResult.row.q, this.low);
    }
    if (!historyResult.ok && this.errorMsg.length === 0) {
      this.errorMsg = historyResult.message;
    }
    await this.loadRecharge30(range, historyResult, force);
    await this.refreshCompare(force);
    this.loading = false;
    setTimeout(() => {
      this.drawChart();
    }, 60);
  }

  /**
   * 「最近充值」取数：始终加载 30d 全量历史（云端只保留 30 天），与所选 24h/7d/30d 无关。
   * 所选区间已是 30d 时直接复用刚加载的点，避免重复请求；失败时保留已有数据（不打扰主流程）。
   */
  private async loadRecharge30(range: PowerRange, current: PowerHistoryResult, force: boolean): Promise<void> {
    if (range.key === PowerRangeKey.D30) {
      this.rechargePoints30 = current.points;
      return;
    }
    const result: PowerHistoryResult = await Services.power.loadHistory(this.sel, PowerRange.D30, force);
    if (result.ok) {
      this.rechargePoints30 = result.points;
      return;
    }
    if (this.rechargePoints30.length === 0 && this.errorMsg.length === 0) {
      this.errorMsg = result.message;
    }
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
    this.rechargePoints30 = [];
    this.stats = new RangeStats();
    this.savePrefs(rv, this.low);
    this.load(false);
  }

  /** 所选区间内的充值点（趋势卡角标 / 金色圆点用）；「最近充值」文案走 30d，见 lastRechargeText。 */
  private windowRecharges(): PowerPoint[] {
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
    // 切到 30d 时复用这次请求，不必再为「最近充值」重复拉取；其它档位保持原有 30d 数据不变。
    if (key === PowerRangeKey.D30 && result.ok) {
      this.rechargePoints30 = result.points;
    }
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

  /**
   * 单调三次曲线路径：保证不过冲，得到连续平滑曲线。
   * close=true 时闭合到基线（用于渐变面积）。
   */
  private traceSmooth(xs: number[], ys: number[], baseY: number, close: boolean): void {
    const n: number = xs.length;
    this.ctx.beginPath();
    this.ctx.moveTo(xs[0], ys[0]);
    if (n === 2) {
      this.ctx.lineTo(xs[1], ys[1]);
    } else if (n > 2) {
      const deltas: number[] = [];
      for (let i = 0; i < n - 1; i++) {
        const step: number = xs[i + 1] - xs[i];
        deltas.push(step === 0 ? 0 : (ys[i + 1] - ys[i]) / step);
      }
      const slopes: number[] = [];
      slopes.push(deltas[0]);
      for (let i = 1; i < n - 1; i++) {
        const prev: number = deltas[i - 1];
        const next: number = deltas[i];
        slopes.push(prev * next <= 0 ? 0 : (prev + next) / 2);
      }
      slopes.push(deltas[n - 2]);
      for (let i = 0; i < n - 1; i++) {
        const d: number = deltas[i];
        if (d === 0) {
          slopes[i] = 0;
          slopes[i + 1] = 0;
          continue;
        }
        const limit: number = 3 * d;
        if (Math.abs(slopes[i]) > Math.abs(limit)) {
          slopes[i] = limit;
        }
        if (Math.abs(slopes[i + 1]) > Math.abs(limit)) {
          slopes[i + 1] = limit;
        }
      }
      for (let i = 0; i < n - 1; i++) {
        const step: number = xs[i + 1] - xs[i];
        this.ctx.bezierCurveTo(xs[i] + step / 3, ys[i] + slopes[i] * step / 3,
          xs[i + 1] - step / 3, ys[i + 1] - slopes[i + 1] * step / 3, xs[i + 1], ys[i + 1]);
      }
    }
    if (close) {
      this.ctx.lineTo(xs[n - 1], baseY);
      this.ctx.lineTo(xs[0], baseY);
      this.ctx.closePath();
    }
  }

  /** 趋势绘制（Canvas，单位 vp）：连续平滑曲线 + 渐变面积 + 网格刻度。 */
  private drawChart(): void {
    const w: number = this.chartW > 0 ? this.chartW : 320;
    const h: number = this.chartH;
    this.ctx.clearRect(0, 0, w, h);
    const view: PowerPoint[] = PowerStats.windowPoints(this.points, this.range(), this.now);
    if (view.length === 0) {
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
    if (maxQ - minQ < 0.05) {
      maxQ = maxQ + 0.05;
      minQ = Math.max(0, minQ - 0.05);
    }
    const padLeft: number = 38;
    const padRight: number = 12;
    const padTop: number = 12;
    const padBottom: number = 20;
    const plotW: number = w - padLeft - padRight;
    const plotH: number = h - padTop - padBottom;
    const t0: number = view[0].t;
    const t1: number = view[view.length - 1].t;
    const span: number = Math.max(1, t1 - t0);
    const xOf = (t: number): number => padLeft + (t - t0) / span * plotW;
    const yOf = (q: number): number => padTop + (1 - (q - minQ) / (maxQ - minQ)) * plotH;
    const baseY: number = padTop + plotH;

    // 水平网格 + 纵轴刻度
    this.ctx.font = '10vp sans-serif';
    this.ctx.lineWidth = 0.5;
    for (let i = 0; i <= 3; i++) {
      const ratio: number = i / 3;
      const gy: number = padTop + plotH * ratio;
      this.ctx.setLineDash([2, 4]);
      this.ctx.strokeStyle = Tokens.DIVIDER;
      this.ctx.beginPath();
      this.ctx.moveTo(padLeft, gy);
      this.ctx.lineTo(padLeft + plotW, gy);
      this.ctx.stroke();
      this.ctx.setLineDash([]);
      this.ctx.fillStyle = Tokens.TEXT_TERTIARY;
      this.ctx.textAlign = 'right';
      this.ctx.fillText(axisLabel(maxQ - (maxQ - minQ) * ratio), padLeft - 6, gy + 3);
    }

    // 采样点坐标
    const xs: number[] = [];
    const ys: number[] = [];
    for (let i = 0; i < view.length; i++) {
      xs.push(xOf(view[i].t));
      ys.push(yOf(view[i].q));
    }

    if (xs.length === 1) {
      this.ctx.fillStyle = Tokens.MIST_TEAL;
      this.ctx.beginPath();
      this.ctx.arc(xs[0], ys[0], 4.5, 0, Math.PI * 2);
      this.ctx.fill();
    } else {
      // 渐变面积
      const area: CanvasGradient = this.ctx.createLinearGradient(0, padTop, 0, baseY);
      area.addColorStop(0, Tokens.tint(Tokens.MIST_TEAL, 0.22));
      area.addColorStop(1, Tokens.tint(Tokens.MIST_TEAL, 0.01));
      this.traceSmooth(xs, ys, baseY, true);
      this.ctx.fillStyle = area;
      this.ctx.fill();

      // 连续平滑主线
      this.traceSmooth(xs, ys, baseY, false);
      this.ctx.strokeStyle = Tokens.MIST_TEAL;
      this.ctx.lineWidth = 2;
      this.ctx.lineJoin = 'round';
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }

    // 充值/上调事件标记
    const rises: PowerPoint[] = PowerStats.recharges(view);
    for (let i = 0; i < rises.length; i++) {
      const rx: number = xOf(rises[i].t);
      const ry: number = yOf(rises[i].q);
      this.ctx.fillStyle = '#FFFFFF';
      this.ctx.beginPath();
      this.ctx.arc(rx, ry, 4, 0, Math.PI * 2);
      this.ctx.fill();
      this.ctx.strokeStyle = Tokens.WARM_SAND;
      this.ctx.lineWidth = 1.6;
      this.ctx.stroke();
      this.ctx.fillStyle = Tokens.WARM_SAND;
      this.ctx.beginPath();
      this.ctx.arc(rx, ry, 1.8, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // 最后一点：实心点 + 白芯
    const last: PowerPoint = view[view.length - 1];
    const lx: number = xOf(last.t);
    const ly: number = yOf(last.q);
    this.ctx.fillStyle = Tokens.MIST_TEAL;
    this.ctx.beginPath();
    this.ctx.arc(lx, ly, 4.5, 0, Math.PI * 2);
    this.ctx.fill();
    this.ctx.fillStyle = '#FFFFFF';
    this.ctx.beginPath();
    this.ctx.arc(lx, ly, 2, 0, Math.PI * 2);
    this.ctx.fill();

    // 触摸游标：虚线 + 圆点 + 数值气泡
    if (this.cursor >= 0 && this.cursor < view.length) {
      const cursorPoint: PowerPoint = view[this.cursor];
      const cx: number = xOf(cursorPoint.t);
      const cy: number = yOf(cursorPoint.q);
      this.ctx.strokeStyle = Tokens.tint(Tokens.SLATE_BLUE, 0.65);
      this.ctx.lineWidth = 1;
      this.ctx.setLineDash([3, 3]);
      this.ctx.beginPath();
      this.ctx.moveTo(cx, padTop);
      this.ctx.lineTo(cx, baseY);
      this.ctx.stroke();
      this.ctx.setLineDash([]);
      this.ctx.fillStyle = '#FFFFFF';
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, 5.5, 0, Math.PI * 2);
      this.ctx.fill();
      this.ctx.strokeStyle = Tokens.SLATE_BLUE;
      this.ctx.lineWidth = 2;
      this.ctx.stroke();

      const bubble: string = cursorPoint.q.toFixed(2) + ' 度';
      this.ctx.font = '10vp sans-serif';
      const bubbleW: number = this.ctx.measureText(bubble).width + 14;
      const bubbleH: number = 20;
      let bx: number = cx - bubbleW / 2;
      bx = Math.max(padLeft, Math.min(padLeft + plotW - bubbleW, bx));
      const by: number = Math.max(0, cy - bubbleH - 12);
      this.ctx.fillStyle = Tokens.tint(Tokens.TEXT_PRIMARY, 0.88);
      this.ctx.fillRect(bx, by, bubbleW, bubbleH);
      this.ctx.fillStyle = '#FFFFFF';
      this.ctx.textAlign = 'center';
      this.ctx.fillText(bubble, bx + bubbleW / 2, by + 14);
    }

    // 横轴标签
    this.ctx.fillStyle = Tokens.TEXT_TERTIARY;
    this.ctx.font = '10vp sans-serif';
    this.ctx.textAlign = 'left';
    this.ctx.fillText(shortTime(t0), padLeft, h - 5);
    this.ctx.textAlign = 'right';
    this.ctx.fillText(shortTime(t1), padLeft + plotW, h - 5);
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
      Text(info.building)
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
  rangeChip(range: PowerRange) {
    Text(range.label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.rangeKey === range.key ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .fontWeight(this.rangeKey === range.key ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .height(30)
      .layoutWeight(1)
      .backgroundColor(this.rangeKey === range.key ? Tokens.SLATE_BLUE : Color.Transparent)
      .borderRadius(Tokens.RADIUS_PILL)
      .onClick(() => {
        this.onRange(range.key);
      })
  }

  @Builder
  lowChip(value: number) {
    Text('' + value)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.low === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .constraintSize({ minWidth: 42 })
      .height(30)
      .backgroundColor(this.low === value ? Tokens.WARM_SAND : Tokens.CONTROL_SOFT)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.onLow(value);
      })
  }

  @Builder
  metricTile(caption: string, value: string, unit: string, bg: string, fg: string) {
    Column() {
      Row() {
        Text(value)
          .fontSize(Tokens.F_HEADING)
          .fontWeight(FontWeight.Bold)
          .fontColor(fg)
        if (unit.length > 0) {
          Text(unit)
            .fontSize(10)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ left: 2, bottom: 2 })
        }
      }
      .alignItems(VerticalAlign.Bottom)

      Text(caption)
        .fontSize(10)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor(bg)
    .borderRadius(12)
  }

  @Builder
  metaTag(text: string, fg: string, bg: string) {
    Text(text)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(fg)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(bg)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 6, bottom: 6 })
  }

  private compareText(): string {
    if (this.compare.label.length === 0) {
      return '';
    }
    if (!this.compare.valid) {
      return this.compare.label + ' · 历史数据不足';
    }
    return this.compare.label + ' ' + (this.compare.deltaPct >= 0 ? '+' : '')
      + this.compare.deltaPct.toFixed(1) + '%';
  }

  /**
   * 「最近充值」：取 30d 全量历史里最后一次相邻上升的充值量（delta），
   * 不随所选 24h/7d/30d 变化；无记录返回 ""（不展示该 metaTag）。
   */
  private lastRechargeText(): string {
    const recharge: PowerRecharge | undefined = PowerStats.lastRecharge(this.rechargePoints30);
    if (recharge === undefined) {
      return '';
    }
    return '最近充值 ' + shortTime(recharge.t) + ' · +' + recharge.delta.toFixed(2) + ' 度';
  }

  private slowText(): string {
    if (!this.slow.valid) {
      return '';
    }
    return '慢频估算 日均 ' + this.slow.perDay.toFixed(2) + ' 度'
      + (this.slow.ref ? '（参考）' : '（' + this.slow.segments + ' 段）');
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
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
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
        if (this.windowRecharges().length > 0) {
          Text('充值 ' + this.windowRecharges().length)
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
        .margin({ top: 6 })
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
          const plotW: number = w - 38 - 12;
          if (plotW <= 0) {
            return;
          }
          const ratio: number = (event.touches[0].x - 38) / plotW;
          const view: PowerPoint[] = PowerStats.windowPoints(this.points, this.range(), this.now);
          const idx: number = PowerStats.cursorIndex(view, ratio);
          if (idx >= 0 && idx < view.length) {
            this.cursor = idx;
            const point: PowerPoint = view[idx];
            this.cursorText = shortTime(point.t) + ' · ' + point.q.toFixed(2) + ' 度';
            this.drawChart();
          }
        })

      Row({ space: 8 }) {
        this.metricTile(this.range().dropLabel, PowerStats.fmtDrop(this.stats.drop, this.stats.valid),
          '度', Tokens.TINT_TEAL, Tokens.MIST_TEAL)
        this.metricTile('日均消耗',
          PowerStats.fmtRate(this.estimate.valid ? this.estimate.ratePerDay : this.stats.perDay,
            this.estimate.valid || this.stats.valid), '度/天', Tokens.TINT_SAND, Tokens.WARM_SAND)
        this.metricTile('预计可用', this.estimate.valid ? this.estimateDays.toFixed(1) : '—',
          this.estimate.valid ? '天' : '', Tokens.TINT_BLUE, Tokens.SLATE_BLUE)
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.lastRechargeText().length > 0 || this.compareText().length > 0
        || this.estimate.deductCount > 0 || this.slowText().length > 0 || !this.stats.valid) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          if (this.lastRechargeText().length > 0) {
            this.metaTag(this.lastRechargeText(), Tokens.WARM_SAND, Tokens.tint(Tokens.WARM_SAND, 0.12))
          }
          if (this.compareText().length > 0) {
            this.metaTag(this.compareText(),
              this.compare.valid
                ? (this.compare.deltaPct <= 0 ? Tokens.MIST_TEAL : Tokens.WARM_SAND)
                : Tokens.TEXT_TERTIARY,
              this.compare.valid
                ? (this.compare.deltaPct <= 0 ? Tokens.TINT_TEAL : Tokens.tint(Tokens.WARM_SAND, 0.12))
                : Tokens.CONTROL_SOFT)
          }
          if (this.estimate.deductCount > 0) {
            this.metaTag('异常扣减 ' + this.estimate.deductCount + ' 次 · '
              + this.estimate.deductDeg.toFixed(2) + ' 度',
              Tokens.WARM_SAND, Tokens.tint(Tokens.WARM_SAND, 0.12))
          }
          if (this.slowText().length > 0) {
            this.metaTag(this.slowText(), Tokens.TEXT_SECONDARY, Tokens.CONTROL_SOFT)
          }
          if (!this.stats.valid) {
            this.metaTag('样本不足，暂不估算用电速度', Tokens.WARM_SAND, Tokens.tint(Tokens.WARM_SAND, 0.12))
          }
        }
        .width('100%')
        .margin({ top: 10 })
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

  @Builder
  lowCard() {
    Column() {
      Row() {
        Column() {
          Text('低电提醒阈值')
            .fontSize(Tokens.F_LABEL)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text('剩余电量低于该值时推送提醒')
            .fontSize(10)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.low + ' 度')
          .fontSize(Tokens.F_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.WARM_SAND)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(PowerStats.LOW_OPTIONS, (value: number) => {
          this.lowChip(value)
        }, (value: number) => 'low_' + value)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  /** 当前宿舍电费 → 分享卡图片 → 系统图片分享。 */
  private shareSummary(): void {
    if (this.picking) {
      return;
    }
    const unit: string = this.row !== undefined ? this.row.unit : '度';
    this.shareSpec = ShareSpecs.power(PowerRooms.labelOf(this.sel),
      PowerStats.fmtMain(this.quantity(), this.hasValue()), unit, this.updatedText(),
      this.range().title, this.stats.drop, this.stats.perDay, this.stats.valid,
      this.estimateDays, this.low, this.isLow(), Date.now());
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
      title: '电费',
      actionText: this.picking ? '返回电费' : '',
      actionText2: this.picking ? '' : '分享',
      scroller: this.scroller,
      onBack: () => {
        this.onClose();
      },
      onAction: () => {
        if (this.picking) {
          this.picking = false;
        }
      },
      onAction2: () => {
        this.shareSummary();
      }
    }) {
      Column() {
        if (this.picking) {
          Scroll(this.scroller) {
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
        Refresh({ refreshing: $$this.refreshing }) {
        Scroll(this.scroller) {
          Column() {
            this.heroCard()

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .width('100%')
                .margin({ top: 8 })
            }

            Row() {
              ForEach(this.rangeChips(), (range: PowerRange) => {
                this.rangeChip(range)
              }, (range: PowerRange) => range.key)
            }
            .width('100%')
            .padding(4)
            .margin({ top: 12 })
            .backgroundColor(Tokens.CONTROL_SOFT)
            .borderRadius(Tokens.RADIUS_PILL)

            this.trendCard()

            this.lowCard()
          }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .onDidScroll((offset: number) => {
          const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
          if (Math.abs(next - this.headerFade) > 0.03) {
            this.headerFade = next;
          }
        })
        }
        .layoutWeight(1)
        .onRefreshing(() => {
          this.pullRefresh();
        })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 0 })
    }
  }

  private async pullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.load(true);
    this.refreshing = false;
  }
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function shortTime(ms: number): string {
  const d: Date = new Date(ms);
  return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

function axisLabel(v: number): string {
  if (v >= 100) {
    return v.toFixed(0);
  }
  if (v >= 10) {
    return v.toFixed(1);
  }
  return v.toFixed(2);
}
