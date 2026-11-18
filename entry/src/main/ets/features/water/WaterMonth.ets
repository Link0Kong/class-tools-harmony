import { WaterCodec } from './WaterCodec';

/** 月份工具（`YYYY-MM`，本地时区）。 */
export class WaterMonth {
  static current(nowMillis: number): string {
    const d: Date = new Date(nowMillis);
    return yearMonth(d.getFullYear(), d.getMonth() + 1);
  }

  /** 月份平移（delta 可负）。 */
  static shift(month: string, delta: number): string {
    const safe: string | undefined = WaterCodec.normalizeMonth(month);
    if (safe === undefined) {
      return month;
    }
    let year: number = Number(safe.substring(0, 4));
    let monthNum: number = Number(safe.substring(5, 7));
    const total: number = year * 12 + (monthNum - 1) + delta;
    year = Math.floor(total / 12);
    monthNum = total - year * 12 + 1;
    return yearMonth(year, monthNum);
  }

  /** 该月已过天数（当月=今天几号；过去月=整月；未来月=1）。 */
  static elapsedDays(month: string, nowMillis: number): number {
    const safe: string | undefined = WaterCodec.normalizeMonth(month);
    if (safe === undefined) {
      return 1;
    }
    const current: string = WaterMonth.current(nowMillis);
    if (safe === current) {
      return Math.max(1, new Date(nowMillis).getDate());
    }
    if (safe < current) {
      return WaterMonth.daysInMonth(safe);
    }
    return 1;
  }

  static daysInMonth(month: string): number {
    const safe: string | undefined = WaterCodec.normalizeMonth(month);
    if (safe === undefined) {
      return 30;
    }
    const year: number = Number(safe.substring(0, 4));
    const monthNum: number = Number(safe.substring(5, 7));
    return new Date(year, monthNum, 0).getDate();
  }

  static label(month: string): string {
    const safe: string | undefined = WaterCodec.normalizeMonth(month);
    return safe !== undefined ? safe : month;
  }
}

function yearMonth(year: number, monthNum: number): string {
  const m: number = monthNum < 10 ? monthNum : monthNum;
  return '' + year + '-' + (m < 10 ? '0' + m : '' + m);
}
