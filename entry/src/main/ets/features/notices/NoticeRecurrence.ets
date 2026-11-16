import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { NoticeGroup, NoticeOccurrence, NoticeRecurrence } from '../../data/notices/NoticeModels';

/** 通知分区（对齐网页：主列表 / 资料 / 已过期）。 */
export enum NoticeSection {
  PRIMARY = '待处理',
  MATERIAL = '资料',
  EXPIRED = '已过期'
}

const OCCURRENCE_LEAD_MS: number = 24 * 60 * 60 * 1000;
const RECUR_FREQS: string[] = ['daily', 'weekly', 'monthly_day', 'monthly_weeks'];
const TIME_PATTERN: RegExp = new RegExp('^([01]?\\d|2[0-3]):[0-5]\\d$');

/** 长期安排/时间解析与分区（对齐网页 `recurNext` / 三区口径的简化实现）。 */
export class NoticeRecurrenceLogic {
  /** 宽松时间解析：ISO(含偏移/Z) → 本地日期时间 → `MM-dd HH:mm` → `MM-dd`。 */
  static parseTs(raw: string): number {
    const text: string = raw.trim();
    if (text.length === 0) {
      return 0;
    }
    const iso: number = Date.parse(text);
    if (Number.isFinite(iso)) {
      return iso;
    }
    const dateTime: RegExpMatchArray | null = text.match(
      new RegExp('^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})[ T](\\d{1,2}):(\\d{2})(?::(\\d{2}))?$'));
    if (dateTime !== null) {
      const d: Date = new Date(Number(dateTime[1]), Number(dateTime[2]) - 1, Number(dateTime[3]),
        Number(dateTime[4]), Number(dateTime[5]), dateTime[6] !== undefined ? Number(dateTime[6]) : 0);
      return d.getTime();
    }
    const mdhm: RegExpMatchArray | null = text.match(new RegExp('^(\\d{1,2})-(\\d{1,2})[ T](\\d{1,2}):(\\d{2})$'));
    if (mdhm !== null) {
      const year: number = new Date().getFullYear();
      return new Date(year, Number(mdhm[1]) - 1, Number(mdhm[2]), Number(mdhm[3]), Number(mdhm[4]), 0).getTime();
    }
    const md: RegExpMatchArray | null = text.match(new RegExp('^(\\d{1,2})-(\\d{1,2})$'));
    if (md !== null) {
      const year: number = new Date().getFullYear();
      return new Date(year, Number(md[1]) - 1, Number(md[2]), 0, 0, 0).getTime();
    }
    return 0;
  }

  /** 有效 recurrence：freq 合法且 time 为 HH:MM。 */
  static effectiveRecurrence(group: NoticeGroup | undefined): NoticeRecurrence | undefined {
    if (group === undefined || group.recurrence === undefined) {
      return undefined;
    }
    const recur: NoticeRecurrence = group.recurrence;
    if (RECUR_FREQS.indexOf(recur.freq.trim().toLowerCase()) < 0) {
      return undefined;
    }
    if (!TIME_PATTERN.test(recur.time.trim())) {
      return undefined;
    }
    return recur;
  }

  static isLongterm(group: NoticeGroup | undefined): boolean {
    return NoticeRecurrenceLogic.effectiveRecurrence(group) !== undefined;
  }

  /** `until`：`YYYY-MM-DD` 含当天；其它按时间解析；空/非法 → 0。 */
  static recurUntil(group: NoticeGroup): number {
    const recur: NoticeRecurrence | undefined = NoticeRecurrenceLogic.effectiveRecurrence(group);
    if (recur === undefined || recur.until.trim().length === 0) {
      return 0;
    }
    const text: string = recur.until.trim();
    const dateOnly: RegExpMatchArray | null = text.match(new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})$'));
    if (dateOnly !== null) {
      return new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]), 23, 59, 59, 999).getTime();
    }
    return NoticeRecurrenceLogic.parseTs(text);
  }

  /** 下一次发生时间（严格 > now）；无法计算 → 0。 */
  static recurNext(group: NoticeGroup, nowMillis: number): number {
    const recur: NoticeRecurrence | undefined = NoticeRecurrenceLogic.effectiveRecurrence(group);
    if (recur === undefined) {
      return 0;
    }
    const startAt: number = recur.startAt.trim().length > 0 ? NoticeRecurrenceLogic.parseTs(recur.startAt) : 0;
    const reference: number = Math.max(nowMillis, startAt > 0 ? startAt : nowMillis);
    const timeMatch: RegExpMatchArray | null = recur.time.trim().match(new RegExp('^(\\d{1,2}):(\\d{2})$'));
    const hour: number = timeMatch !== null ? Number(timeMatch[1]) : 0;
    const minute: number = timeMatch !== null ? Number(timeMatch[2]) : 0;
    const base: Date = new Date(reference);
    const at = (y: number, m: number, d: number): number => {
      return new Date(y, m, d, hour, minute, 0).getTime();
    };
    if (recur.freq.trim().toLowerCase() === 'daily') {
      let candidate: number = at(base.getFullYear(), base.getMonth(), base.getDate());
      if (candidate <= reference) {
        candidate = at(base.getFullYear(), base.getMonth(), base.getDate() + 1);
      }
      return candidate;
    }
    if (recur.freq.trim().toLowerCase() === 'weekly') {
      if (recur.weekday < 0 || recur.weekday > 6) {
        return 0;
      }
      const cursor: Date = new Date(base.getFullYear(), base.getMonth(), base.getDate(), 0, 0, 0);
      for (let i = 0; i < 62; i++) {
        const candidate: number = at(cursor.getFullYear(), cursor.getMonth(), cursor.getDate());
        if (cursor.getDay() === recur.weekday && candidate > reference) {
          return candidate;
        }
        cursor.setDate(cursor.getDate() + 1);
      }
      return 0;
    }
    if (recur.freq.trim().toLowerCase() === 'monthly_day') {
      if (recur.day < 1 || recur.day > 28) {
        return 0;
      }
      let year: number = base.getFullYear();
      let month: number = base.getMonth();
      for (let i = 0; i < 3; i++) {
        const candidate: number = at(year, month, recur.day);
        if (candidate > reference) {
          return candidate;
        }
        month += 1;
        if (month > 11) {
          month = 0;
          year += 1;
        }
      }
      return 0;
    }
    if (recur.freq.trim().toLowerCase() === 'monthly_weeks') {
      if (recur.weekday < 0 || recur.weekday > 6) {
        return 0;
      }
      const weeks: number[] = [];
      for (let i = 0; i < recur.weeks.length; i++) {
        if (recur.weeks[i] >= 1 && recur.weeks[i] <= 5) {
          weeks.push(recur.weeks[i]);
        }
      }
      if (weeks.length === 0) {
        weeks.push(1);
        weeks.push(2);
        weeks.push(3);
        weeks.push(4);
        weeks.push(5);
      }
      let monthStart: Date = new Date(base.getFullYear(), base.getMonth(), 1, 0, 0, 0);
      for (let m = 0; m < 4; m++) {
        const first: Date = firstWeekdayOfMonth(monthStart.getFullYear(), monthStart.getMonth(), recur.weekday);
        for (let w = 0; w < weeks.length; w++) {
          const candidateDate: Date = new Date(first.getFullYear(), first.getMonth(),
            first.getDate() + (weeks[w] - 1) * 7, hour, minute, 0);
          if (candidateDate.getMonth() !== monthStart.getMonth()) {
            continue;
          }
          const candidate: number = candidateDate.getTime();
          if (candidate > reference) {
            return candidate;
          }
        }
        monthStart = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 1, 0, 0, 0);
      }
      return 0;
    }
    return 0;
  }

  /** 期次（仅 `[next-24h, next)` 窗口内返回）。 */
  static occurrenceOf(entry: NoticeEntry, nowMillis: number): NoticeOccurrence | undefined {
    const group: NoticeGroup | undefined = entry.group;
    if (group === undefined) {
      return undefined;
    }
    const until: number = NoticeRecurrenceLogic.recurUntil(group);
    if (until > 0 && nowMillis > until) {
      return undefined;
    }
    const next: number = NoticeRecurrenceLogic.recurNext(group, nowMillis);
    if (next <= 0) {
      return undefined;
    }
    if (until > 0 && next > until) {
      return undefined;
    }
    const windowStart: number = next - OCCURRENCE_LEAD_MS;
    if (nowMillis < windowStart || nowMillis >= next) {
      return undefined;
    }
    const occurrence: NoticeOccurrence = new NoticeOccurrence();
    occurrence.groupId = group.id.length > 0 ? group.id : entry.id();
    occurrence.title = group.title.length > 0 ? group.title : entry.title();
    occurrence.nextMillis = next;
    occurrence.windowStartMillis = windowStart;
    occurrence.key = NoticeRecurrenceLogic.occurrenceKey(occurrence.groupId, next);
    occurrence.label = NoticeRecurrenceLogic.occurrenceLabel(next, nowMillis);
    return occurrence;
  }

  static occurrenceKey(groupId: string, nextMillis: number): string {
    const d: Date = new Date(nextMillis);
    return groupId + '@occ:' + d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate());
  }

  static occurrenceLabel(nextMillis: number, nowMillis: number): string {
    const d: Date = new Date(nextMillis);
    const today: Date = new Date(nowMillis);
    const tomorrow: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
    let dayText: string = '';
    if (d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth()
      && d.getDate() === today.getDate()) {
      dayText = '今天';
    } else if (d.getFullYear() === tomorrow.getFullYear() && d.getMonth() === tomorrow.getMonth()
      && d.getDate() === tomorrow.getDate()) {
      dayText = '明天';
    } else {
      dayText = (d.getMonth() + 1) + '月' + d.getDate() + '日';
    }
    return '本次 ' + dayText + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  /** 长期安排下一场文案（用于定义卡）。 */
  static nextText(group: NoticeGroup, nowMillis: number): string {
    const next: number = NoticeRecurrenceLogic.recurNext(group, nowMillis);
    if (next <= 0) {
      return '';
    }
    return '下次 ' + NoticeRecurrenceLogic.occurrenceLabel(next, nowMillis).substring(3);
  }

  /** 通知分区。 */
  static sectionOf(entry: NoticeEntry, nowMillis: number): NoticeSection {
    const group: NoticeGroup | undefined = entry.group;
    if (group !== undefined) {
      if (NoticeRecurrenceLogic.isLongterm(group)) {
        const until: number = NoticeRecurrenceLogic.recurUntil(group);
        if (until > 0 && nowMillis > until) {
          return NoticeSection.EXPIRED;
        }
        return NoticeSection.PRIMARY;
      }
      const anchors: number[] = NoticeRecurrenceLogic.timeAnchors(group);
      if (anchors.length === 0) {
        return NoticeSection.MATERIAL;
      }
      let latest: number = 0;
      for (let i = 0; i < anchors.length; i++) {
        latest = Math.max(latest, anchors[i]);
      }
      return latest > 0 && latest < nowMillis ? NoticeSection.EXPIRED : NoticeSection.PRIMARY;
    }
    return NoticeSection.MATERIAL;
  }

  /** 时间锚点（截止/活动/报名截止/失效/过期）。 */
  static timeAnchors(group: NoticeGroup): number[] {
    const out: number[] = [];
    const push = (raw: string): void => {
      if (raw.trim().length === 0) {
        return;
      }
      const ts: number = NoticeRecurrenceLogic.parseTs(raw);
      if (ts > 0) {
        out.push(ts);
      }
    };
    push(group.deadline);
    push(group.eventAt);
    push(group.expireAt);
    return out;
  }

  /** 截止文案（`MM-dd HH:mm`，无可解析 → 原字符串）。 */
  static deadlineText(group: NoticeGroup): string {
    const raw: string = group.deadline.trim();
    if (raw.length === 0) {
      return '';
    }
    const ts: number = NoticeRecurrenceLogic.parseTs(raw);
    if (ts <= 0) {
      return raw;
    }
    const d: Date = new Date(ts);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }
}

function firstWeekdayOfMonth(year: number, month: number, weekday: number): Date {
  const first: Date = new Date(year, month, 1, 0, 0, 0);
  const delta: number = (weekday - first.getDay() + 7) % 7;
  return new Date(year, month, 1 + delta, 0, 0, 0);
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
