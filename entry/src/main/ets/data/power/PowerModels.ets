/** 宿舍目录项；`rv` = roomverify（如 `4-23A---321`，同时也是 `power.id`）。 */
export class RoomInfo {
  rv: string = '';
  label: string = '';
  building: string = '';
  room: string = '';

  constructor(rv: string, label: string, building: string, room: string) {
    this.rv = rv;
    this.label = label;
    this.building = building;
    this.room = room;
  }
}

/** 17 间宿舍目录（与网页 PW_ROOMS / 小程序 utils/power.js 逐项一致）。 */
export class PowerRooms {
  static readonly ROOMS: RoomInfo[] = [
    new RoomInfo('1-13---324', '13号楼324', '13号楼', '324'),
    new RoomInfo('1-13---308', '13号楼308', '13号楼', '308'),
    new RoomInfo('1-16---305', '16号楼305', '16号楼', '305'),
    new RoomInfo('1-16---306', '16号楼306', '16号楼', '306'),
    new RoomInfo('4-23A---321', '23号楼A座321', '23号楼A座', '321'),
    new RoomInfo('4-23A---323', '23号楼A座323', '23号楼A座', '323'),
    new RoomInfo('4-23A---324', '23号楼A座324', '23号楼A座', '324'),
    new RoomInfo('4-23A---325', '23号楼A座325', '23号楼A座', '325'),
    new RoomInfo('4-23A---326', '23号楼A座326', '23号楼A座', '326'),
    new RoomInfo('4-23A---327', '23号楼A座327', '23号楼A座', '327'),
    new RoomInfo('4-23A---328', '23号楼A座328', '23号楼A座', '328'),
    new RoomInfo('4-23A---329', '23号楼A座329', '23号楼A座', '329'),
    new RoomInfo('4-23A---330', '23号楼A座330', '23号楼A座', '330'),
    new RoomInfo('4-23B---422', '23号楼B座422', '23号楼B座', '422'),
    new RoomInfo('4-23B---423', '23号楼B座423', '23号楼B座', '423'),
    new RoomInfo('4-23B---424', '23号楼B座424', '23号楼B座', '424'),
    new RoomInfo('4-23B---425', '23号楼B座425', '23号楼B座', '425')
  ];

  static readonly BUILDINGS: string[] = ['13号楼', '16号楼', '23号楼A座', '23号楼B座'];

  /** 网关日更楼栋（隐藏 24h 区间，默认 7 天）。 */
  static readonly SLOW_BUILDINGS: string[] = ['13号楼', '16号楼'];

  static catOf(rv: string): RoomInfo | undefined {
    const key: string = rv.trim();
    for (let i = 0; i < PowerRooms.ROOMS.length; i++) {
      if (PowerRooms.ROOMS[i].rv === key) {
        return PowerRooms.ROOMS[i];
      }
    }
    return undefined;
  }

  /** 非法/未知 roomverify → ""（页面按未选择处理）。 */
  static normalizeSel(value: string): string {
    const rv: string = value.trim();
    return PowerRooms.catOf(rv) !== undefined ? rv : '';
  }

  static labelOf(rv: string): string {
    const info: RoomInfo | undefined = PowerRooms.catOf(rv);
    return info !== undefined ? info.label : '';
  }

  static buildingOf(rv: string): string {
    const info: RoomInfo | undefined = PowerRooms.catOf(rv);
    return info !== undefined ? info.building : '';
  }

  static roomsOfBuilding(building: string): RoomInfo[] {
    const out: RoomInfo[] = [];
    for (let i = 0; i < PowerRooms.ROOMS.length; i++) {
      if (PowerRooms.ROOMS[i].building === building.trim()) {
        out.push(PowerRooms.ROOMS[i]);
      }
    }
    return out;
  }

  static rvOf(building: string, room: string): string {
    const rooms: RoomInfo[] = PowerRooms.roomsOfBuilding(building);
    for (let i = 0; i < rooms.length; i++) {
      if (rooms[i].room === room.trim()) {
        return rooms[i].rv;
      }
    }
    return '';
  }

  static isSlowBuilding(building: string): boolean {
    return PowerRooms.SLOW_BUILDINGS.indexOf(building.trim()) >= 0;
  }
}

/** 云端 `power` 当前值行（quantity 非法 → q=0，`hasValue=false`）。 */
export class PowerRow {
  id: string = '';
  label: string = '';
  building: string = '';
  room: string = '';
  q: number = 0;
  hasValue: boolean = false;
  unit: string = '度';
  low: boolean = false;
  updatedAt: string = '';
}

/** 一个采样点：q=剩余电量，t=epoch ms。 */
export class PowerPoint {
  q: number = 0;
  t: number = 0;
}

export enum PowerRangeKey {
  H24 = '24h',
  D7 = '7d',
  D30 = '30d'
}

export class PowerRange {
  key: string = '';
  label: string = '';
  windowMs: number = 0;
  title: string = '';
  dropLabel: string = '';

  constructor(key: string, label: string, windowMs: number, title: string, dropLabel: string) {
    this.key = key;
    this.label = label;
    this.windowMs = windowMs;
    this.title = title;
    this.dropLabel = dropLabel;
  }

  static readonly H24: PowerRange = new PowerRange(PowerRangeKey.H24, '24h', 24 * 60 * 60 * 1000,
    '近 24h 趋势', '近 24h 下降');
  static readonly D7: PowerRange = new PowerRange(PowerRangeKey.D7, '7天', 7 * 24 * 60 * 60 * 1000,
    '近 7 天趋势', '近 7 天下降');
  static readonly D30: PowerRange = new PowerRange(PowerRangeKey.D30, '30天', 30 * 24 * 60 * 60 * 1000,
    '近 30 天趋势', '近 30 天下降');

  static readonly ALL: PowerRange[] = [PowerRange.H24, PowerRange.D7, PowerRange.D30];

  static fromKey(key: string): PowerRange {
    for (let i = 0; i < PowerRange.ALL.length; i++) {
      if (PowerRange.ALL[i].key === key) {
        return PowerRange.ALL[i];
      }
    }
    return PowerRange.H24;
  }
}

/** 区间统计（deriveRange 结果）。 */
export class RangeStats {
  n: number = 0;
  start: number = 0;
  end: number = 0;
  drop: number = 0;
  hours: number = 0;
  perDay: number = 0;
  valid: boolean = false;
  hasStart: boolean = false;
}

/** 同期比较结果（自然周期：较昨日/上周/上月同期）。 */
export class PowerCompare {
  valid: boolean = false;
  currentDrop: number = 0;
  previousDrop: number = 0;
  deltaPct: number = 0;
  label: string = '';
  previousText: string = '';
}

/** 用电速度估算（跳过充值上升与异常扣减）。 */
export class PowerEstimate {
  valid: boolean = false;
  ratePerDay: number = 0;
  deductCount: number = 0;
  deductDeg: number = 0;
}

/** 慢频楼栋估算（30 天分段）。 */
export class SlowEstimate {
  valid: boolean = false;
  perDay: number = 0;
  ref: boolean = false;
  segments: number = 0;
}

/** 电费纯计算（与网页 deriveRange 同口径的简化版）。 */
export class PowerStats {
  static round2(v: number): number {
    return Number.isFinite(v) ? Math.round(v * 100) / 100 : 0;
  }

  static fmtQ(q: number, hasValue: boolean): string {
    if (!hasValue) {
      return '—';
    }
    return q.toFixed(2);
  }

  /** 主数值：整数部分大、两位小数。 */
  static fmtMain(q: number, hasValue: boolean): string {
    if (!hasValue) {
      return '—';
    }
    return q.toFixed(2);
  }

  static fmtDrop(v: number, valid: boolean): string {
    return valid ? v.toFixed(2) : '—';
  }

  static fmtRate(v: number, valid: boolean): string {
    return valid ? v.toFixed(1) : '—';
  }

  /**
   * 区间统计：以窗口起点前最后一个采样为基线，窗口内最后一个采样为终点。
   * 样本不足（<2 或时间跨度 0）时 valid=false。
   */
  static deriveRange(points: PowerPoint[], range: PowerRange, nowMillis: number): RangeStats {
    const stats: RangeStats = new RangeStats();
    const cutoff: number = nowMillis - range.windowMs;
    let baselineIndex: number = -1;
    for (let i = 0; i < points.length; i++) {
      if (points[i].t <= cutoff) {
        baselineIndex = i;
      } else {
        break;
      }
    }
    const inWindow: PowerPoint[] = [];
    for (let i = 0; i < points.length; i++) {
      if (points[i].t > cutoff && points[i].t <= nowMillis) {
        inWindow.push(points[i]);
      }
    }
    stats.n = inWindow.length;
    if (inWindow.length === 0) {
      return stats;
    }
    const startPoint: PowerPoint | undefined = baselineIndex >= 0 ? points[baselineIndex]
      : (inWindow.length > 1 ? inWindow[0] : undefined);
    if (startPoint === undefined) {
      return stats;
    }
    const endPoint: PowerPoint = inWindow[inWindow.length - 1];
    stats.start = startPoint.q;
    stats.end = endPoint.q;
    stats.hasStart = true;
    // 只累计真实下降段（充值跳升不计入用电），与网页 deriveRange 同口径
    let dropSum: number = 0;
    let prevQ: number = startPoint.q;
    const series: PowerPoint[] = [];
    series.push(startPoint);
    for (let i = 0; i < inWindow.length; i++) {
      series.push(inWindow[i]);
    }
    for (let i = 1; i < series.length; i++) {
      const current: number = series[i].q;
      if (current < prevQ) {
        dropSum += prevQ - current;
      }
      prevQ = current;
    }
    stats.drop = PowerStats.round2(dropSum);
    stats.hours = (endPoint.t - startPoint.t) / (60 * 60 * 1000);
    stats.valid = inWindow.length >= 2 && stats.hours > 0;
    stats.perDay = stats.valid ? PowerStats.round2(stats.drop / stats.hours * 24) : 0;
    return stats;
  }

  /** 趋势绘制用降采样（最多 maxPoints 个点，保留首尾）。 */
  static downsample(points: PowerPoint[], maxPoints: number): PowerPoint[] {
    if (points.length <= maxPoints || maxPoints < 3) {
      return points;
    }
    const out: PowerPoint[] = [];
    const step: number = (points.length - 1) / (maxPoints - 1);
    for (let i = 0; i < maxPoints; i++) {
      out.push(points[Math.round(i * step)]);
    }
    return out;
  }

  /** 区间内采样点（含窗口起点前的基线点，便于画连续线）。 */
  static windowPoints(points: PowerPoint[], range: PowerRange, nowMillis: number): PowerPoint[] {
    const cutoff: number = nowMillis - range.windowMs;
    let baselineIndex: number = -1;
    for (let i = 0; i < points.length; i++) {
      if (points[i].t <= cutoff) {
        baselineIndex = i;
      } else {
        break;
      }
    }
    const out: PowerPoint[] = [];
    if (baselineIndex >= 0) {
      out.push(points[baselineIndex]);
    }
    for (let i = 0; i < points.length; i++) {
      if (points[i].t > cutoff && points[i].t <= nowMillis) {
        out.push(points[i]);
      }
    }
    return out;
  }

  /** 上升事件（充值/上调）：q 比前一点高 minDelta 以上。 */
  static recharges(points: PowerPoint[], minDelta: number = 0.05): PowerPoint[] {
    const out: PowerPoint[] = [];
    for (let i = 1; i < points.length; i++) {
      if (points[i].q - points[i - 1].q > minDelta) {
        out.push(points[i]);
      }
    }
    return out;
  }

  /** 最近一次充值/上调（窗口内），无则 undefined。 */
  static lastRecharge(points: PowerPoint[]): PowerPoint | undefined {
    const rises: PowerPoint[] = PowerStats.recharges(points);
    return rises.length > 0 ? rises[rises.length - 1] : undefined;
  }

  /** 任意窗口统计：[startMs, endMs] 内只累计下降段（基线取窗口前最后一点）。 */
  static deriveWindow(points: PowerPoint[], startMs: number, endMs: number): RangeStats {
    const stats: RangeStats = new RangeStats();
    let baseline: PowerPoint | undefined = undefined;
    for (let i = 0; i < points.length; i++) {
      if (points[i].t <= startMs) {
        baseline = points[i];
      } else {
        break;
      }
    }
    const inWindow: PowerPoint[] = [];
    for (let i = 0; i < points.length; i++) {
      if (points[i].t > startMs && points[i].t <= endMs) {
        inWindow.push(points[i]);
      }
    }
    stats.n = inWindow.length;
    if (inWindow.length === 0) {
      return stats;
    }
    const startPoint: PowerPoint | undefined = baseline !== undefined ? baseline
      : (inWindow.length > 1 ? inWindow[0] : undefined);
    if (startPoint === undefined) {
      return stats;
    }
    const endPoint: PowerPoint = inWindow[inWindow.length - 1];
    stats.start = startPoint.q;
    stats.end = endPoint.q;
    stats.hasStart = true;
    let dropSum: number = 0;
    let prevQ: number = startPoint.q;
    for (let i = 0; i < inWindow.length; i++) {
      const q: number = inWindow[i].q;
      if (q < prevQ) {
        dropSum += prevQ - q;
      }
      prevQ = q;
    }
    stats.drop = PowerStats.round2(dropSum);
    stats.hours = (endPoint.t - startPoint.t) / (60 * 60 * 1000);
    stats.valid = inWindow.length >= 2 && stats.hours > 0;
    stats.perDay = stats.valid ? PowerStats.round2(stats.drop / stats.hours * 24) : 0;
    return stats;
  }

  /** 自然周期同期比较（较昨日/上周/上月同期）。 */
  static compare(points: PowerPoint[], range: PowerRange, nowMillis: number): PowerCompare {
    const result: PowerCompare = new PowerCompare();
    const now: Date = new Date(nowMillis);
    let currentStart: number = 0;
    let previousStart: number = 0;
    if (range.key === PowerRangeKey.H24) {
      currentStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0).getTime();
      previousStart = currentStart - 24 * 60 * 60 * 1000;
      result.label = '较昨日同期';
    } else if (range.key === PowerRangeKey.D7) {
      const dayIdx: number = (now.getDay() + 6) % 7;
      currentStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - dayIdx, 0, 0, 0).getTime();
      previousStart = currentStart - 7 * 24 * 60 * 60 * 1000;
      result.label = '较上周同期';
    } else {
      currentStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0).getTime();
      previousStart = new Date(now.getFullYear(), now.getMonth() - 1, 1, 0, 0, 0).getTime();
      result.label = '较上月同期';
    }
    const windowMs: number = nowMillis - currentStart;
    if (windowMs <= 0) {
      return result;
    }
    const current: RangeStats = PowerStats.deriveWindow(points, currentStart, nowMillis);
    const previous: RangeStats = PowerStats.deriveWindow(points, previousStart, previousStart + windowMs);
    const coverage: number = 0.35;
    if (!current.valid || !previous.valid
      || current.hours < windowMs / (60 * 60 * 1000) * coverage
      || previous.hours < windowMs / (60 * 60 * 1000) * coverage) {
      return result;
    }
    result.valid = true;
    result.currentDrop = current.drop;
    result.previousDrop = previous.drop;
    result.previousText = previous.drop.toFixed(2) + ' 度';
    if (previous.drop > 0.001) {
      result.deltaPct = PowerStats.round2((current.drop - previous.drop) / previous.drop * 100);
    }
    return result;
  }

  /** 触摸命中最近采样点（xRatio 0..1 → 索引；无点返回 -1）。 */
  static cursorIndex(view: PowerPoint[], xRatio: number): number {
    if (view.length === 0) {
      return -1;
    }
    if (view.length === 1) {
      return 0;
    }
    const t0: number = view[0].t;
    const t1: number = view[view.length - 1].t;
    const target: number = t0 + Math.max(0, Math.min(1, xRatio)) * (t1 - t0);
    let best: number = 0;
    let bestDiff: number = Math.abs(view[0].t - target);
    for (let i = 1; i < view.length; i++) {
      const diff: number = Math.abs(view[i].t - target);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  /** 慢频估算：只取真实下降段（|Δq|>0.05 且间隔 ≥6h），剔除异常大跌，按段折算日均。 */
  static slowEstimate(points: PowerPoint[]): SlowEstimate {
    const estimate: SlowEstimate = new SlowEstimate();
    // 先压成「真实变化点」（网关会重复上报同一读数）
    const changes: PowerPoint[] = [];
    for (let i = 0; i < points.length; i++) {
      if (changes.length === 0 || Math.abs(points[i].q - changes[changes.length - 1].q) > 0.001) {
        changes.push(points[i]);
      }
    }
    const drops: number[] = [];
    for (let i = 1; i < changes.length; i++) {
      const gapH: number = (changes[i].t - changes[i - 1].t) / (60 * 60 * 1000);
      const drop: number = changes[i - 1].q - changes[i].q;
      if (gapH >= 6 && drop > 0.05) {
        drops.push(drop);
      }
    }
    if (drops.length === 0) {
      return estimate;
    }
    const sorted: number[] = drops.slice(0).sort((a: number, b: number) => a - b);
    const median: number = sorted[Math.floor(sorted.length / 2)];
    const threshold: number = Math.max(5, 4 * median);
    let sumDrop: number = 0;
    let sumHours: number = 0;
    let segments: number = 0;
    for (let i = 1; i < changes.length; i++) {
      const gapH: number = (changes[i].t - changes[i - 1].t) / (60 * 60 * 1000);
      const drop: number = changes[i - 1].q - changes[i].q;
      if (gapH >= 6 && drop > 0.05 && drop <= threshold) {
        sumDrop += drop;
        sumHours += gapH;
        segments += 1;
      }
    }
    if (segments === 0 || sumHours <= 0) {
      return estimate;
    }
    estimate.valid = true;
    estimate.segments = segments;
    estimate.perDay = PowerStats.round2(sumDrop / sumHours * 24);
    estimate.ref = segments === 1;
    return estimate;
  }

  /** 估算日耗：相邻采样间隔 ≥1h、下降 >0.05 且不超过异常阈值；异常大跌幅计入 deduct。 */
  static estimate(points: PowerPoint[]): PowerEstimate {
    const result: PowerEstimate = new PowerEstimate();
    const changes: PowerPoint[] = [];
    for (let i = 0; i < points.length; i++) {
      if (changes.length === 0 || Math.abs(points[i].q - changes[changes.length - 1].q) > 0.001) {
        changes.push(points[i]);
      }
    }
    const drops: number[] = [];
    for (let i = 1; i < changes.length; i++) {
      const gapH: number = (changes[i].t - changes[i - 1].t) / (60 * 60 * 1000);
      const drop: number = changes[i - 1].q - changes[i].q;
      if (gapH >= 1 && drop > 0.05) {
        drops.push(drop);
      }
    }
    if (drops.length === 0) {
      return result;
    }
    const sorted: number[] = drops.slice(0).sort((a: number, b: number) => a - b);
    const median: number = sorted[Math.floor((sorted.length - 1) / 2)];
    const threshold: number = Math.max(5, 4 * median);
    let sumDrop: number = 0;
    let sumHours: number = 0;
    for (let i = 1; i < changes.length; i++) {
      const gapH: number = (changes[i].t - changes[i - 1].t) / (60 * 60 * 1000);
      const drop: number = changes[i - 1].q - changes[i].q;
      if (gapH < 1 || drop <= 0.05) {
        continue;
      }
      if (drop > threshold) {
        result.deductCount += 1;
        result.deductDeg = PowerStats.round2(result.deductDeg + drop);
        continue;
      }
      sumDrop += drop;
      sumHours += gapH;
    }
    if (sumHours > 0) {
      result.valid = true;
      result.ratePerDay = PowerStats.round2(Math.max(0.05, sumDrop / sumHours * 24));
    }
    return result;
  }

  /** 估算可用天数（电量 / 日耗；无效返回 0）。 */
  static daysLeft(q: number, ratePerDay: number): number {
    if (ratePerDay <= 0 || q <= 0) {
      return 0;
    }
    return Math.floor(q / ratePerDay * 10) / 10;
  }

  /** 低电阈值选项（与网页一致）。 */
  static readonly LOW_OPTIONS: number[] = [10, 20, 30, 40, 50, 60, 80, 100];

  static defaultLow(): number {
    return 30;
  }

  static normalizeLow(value: number): number {
    for (let i = 0; i < PowerStats.LOW_OPTIONS.length; i++) {
      if (PowerStats.LOW_OPTIONS[i] === Math.round(value)) {
        return Math.round(value);
      }
    }
    return PowerStats.defaultLow();
  }
}
