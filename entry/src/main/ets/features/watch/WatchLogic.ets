/** 手表端纯逻辑：倒计时、时间、离线判断（可单测）。 */
export class WatchLogic {
  /** 距上课还有几分钟；<=0 表示已开始。 */
  static minutesUntil(atMs: number, nowMs: number): number {
    return Math.floor((atMs - nowMs) / 60000);
  }

  /** 倒计时文案。 */
  static countdownText(atMs: number, nowMs: number): string {
    const min: number = WatchLogic.minutesUntil(atMs, nowMs);
    if (min > 60) {
      const h: number = Math.floor(min / 60);
      return '还有 ' + h + ' 小时 ' + (min % 60) + ' 分';
    }
    if (min > 0) {
      return '还有 ' + min + ' 分钟';
    }
    return '已开始';
  }

  /** HH:mm。 */
  static clock(ms: number): string {
    const d: Date = new Date(ms);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    return (h < 10 ? '0' + h : '' + h) + ':' + (m < 10 ? '0' + m : '' + m);
  }

  /** 截止文案：今天/明天/日期 + HH:mm。 */
  static dueText(date: string, time: string, nowMs: number): string {
    if (date.length === 0) {
      return time.length > 0 ? time + ' 截止' : '';
    }
    const now: Date = new Date(nowMs);
    const today: string = WatchLogic.dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    const tomorrow: Date = new Date(now.getTime() + 24 * 3600 * 1000);
    const tmr: string = WatchLogic.dateKey(tomorrow.getFullYear(), tomorrow.getMonth() + 1, tomorrow.getDate());
    let day: string = date;
    if (date === today) {
      day = '今天';
    } else if (date === tmr) {
      day = '明天';
    }
    return day + ' ' + (time.length > 0 ? time : '') + ' 截止';
  }

  static dateKey(y: number, m: number, d: number): string {
    const mm: string = m < 10 ? '0' + m : '' + m;
    const dd: string = d < 10 ? '0' + d : '' + d;
    return y + '-' + mm + '-' + dd;
  }

  /** 超过 max 字符截断。 */
  static short(text: string, max: number): string {
    if (text.length <= max) {
      return text;
    }
    return text.substring(0, max - 1) + '…';
  }

  /** 所有数据源都失败且无缓存 → 离线。 */
  static offline(anyOk: boolean): boolean {
    return !anyOk;
  }
}
