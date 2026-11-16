import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { NoticeGroup, NoticeRecurrence } from '../../data/notices/NoticeModels';
import { NoticeRecurrenceLogic } from './NoticeRecurrence';

/** 状态胶囊（与小程序 `utils/notice.js statusOf` 同口径）。 */
export class NoticeStatusInfo {
  key: string = 'none';
  label: string = '无时间';
  cls: string = 'none';
  expired: boolean = false;
  /** 主显示时间（deadline / eventAt），无时间 → 0。 */
  whenAt: number = 0;
}

const WEEK_CN: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const HOUR_MS: number = 60 * 60 * 1000;
const DAY_MS: number = 24 * HOUR_MS;

/** 通知状态机 + 时间文案（纯函数，可单测）。 */
export class NoticeStatus {
  static pad2(value: number): string {
    return value < 10 ? '0' + value : '' + value;
  }

  /** 主显示时间：截止 → 活动时间；长期安排 → 状态胶囊不带日期。 */
  static whenAt(group: NoticeGroup | undefined): number {
    if (group === undefined) {
      return 0;
    }
    const deadline: number = NoticeRecurrenceLogic.parseTs(group.deadline);
    if (deadline > 0) {
      return deadline;
    }
    return NoticeRecurrenceLogic.parseTs(group.eventAt);
  }

  /** `MM-DD HH:MM`。 */
  static shortTime(ts: number): string {
    const d: Date = new Date(ts);
    return NoticeStatus.pad2(d.getMonth() + 1) + '-' + NoticeStatus.pad2(d.getDate())
      + ' ' + NoticeStatus.pad2(d.getHours()) + ':' + NoticeStatus.pad2(d.getMinutes());
  }

  /** 紧迫度文案：已过 / N 分钟后 / N 小时后 / N 天后 / MM-DD HH:MM。 */
  static fmtWhen(ts: number, now: number): string {
    const left: number = ts - now;
    if (left <= 0) {
      return NoticeStatus.shortTime(ts);
    }
    if (left < HOUR_MS) {
      return Math.max(1, Math.round(left / 60000)) + ' 分钟后';
    }
    if (left < DAY_MS) {
      return Math.max(1, Math.round(left / HOUR_MS)) + ' 小时后';
    }
    if (left < 7 * DAY_MS) {
      return Math.max(1, Math.round(left / DAY_MS)) + ' 天后';
    }
    return NoticeStatus.shortTime(ts);
  }

  /** 动作文案精简（≤6 字）。 */
  static conciseAction(action: string): string {
    const text: string = action.trim();
    if (text.length === 0) {
      return '截止';
    }
    if (text === '报送姓名截止') {
      return '报送截止';
    }
    if (text === '集合点名') {
      return '点名';
    }
    if (text === '活动开始') {
      return '开始';
    }
    if (text === '报名已截止') {
      return '报名截止';
    }
    return text.length > 6 ? text.substring(0, 6) : text;
  }

  private static bucketOf(ts: number, action: string, now: number): NoticeStatusInfo {
    const info: NoticeStatusInfo = new NoticeStatusInfo();
    info.label = NoticeStatus.fmtWhen(ts, now) + ' ' + NoticeStatus.conciseAction(action);
    info.whenAt = ts;
    const left: number = ts - now;
    if (left < HOUR_MS) {
      info.key = 'urgent';
      info.cls = 'urgent';
    } else if (left < DAY_MS) {
      info.key = 'today';
      info.cls = 'urgent';
    } else if (left < 3 * DAY_MS) {
      info.key = 'soon';
      info.cls = 'active';
    } else {
      info.key = 'active';
      info.cls = 'active';
    }
    info.expired = false;
    return info;
  }

  static statusOf(group: NoticeGroup | undefined, now: number): NoticeStatusInfo {
    if (group === undefined) {
      return new NoticeStatusInfo();
    }
    const recur: NoticeRecurrence | undefined = NoticeRecurrenceLogic.effectiveRecurrence(group);
    if (recur !== undefined) {
      const until: number = NoticeRecurrenceLogic.recurUntil(group);
      const next: number = NoticeRecurrenceLogic.recurNext(group, now);
      const ended: boolean = (until > 0 && now > until) || (until > 0 && next > until);
      const info: NoticeStatusInfo = new NoticeStatusInfo();
      if (ended) {
        info.key = 'expired';
        info.cls = 'expired';
        info.expired = true;
        info.label = '长期安排已结束';
        return info;
      }
      info.key = 'recurring';
      info.cls = 'recurring';
      info.expired = false;
      info.whenAt = next;
      const label: string = recur.label.trim();
      info.label = label.length > 0 ? ('长期安排 · ' + label) : '长期安排';
      return info;
    }
    const deadline: number = NoticeRecurrenceLogic.parseTs(group.deadline);
    if (deadline > 0) {
      const action: string = group.alert ? '截止' : '截止';
      if (now > deadline) {
        const info: NoticeStatusInfo = new NoticeStatusInfo();
        info.key = group.alert ? 'alert' : 'expired';
        info.cls = group.alert ? 'alert' : 'expired';
        info.expired = !group.alert;
        info.label = NoticeStatus.fmtWhen(deadline, now) + ' ' + NoticeStatus.conciseAction(action);
        info.whenAt = deadline;
        return info;
      }
      return NoticeStatus.bucketOf(deadline, action, now);
    }
    const eventAt: number = NoticeRecurrenceLogic.parseTs(group.eventAt);
    if (eventAt > 0) {
      const end: number = Math.max(eventAt, NoticeRecurrenceLogic.parseTs(group.expireAt));
      if (now > end) {
        const info: NoticeStatusInfo = new NoticeStatusInfo();
        info.key = 'expired';
        info.cls = 'expired';
        info.expired = true;
        info.label = NoticeStatus.fmtWhen(eventAt, now) + ' 开始';
        info.whenAt = eventAt;
        return info;
      }
      const info: NoticeStatusInfo = new NoticeStatusInfo();
      info.key = 'active';
      info.cls = 'active';
      info.expired = false;
      info.label = NoticeStatus.fmtWhen(eventAt, now) + ' 开始';
      info.whenAt = eventAt;
      return info;
    }
    const none: NoticeStatusInfo = new NoticeStatusInfo();
    none.whenAt = 0;
    return none;
  }

  /** 状态（含手动通知兜底：无 group 按「无时间」）。 */
  static ofEntry(entry: NoticeEntry, now: number): NoticeStatusInfo {
    const info: NoticeStatusInfo = NoticeStatus.statusOf(entry.group, now);
    if (entry.group === undefined && info.whenAt === 0 && entry.row.ts > 0) {
      info.label = '无时间';
    }
    return info;
  }

  /** `M月D日（周X）`（跨年补年份）。 */
  static dateCnOf(ts: number, now: number): string {
    const d: Date = new Date(ts);
    const n: Date = new Date(now);
    const yearPrefix: string = d.getFullYear() !== n.getFullYear() ? (d.getFullYear() + '年') : '';
    return yearPrefix + (d.getMonth() + 1) + '月' + d.getDate() + '日（' + WEEK_CN[d.getDay()] + '）';
  }

  /** `M月D日（周X）HH:MM`。 */
  static dateTimeCnOf(ts: number, now: number): string {
    const d: Date = new Date(ts);
    return NoticeStatus.dateCnOf(ts, now) + NoticeStatus.pad2(d.getHours()) + ':' + NoticeStatus.pad2(d.getMinutes());
  }

  /** 文本里的日期 token → `M月D日（周X）`（已带括号不重复）。 */
  static fmtDatesCn(text: string, now: number): string {
    let src: string = text;
    if (src.length === 0) {
      return src;
    }
    const n: Date = new Date(now);
    const year: number = n.getFullYear();
    src = src.replace(new RegExp('(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})', 'g'),
      (match: string, y: string, mo: string, da: string): string => {
        if (!validMd(Number(mo), Number(da))) {
          return match;
        }
        return NoticeStatus.dateCnOf(new Date(Number(y), Number(mo) - 1, Number(da)).getTime(), now);
      });
    src = src.replace(new RegExp('(\\d{1,2})月(\\d{1,2})日(?!\\s*[（(])', 'g'),
      (match: string, mo: string, da: string): string => {
        if (!validMd(Number(mo), Number(da))) {
          return match;
        }
        return NoticeStatus.dateCnOf(new Date(year, Number(mo) - 1, Number(da)).getTime(), now);
      });
    src = src.replace(new RegExp('(^|[^0-9:\\-])(\\d{1,2})-(\\d{1,2})(?![0-9\\-人个次名天周月年元度分条项张份间号栋楼届])', 'g'),
      (match: string, pre: string, mo: string, da: string): string => {
        if (!validMd(Number(mo), Number(da))) {
          return match;
        }
        return pre + NoticeStatus.dateCnOf(new Date(year, Number(mo) - 1, Number(da)).getTime(), now);
      });
    return src;
  }

  /** 发布时间相对文案：今天 12:49 / 昨天 12:49 / 11-12 12:49。 */
  static latestTextOf(ts: number, now: number): string {
    if (ts <= 0) {
      return '—';
    }
    const d: Date = new Date(ts);
    const n: Date = new Date(now);
    const sameDay: boolean = d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth()
      && d.getDate() === n.getDate();
    const hm: string = NoticeStatus.pad2(d.getHours()) + ':' + NoticeStatus.pad2(d.getMinutes());
    if (sameDay) {
      return '今天 ' + hm;
    }
    const yesterday: Date = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1);
    if (d.getFullYear() === yesterday.getFullYear() && d.getMonth() === yesterday.getMonth()
      && d.getDate() === yesterday.getDate()) {
      return '昨天 ' + hm;
    }
    return NoticeStatus.shortTime(ts);
  }

  /** 原样文案（期次胶囊）。 */
  static occurrenceLabel(nextMillis: number, now: number): string {
    const d: Date = new Date(nextMillis);
    return '本次 ' + (d.getMonth() + 1) + '月' + d.getDate() + '日（' + WEEK_CN[d.getDay()] + '）'
      + NoticeStatus.pad2(d.getHours()) + ':' + NoticeStatus.pad2(d.getMinutes());
  }
}

function validMd(month: number, day: number): boolean {
  if (!(month >= 1 && month <= 12) || !(day >= 1 && day <= 31)) {
    return false;
  }
  const d: Date = new Date(2000, month - 1, day);
  return d.getMonth() === month - 1 && d.getDate() === day;
}
