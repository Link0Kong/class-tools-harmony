import { Blob, JsonBlob } from '../sync/JsonBlob';

/** 一门课（day 0=周一；start/end 为节次 1..12）。 */
export class Course {
  name: string = '';
  teacher: string = '';
  room: string = '';
  day: number = 0;
  start: number = 1;
  end: number = 1;
  /** 周次表达式，如 "1-16,18"；空 = 全学期。 */
  weeks: string = '';
  /** all | odd | even（单双周）。 */
  parity: string = 'all';
}

/** 课表快照：`c` 课程数组 + `t` 开学日 + 可选 `meta`。 */
export class TtSnapshot {
  c: Course[] = [];
  t: string = '';
  termStartMeta: string = '';

  /** 开学日解析优先级：meta.termStart → t。 */
  termStart(): string {
    return this.termStartMeta.trim().length > 0 ? this.termStartMeta.trim() : this.t.trim();
  }
}

/** 节次时间表（12 节固定，与小程序 PERIODS 一致）。 */
export class TtPeriods {
  static readonly PERIODS: string[][] = [
    ['08:10', '08:50'],
    ['09:00', '09:40'],
    ['09:50', '10:30'],
    ['10:40', '11:20'],
    ['11:30', '12:10'],
    ['14:30', '15:10'],
    ['15:20', '16:00'],
    ['16:10', '16:50'],
    ['17:00', '17:40'],
    ['19:00', '19:40'],
    ['19:50', '20:30'],
    ['20:40', '21:20']
  ];

  static readonly DAY_LABELS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static startText(period: number): string {
    return period >= 1 && period <= TtPeriods.PERIODS.length ? TtPeriods.PERIODS[period - 1][0] : '';
  }

  static endText(period: number): string {
    return period >= 1 && period <= TtPeriods.PERIODS.length ? TtPeriods.PERIODS[period - 1][1] : '';
  }
}

export enum SessionState {
  NEXT = 'next',
  ONGOING = 'ongoing',
  DONE = 'done'
}

export enum TodayState {
  NODATA = 'nodata',
  NONE = 'none',
  HAS = 'has',
  DONE = 'done'
}

/** 一次课程占用（今日课程/下一节/日视图）。 */
export class SessionInfo {
  teacher: string = '';
  period: number = 0;
  week: number = 0;
  name: string = '';
  room: string = '';
  fullRoom: string = '';
  start: number = 1;
  end: number = 1;
  startText: string = '';
  endText: string = '';
  span: string = '';
  startAt: number = 0;
  endAt: number = 0;
  state: SessionState = SessionState.NEXT;
  afterShortBreak: boolean = false;
  countdown: string = '';
  dayOffset: number = 0;
  dayText: string = '';
  dateText: string = '';
}

/** 课表页/工作台共用计算产物。 */
export class TtPlan {
  hasData: boolean = false;
  week: number | undefined = undefined;
  today: SessionInfo[] = [];
  todayState: TodayState = TodayState.NODATA;
  next: SessionInfo | undefined = undefined;
}

/** 解析课表快照（`body` 可能是对象或 JSON 字符串）。 */
export class TtParser {
  static parseSnapshot(body: string): TtSnapshot | undefined {
    if (body.trim().length === 0) {
      return undefined;
    }
    let parsed: Blob | undefined = JsonBlob.parse(body);
    if (parsed === undefined) {
      // body 可能是「JSON 字符串里再套 JSON」
      const inner: string = body.trim();
      if (inner.indexOf('"c"') >= 0) {
        return undefined;
      }
      return undefined;
    }
    const snapshot: TtSnapshot = new TtSnapshot();
    snapshot.t = JsonBlob.asString(JsonBlob.get(parsed, 't'), '');
    const meta: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(parsed, 'meta'));
    if (meta !== undefined) {
      snapshot.termStartMeta = JsonBlob.asString(JsonBlob.get(meta, 'termStart'), '');
    }
    const courses: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(parsed, 'c'));
    if (courses !== undefined) {
      for (let i = 0; i < courses.length; i++) {
        const obj: Blob | undefined = JsonBlob.asBlob(courses[i]);
        if (obj === undefined) {
          continue;
        }
        const course: Course = new Course();
        course.name = JsonBlob.asString(JsonBlob.get(obj, 'name') ?? JsonBlob.get(obj, 'n'), '').trim();
        course.teacher = JsonBlob.asString(JsonBlob.get(obj, 'teacher'), '');
        course.room = JsonBlob.asString(JsonBlob.get(obj, 'room'), '');
        course.day = TtParser.courseNumber(obj, 'day', -1);
        course.start = TtParser.courseNumber(obj, 'start', 1);
        course.end = TtParser.courseNumber(obj, 'end', course.start);
        course.weeks = JsonBlob.asString(JsonBlob.get(obj, 'weeks'), '');
        course.parity = JsonBlob.asString(JsonBlob.get(obj, 'parity'), 'all');
        if (course.name.length > 0 && course.day >= 0 && course.day <= 6 &&
          course.start >= 1 && course.end >= course.start) {
          snapshot.c.push(course);
        }
      }
    }
    return snapshot;
  }

  private static courseNumber(row: Blob, key: string, fallback: number): number {
    const value = JsonBlob.get(row, key);
    const number = typeof value === 'string' && value.trim().length ? Number(value) : JsonBlob.asNumber(value, fallback);
    return Number.isFinite(number) ? Math.round(number) : fallback;
  }

  /** `site_assets` 行的 body（jsonb 可能是对象，也可能是字符串）。 */
  static bodyOf(row: Blob): string {
    const body = JsonBlob.get(row, 'body');
    if (body === null || body === undefined) {
      return '';
    }
    if (typeof body === 'string') {
      return body as string;
    }
    return JSON.stringify(body);
  }
}
