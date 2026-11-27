import { Course, SessionInfo, SessionState, TodayState, TtPeriods, TtPlan, TtSnapshot } from './TimetableModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;

/**
 * 课表日历纯函数（与小程序 `utils/ttplan.js` 同口径）。
 *
 * - 周次：`floor(days(today - termStart)/7) + 1`（开学当周为第 1 周；开学前 undefined）；
 * - 上课判定：`weeks` 空 = 全学期；非空需包含该周；再按 parity 过滤单双周；
 * - 下一节：今天起 14 天内按真实时间找最近一节。
 */
export class TtCalendar {
  /** 解析开学日（容忍前 10 位是 YYYY-MM-DD 的 ISO 字符串）。 */
  static parseTermStart(raw: string): Date | undefined {
    const text: string = raw.trim();
    if (text.length < 10) {
      return undefined;
    }
    const match: RegExpMatchArray | null = text.substring(0, 10).match(new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})$'));
    if (match === null) {
      return undefined;
    }
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return undefined;
    }
    return new Date(year, month - 1, day, 0, 0, 0);
  }

  /** 解析周次表达式："1-16,18"（容忍中文逗号/顿号/空格；非法 token 忽略）。 */
  static parseWeeks(spec: string): Set<number> {
    const out: Set<number> = new Set<number>();
    const text: string = spec.trim();
    if (text.length === 0) {
      return out;
    }
    const tokens: string[] = text.split(new RegExp('[,，;；\\s]+'));
    for (let i = 0; i < tokens.length; i++) {
      const token: string = tokens[i].trim();
      if (token.length === 0) {
        continue;
      }
      const dash: number = token.indexOf('-');
      if (dash > 0 && dash < token.length - 1) {
        const a: number = Number(token.substring(0, dash).trim());
        const b: number = Number(token.substring(dash + 1).trim());
        if (Number.isFinite(a) && Number.isFinite(b)) {
          const lo: number = Math.min(a, b);
          const hi: number = Math.max(a, b);
          for (let w = lo; w <= hi; w++) {
            if (w >= 1 && w <= 60) {
              out.add(w);
            }
          }
        }
      } else {
        const w: number = Number(token);
        if (Number.isFinite(w) && w >= 1 && w <= 60) {
          out.add(w);
        }
      }
    }
    return out;
  }

  /** 本地日期 → epoch day（避免时区偏移）。 */
  static epochDay(date: Date): number {
    return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / DAY_MS);
  }

  /** 指定日期属于第几周（开学当周=1；开学前/开学日无效 → undefined）。 */
  static weekOf(termStart: Date | undefined, date: Date): number | undefined {
    if (termStart === undefined) {
      return undefined;
    }
    const diffDays: number = TtCalendar.epochDay(date) - TtCalendar.epochDay(termStart);
    const week: number = Math.floor(diffDays / 7) + 1;
    return week > 0 ? week : undefined;
  }

  /** 某门课在第 week 周是否上课（undefined 视为不按周过滤）。 */
  static isActive(course: Course, week: number | undefined): boolean {
    if (week === undefined) {
      return true;
    }
    const weeks: Set<number> = TtCalendar.parseWeeks(course.weeks);
    if (weeks.size > 0 && !weeks.has(week)) {
      return false;
    }
    if (course.parity === 'odd') {
      return week % 2 === 1;
    }
    if (course.parity === 'even') {
      return week % 2 === 0;
    }
    return true;
  }

  /** 星期索引：0=周一 … 6=周日。 */
  static dayIndex(date: Date): number {
    return (date.getDay() + 6) % 7;
  }

  /** 教室短标识：优先取房间号（如「综合楼(教室01105)」→ "01105"）。 */
  static roomShort(room: string): string {
    const s: string = room.trim();
    if (s.length === 0) {
      return '';
    }
    if (s.length <= 7) {
      return s;
    }
    const numberMatch: RegExpMatchArray | null = s.match(new RegExp('\\d{3,6}'));
    if (numberMatch !== null) {
      return numberMatch[0];
    }
    const rangeMatch: RegExpMatchArray | null = s.match(new RegExp('\\d+-\\d+'));
    if (rangeMatch !== null) {
      return rangeMatch[0];
    }
    return s.substring(0, 7) + '…';
  }

  /** 节次跨度文案：`1-2 节` / `3 节`。 */
  static spanText(start: number, end: number): string {
    return start === end ? start + ' 节' : start + '-' + end + ' 节';
  }

  /** 指定日期的课程（未过滤时间，供周视图渲染）。 */
  static coursesOn(courses: Course[], termStart: Date | undefined, date: Date): Course[] {
    const week: number | undefined = TtCalendar.weekOf(termStart, date);
    const dayIdx: number = TtCalendar.dayIndex(date);
    const out: Course[] = [];
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      if (course.day !== dayIdx) {
        continue;
      }
      if (!TtCalendar.isActive(course, week)) {
        continue;
      }
      if (course.start < 1 || course.end > TtPeriods.PERIODS.length || course.end < course.start) {
        continue;
      }
      out.push(course);
    }
    out.sort((a: Course, b: Course) => a.start - b.start);
    return out;
  }

  private static session(course: Course, date: Date, start: number, end: number, now: number): SessionInfo {
    const session = new SessionInfo();
    session.name = course.name.trim() || '课程';
    session.fullRoom = course.room.trim();
    session.room = TtCalendar.roomShort(session.fullRoom);
    session.teacher = course.teacher.trim();
    session.period = start;
    session.start = course.start;
    session.end = course.end;
    session.startText = TtPeriods.startText(start);
    session.endText = TtPeriods.endText(end);
    session.startAt = TtCalendar.at(date, session.startText);
    session.endAt = TtCalendar.at(date, session.endText);
    session.state = now >= session.endAt ? SessionState.DONE : now >= session.startAt ? SessionState.ONGOING : SessionState.NEXT;
    session.span = TtCalendar.spanText(start, end);
    return session;
  }

  /** 课程表保留整次课；动态摘要可按当前节的下课铃或下一节的上课铃定位。 */
  static sessionsOn(courses: Course[], termStart: Date | undefined, date: Date, nowMillis: number,
    focusOnBell: boolean = false, upcomingBell: boolean = false): SessionInfo[] {
    if (TtCalendar.weekOf(termStart, date) === undefined) return [];
    const day = TtCalendar.coursesOn(courses, termStart, date);
    const sessions: SessionInfo[] = [];
    for (const course of day) {
      let session = TtCalendar.session(course, date, course.start, course.end, nowMillis);
      if (focusOnBell && session.state === SessionState.ONGOING) {
        for (let p = course.start; p <= course.end; p++) {
          const boundary = upcomingBell ? TtPeriods.startText(p) : TtPeriods.endText(p);
          if (nowMillis < TtCalendar.at(date, boundary)) {
            session = TtCalendar.session(course, date, p, p, nowMillis);
            break;
          }
        }
      }
      sessions.push(session);
    }
    return sessions.sort((a: SessionInfo, b: SessionInfo) => a.startAt - b.startAt);
  }

  private static describeDay(session: SessionInfo, date: Date, offset: number): void {
    session.dayOffset = offset;
    session.dayText = offset === 0 ? '今天' : offset === 1 ? '明天' : TtPeriods.DAY_LABELS[TtCalendar.dayIndex(date)];
    session.dateText = (date.getMonth() + 1) + '-' + date.getDate();
  }

  /** 今天起 days 个自然日内的所有未来上课铃。合并显示的一门连堂课在这里按实际上课节次展开。 */
  static upcomingBells(snapshot: TtSnapshot, now: number, days: number): SessionInfo[] {
    const term = TtCalendar.parseTermStart(snapshot.termStart());
    if (!term || !Number.isFinite(days) || days <= 0) return [];
    const today = new Date(now);
    const bells: SessionInfo[] = [];
    for (let offset = 0; offset < Math.floor(days); offset++) {
      const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
      if (TtCalendar.weekOf(term, date) === undefined) continue;
      const courses = TtCalendar.coursesOn(snapshot.c, term, date);
      for (const course of courses) {
        for (let period = course.start; period <= course.end; period++) {
          const bell = TtCalendar.session(course, date, period, period, now);
          if (bell.startAt <= now) continue;
          if (period > 1) {
            const gap = bell.startAt - TtCalendar.at(date, TtPeriods.endText(period - 1));
            bell.afterShortBreak = gap > 0 && gap <= 10 * 60000 &&
              courses.some((c: Course) => c.start <= period - 1 && c.end >= period - 1);
          }
          bell.week = TtCalendar.weekOf(term, date) ?? 0;
          TtCalendar.describeDay(bell, date, offset);
          bells.push(bell);
        }
      }
    }
    return bells.sort((a: SessionInfo, b: SessionInfo) => a.startAt - b.startAt);
  }

  /** 下一次严格晚于当前时刻的上课铃，包含连堂课内尚未开始的节次。 */
  static nextSession(courses: Course[], termStart: Date | undefined, nowMillis: number,
    lookAheadDays: number): SessionInfo | undefined {
    const today: Date = new Date(nowMillis);
    for (let offset = 0; offset <= lookAheadDays; offset++) {
      const date: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset, 0, 0, 0);
      const sessions: SessionInfo[] = TtCalendar.sessionsOn(courses, termStart, date, nowMillis, true, true);
      for (let i = 0; i < sessions.length; i++) {
        const session: SessionInfo = sessions[i];
        if (session.startAt <= nowMillis) {
          continue;
        }
        TtCalendar.describeDay(session, date, offset);
        return session;
      }
    }
    return undefined;
  }

  /** 课表页计算产物（今日课程 + 今日状态 + 下一节 + 当前周）。 */
  static plan(snapshot: TtSnapshot | undefined, nowMillis: number): TtPlan {
    const plan: TtPlan = new TtPlan();
    if (snapshot === undefined || snapshot.c.length === 0) {
      plan.hasData = false;
      plan.todayState = TodayState.NODATA;
      return plan;
    }
    const termStart: Date | undefined = TtCalendar.parseTermStart(snapshot.termStart());
    if (termStart === undefined) {
      return plan;
    }
    plan.hasData = true;
    const today: Date = new Date(nowMillis);
    plan.week = TtCalendar.weekOf(termStart, today);
    plan.today = TtCalendar.sessionsOn(snapshot.c, termStart, today, nowMillis, true);
    plan.next = TtCalendar.nextSession(snapshot.c, termStart, nowMillis, 14);
    for (const session of plan.today) {
      if (session.state === SessionState.ONGOING) {
        session.countdown = '距下课 ' + Math.ceil((session.endAt - nowMillis) / 60000) + ' 分钟';
      } else if (session.state === SessionState.NEXT && session.startAt === plan.next?.startAt) {
        const minutes = Math.ceil((session.startAt - nowMillis) / 60000);
        session.countdown = minutes <= 10 ? '距上课 ' + minutes + ' 分钟' : '下一节';
      }
    }
    if (plan.today.length === 0) {
      plan.todayState = TodayState.NONE;
    } else {
      let hasOngoingOrNext: boolean = false;
      for (let i = 0; i < plan.today.length; i++) {
        if (plan.today[i].state !== SessionState.DONE) {
          hasOngoingOrNext = true;
        }
      }
      plan.todayState = hasOngoingOrNext ? TodayState.HAS : TodayState.DONE;
    }
    return plan;
  }

  /** 指定日期 + `HH:MM` → epoch ms。 */
  static at(date: Date, hhmm: string): number {
    const match: RegExpMatchArray | null = hhmm.match(new RegExp('^(\\d{1,2}):(\\d{2})$'));
    if (match === null) {
      return 0;
    }
    const hour: number = Number(match[1]);
    const minute: number = Number(match[2]);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour, minute, 0).getTime();
  }

  /** 第 N 周的周一日期（用于周视图）。 */
  static mondayOfWeek(termStart: Date, week: number): Date {
    return new Date(termStart.getFullYear(), termStart.getMonth(), termStart.getDate() + (week - 1) * 7, 0, 0, 0);
  }
}
