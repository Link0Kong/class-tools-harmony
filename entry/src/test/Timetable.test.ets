import { describe, it, expect } from '@ohos/hypium';
import {
  Course,
  SessionInfo,
  SessionState,
  TodayState,
  TtParser,
  TtPeriods,
  TtSnapshot
} from '../main/ets/data/timetable/TimetableModels';
import { TtCalendar } from '../main/ets/data/timetable/TtCalendar';
import { TimetableRepository, TtResult, TtSource } from '../main/ets/data/timetable/TimetableRepository';
import { FakeApi } from './support/FakeApi';
import { Blob } from '../main/ets/data/sync/JsonBlob';

const TERM_START: string = '2026-09-07'; // 周一
const SATURDAY: number = new Date(2026, 10, 14, 10, 0).getTime(); // 11-14 周六 10:00

function course(name: string, day: number, start: number, end: number, weeks: string, parity: string): Course {
  const c: Course = new Course();
  c.name = name;
  c.day = day;
  c.start = start;
  c.end = end;
  c.weeks = weeks;
  c.parity = parity;
  c.room = '综合楼(教室01105)';
  return c;
}

function snapshotWith(courses: Course[], termStart: string): TtSnapshot {
  const snapshot: TtSnapshot = new TtSnapshot();
  snapshot.c = courses;
  snapshot.t = termStart;
  return snapshot;
}

function bodyJson(courses: string, termStart: string): string {
  return '{"c":[' + courses + '],"t":"' + termStart + '"}';
}

export default function timetableTest() {
  describe('TtCalendarBasics', () => {
    it('parses_term_start', 0, () => {
      const date: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      expect(date !== undefined).assertTrue();
      if (date !== undefined) {
        expect(date.getFullYear()).assertEqual(2026);
        expect(date.getMonth()).assertEqual(8);
        expect(date.getDate()).assertEqual(7);
      }
      expect(TtCalendar.parseTermStart('') === undefined).assertTrue();
      expect(TtCalendar.parseTermStart('2026/09/07') === undefined).assertTrue();
    });

    it('parses_weeks_expression', 0, () => {
      const weeks: Set<number> = TtCalendar.parseWeeks('1-3,5，7;9');
      expect(weeks.size).assertEqual(6);
      expect(weeks.has(2)).assertTrue();
      expect(weeks.has(4)).assertFalse();
      expect(weeks.has(9)).assertTrue();
      expect(TtCalendar.parseWeeks('').size).assertEqual(0);
      expect(TtCalendar.parseWeeks('abc').size).assertEqual(0);
    });

    it('week_of_term', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      expect(term !== undefined).assertTrue();
      if (term !== undefined) {
        const sameWeek: Date = new Date(2026, 8, 12, 0, 0, 0); // 09-12 周六
        expect(TtCalendar.weekOf(term, sameWeek)).assertEqual(1);
        const nextWeek: Date = new Date(2026, 8, 14, 0, 0, 0); // 09-14 周一
        expect(TtCalendar.weekOf(term, nextWeek)).assertEqual(2);
        const before: Date = new Date(2026, 8, 1, 0, 0, 0);
        expect(TtCalendar.weekOf(term, before) === undefined).assertTrue();
        expect(TtCalendar.weekOf(undefined, sameWeek) === undefined).assertTrue();
      }
    });

    it('active_by_weeks_and_parity', 0, () => {
      const full: Course = course('全学期', 5, 1, 2, '', 'all');
      expect(TtCalendar.isActive(full, 10)).assertTrue();
      const odd: Course = course('单周', 5, 1, 2, '1-16', 'odd');
      expect(TtCalendar.isActive(odd, 9)).assertTrue();
      expect(TtCalendar.isActive(odd, 10)).assertFalse();
      const even: Course = course('双周', 5, 1, 2, '3-16', 'even');
      expect(TtCalendar.isActive(even, 10)).assertTrue();
      expect(TtCalendar.isActive(even, 1)).assertFalse();
    });

    it('room_short_and_span', 0, () => {
      expect(TtCalendar.roomShort('综合楼(教室01105)')).assertEqual('01105');
      expect(TtCalendar.roomShort('A101')).assertEqual('A101');
      expect(TtCalendar.roomShort('很长的教室名字没有数字'.substring(0, 12))).assertEqual('很长的教室名字…');
      expect(TtCalendar.spanText(1, 2)).assertEqual('1-2 节');
      expect(TtCalendar.spanText(3, 3)).assertEqual('3 节');
    });

    it('periods_table', 0, () => {
      expect(TtPeriods.PERIODS.length).assertEqual(12);
      expect(TtPeriods.startText(1)).assertEqual('08:10');
      expect(TtPeriods.endText(5)).assertEqual('12:10');
      expect(TtPeriods.startText(0)).assertEqual('');
    });
  });

  describe('TtCalendarSessions', () => {
    it('retains the current period while exposing the next bell within a double period', 0, () => {
      const snap = snapshotWith([course('连堂', 4, 1, 2, '', 'all')], TERM_START);
      const time = (h: number, m: number): number => new Date(2026, 10, 6, h, m).getTime();
      const plan = TtCalendar.plan(snap, time(8, 45));
      expect(plan.today[0].span).assertEqual('1 节');
      expect(plan.today[0].state).assertEqual(SessionState.ONGOING);
      expect(plan.today[0].endText).assertEqual('08:50');
      expect(plan.next?.startAt).assertEqual(time(9, 0));
      expect(plan.next?.endText).assertEqual('09:40');
      expect(plan.next?.span).assertEqual('2 节');
      expect(plan.next?.fullRoom).assertEqual('综合楼(教室01105)');
      const inBreak = TtCalendar.plan(snap, time(8, 50));
      expect(inBreak.today[0].state).assertEqual(SessionState.NEXT);
      expect(inBreak.next?.startAt).assertEqual(time(9, 0));
      const onBell = TtCalendar.plan(snap, time(9, 0));
      expect(onBell.today[0].state).assertEqual(SessionState.ONGOING);
      expect(onBell.next?.dayOffset).assertEqual(7);
    });

    it('expands future bells inside the requested day window and respects active weeks', 0, () => {
      const snap = snapshotWith([course('周五', 4, 1, 3, '', 'all'),
        course('周六', 5, 2, 2, '', 'all'), course('过期', 4, 4, 4, '1', 'all')], TERM_START);
      const start = new Date(2026, 10, 6, 8, 10).getTime();
      const bells = TtCalendar.upcomingBells(snap, start, 2);
      expect(bells.map((s: SessionInfo) => s.startText).join(',')).assertEqual('09:00,09:50,09:00');
      expect(bells[0].dayText).assertEqual('今天');
      expect(bells[2].dayText).assertEqual('明天');
      expect(TtCalendar.upcomingBells(snap, start, 1).length).assertEqual(2);
      expect(TtCalendar.upcomingBells(snap, start, 0).length).assertEqual(0);
    });
    it('sessions_on_with_states', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      const courses: Course[] = [course('高数', 5, 1, 2, '1-16', 'all'), course('英语', 5, 3, 4, '1-16', 'all')];
      const date: Date = new Date(2026, 10, 14, 0, 0, 0);
      // 09:30：高数（08:10-09:40）进行中，英语（09:50-11:25）未开始
      const at0930: SessionInfo[] = TtCalendar.sessionsOn(courses, term,
        date, new Date(2026, 10, 14, 9, 30).getTime());
      expect(at0930.length).assertEqual(2);
      expect(at0930[0].state).assertEqual(SessionState.ONGOING);
      expect(at0930[1].state).assertEqual(SessionState.NEXT);
      expect(at0930[0].room).assertEqual('01105');
      // 13:00：都结束
      const at1300: SessionInfo[] = TtCalendar.sessionsOn(courses, term,
        date, new Date(2026, 10, 14, 13, 0).getTime());
      expect(at1300[0].state).assertEqual(SessionState.DONE);
      expect(at1300[1].state).assertEqual(SessionState.DONE);
    });

    it('next_session_today_or_tomorrow', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      const courses: Course[] = [course('高数', 5, 1, 2, '1-16', 'all')];
      // 周六 06:00 → 今天 1-2 节
      const early: SessionInfo | undefined = TtCalendar.nextSession(courses, term,
        new Date(2026, 10, 14, 6, 0).getTime(), 14);
      expect(early !== undefined).assertTrue();
      if (early !== undefined) {
        expect(early.dayOffset).assertEqual(0);
        expect(early.dayText).assertEqual('今天');
      }
      // 周六 13:00 → 今天已结束，下周同一课程（+7 天）
      const after: SessionInfo | undefined = TtCalendar.nextSession(courses, term,
        new Date(2026, 10, 14, 13, 0).getTime(), 14);
      expect(after !== undefined).assertTrue();
      if (after !== undefined) {
        expect(after.dayOffset).assertEqual(7);
      }
    });

    it('courses_on_filters_and_sorts', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      const courses: Course[] = [course('晚课', 5, 10, 12, '', 'all'), course('早课', 5, 1, 2, '', 'all'),
        course('单周课', 5, 3, 4, '1-16', 'odd'), course('别的天', 0, 1, 2, '', 'all')];
      const date: Date = new Date(2026, 10, 14, 0, 0, 0);
      const list: Course[] = TtCalendar.coursesOn(courses, term, date);
      expect(list.length).assertEqual(2);
      expect(list[0].name).assertEqual('早课');
      expect(list[1].name).assertEqual('晚课');
      const oddWeek: Date = new Date(2026, 10, 21, 0, 0, 0);
      const oddOnly: Course[] = TtCalendar.coursesOn(courses, term, oddWeek);
      expect(oddOnly.length).assertEqual(3);
      expect(oddOnly[1].name).assertEqual('单周课');
    });

    it('monday_of_week', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      if (term !== undefined) {
        const monday: Date = TtCalendar.mondayOfWeek(term, 3);
        expect(monday.getMonth()).assertEqual(8);
        expect(monday.getDate()).assertEqual(21);
      }
    });

    it('plan_states', 0, () => {
      const term: Date | undefined = TtCalendar.parseTermStart(TERM_START);
      const date: Date = new Date(2026, 10, 14, 0, 0, 0);
      const empty: TtSnapshot = snapshotWith([], TERM_START);
      expect(TtCalendar.plan(empty, date.getTime()).todayState).assertEqual(TodayState.NODATA);
      expect(TtCalendar.plan(undefined, date.getTime()).hasData).assertFalse();

      const noToday: TtSnapshot = snapshotWith([course('高数', 0, 1, 2, '', 'all')], TERM_START);
      expect(TtCalendar.plan(noToday, date.getTime()).todayState).assertEqual(TodayState.NONE);

      const hasToday: TtSnapshot = snapshotWith([course('高数', 5, 1, 2, '', 'all')], TERM_START);
      const plan = TtCalendar.plan(hasToday, new Date(2026, 10, 14, 8, 30).getTime());
      expect(plan.todayState).assertEqual(TodayState.HAS);
      expect(plan.week).assertEqual(10);
      expect(plan.today.length).assertEqual(1);

      const doneToday = TtCalendar.plan(hasToday, new Date(2026, 10, 14, 20, 0).getTime());
      expect(doneToday.todayState).assertEqual(TodayState.DONE);
      expect(term !== undefined).assertTrue();
    });
  });

  describe('TtParser', () => {
    it('parses_snapshot', 0, () => {
      const body: string = bodyJson('{"name":"高数","day":5,"start":1,"end":2,"weeks":"1-16","parity":"all",'
        + '"room":"A101","teacher":"张老师"}', TERM_START);
      const snapshot: TtSnapshot | undefined = TtParser.parseSnapshot(body);
      expect(snapshot !== undefined).assertTrue();
      if (snapshot !== undefined) {
        expect(snapshot.c.length).assertEqual(1);
        expect(snapshot.c[0].name).assertEqual('高数');
        expect(snapshot.c[0].teacher).assertEqual('张老师');
        expect(snapshot.termStart()).assertEqual(TERM_START);
      }
      expect(TtParser.parseSnapshot('') === undefined).assertTrue();
      expect(TtParser.parseSnapshot('bad') === undefined).assertTrue();
    });

    it('drops_invalid_courses', 0, () => {
      const body: string = bodyJson('{"name":"坏课","day":9,"start":1,"end":2}'
        + ',{"name":"倒序","day":1,"start":5,"end":3}'
        + ',{"name":"好课","day":1,"start":1,"end":2}', TERM_START);
      const snapshot: TtSnapshot | undefined = TtParser.parseSnapshot(body);
      expect(snapshot !== undefined).assertTrue();
      if (snapshot !== undefined) {
        expect(snapshot.c.length).assertEqual(1);
        expect(snapshot.c[0].name).assertEqual('好课');
      }
    });

    it('meta_term_start_wins', 0, () => {
      const body: string = '{"c":[],"t":"2026-09-01","meta":{"termStart":"2026-09-07"}}';
      const snapshot: TtSnapshot | undefined = TtParser.parseSnapshot(body);
      expect(snapshot !== undefined).assertTrue();
      if (snapshot !== undefined) {
        expect(snapshot.termStart()).assertEqual('2026-09-07');
      }
    });
  });

  describe('TimetableRepository', () => {
    it('parses_site_asset_object_body', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.siteAssetsBody = '[{"id":"tt","body":{"c":[{"name":"高数","day":5,"start":1,"end":2}],"t":"2026-09-07"}}]';
      const repo: TimetableRepository = new TimetableRepository(api, () => undefined, () => SATURDAY, 0);
      const result: TtResult = await repo.load(false);
      expect(result.ok).assertTrue();
      expect(result.snapshot !== undefined).assertTrue();
      if (result.snapshot !== undefined) {
        expect(result.snapshot.c.length).assertEqual(1);
      }
      expect(result.source).assertEqual(TtSource.PUBLIC);
      expect(result.fromCache).assertFalse();
    });

    it('personal_snapshot_has_priority', 0, async () => {
      const api: FakeApi = new FakeApi();
      const personal: Blob = JSON.parse('{"ttUseMine":true,"ttLocal":{"c":[{"name":"我的课","day":5,"start":1,"end":2}],'
        + '"t":"2026-09-07"}}') as Blob;
      const repo: TimetableRepository = new TimetableRepository(api, () => personal, () => SATURDAY, 0);
      const result: TtResult = await repo.load(true);
      expect(result.ok).assertTrue();
      expect(result.source).assertEqual(TtSource.PERSONAL);
      if (result.snapshot !== undefined) {
        expect(result.snapshot.c[0].name).assertEqual('我的课');
      }
      expect(api.getPaths.length).assertEqual(0);
    });

    it('ttl_cache_and_fallback', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.siteAssetsBody = '[{"id":"tt","body":"{\\"c\\":[{\\"name\\":\\"高数\\",\\"day\\":5,\\"start\\":1,\\"end\\":2}],'
        + '\\"t\\":\\"2026-09-07\\"}"}]';
      let now: number = 1000;
      const repo: TimetableRepository = new TimetableRepository(api, () => undefined, () => now, 1000);
      await repo.load(false);
      const cached: TtResult = await repo.load(false);
      expect(cached.fromCache).assertTrue();
      expect(api.getPaths.length).assertEqual(1);
      now = 5000;
      api.failGets = true;
      const fallback: TtResult = await repo.load(true);
      expect(fallback.ok).assertTrue();
      expect(fallback.fromCache).assertTrue();
      expect(fallback.snapshot !== undefined).assertTrue();
    });

    it('coalesces_concurrent_loads', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.siteAssetsBody = '[{"id":"tt","body":{"c":[{"name":"高数","day":5,"start":1,"end":2}],"t":"2026-09-07"}}]';
      const repo: TimetableRepository = new TimetableRepository(api, () => undefined, () => SATURDAY, 0);
      const first = repo.load(false);
      const second = repo.load(false);
      const a: TtResult = await first;
      const b: TtResult = await second;
      expect(a.ok).assertTrue();
      expect(b.ok).assertTrue();
      expect(a.snapshot !== undefined).assertTrue();
      expect(b.snapshot !== undefined).assertTrue();
      expect(api.getPaths.length).assertEqual(1);
    });

    it('empty_site_asset_is_failure', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.siteAssetsBody = '[]';
      const repo: TimetableRepository = new TimetableRepository(api, () => undefined, () => SATURDAY, 0);
      const result: TtResult = await repo.load(true);
      expect(result.ok).assertFalse();
      expect(result.message.length > 0).assertTrue();
    });
  });
}
