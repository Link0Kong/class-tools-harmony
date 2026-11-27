import { describe, it, expect } from '@ohos/hypium';
import { Course, TtPlan, TtSnapshot } from '../main/ets/data/timetable/TimetableModels';
import { TtCalendar } from '../main/ets/data/timetable/TtCalendar';
import { HOME_DEFAULT_REGION, HomeAppearance, HomeContextRules, HomeCourseContext, HomePhraseBatch, HomePhraseContext,
  HomeReading, HomeTimetableState, HomeWeather } from '../main/ets/features/home/HomeContext';
import { HOME_LOCAL_PHRASES } from '../main/ets/features/home/HomePhrases';

export default function homeContextTest(): void {
  describe('HomeContext', () => {
    it('keeps the Android catalogue and the Minhou default', 0, () => {
      expect(HOME_LOCAL_PHRASES.length).assertEqual(57);
      expect(HOME_LOCAL_PHRASES.filter((line) => line.topic === 'ENGLISH' && !!line.translation).length).assertEqual(9);
      expect(new Set<string>(HOME_LOCAL_PHRASES.map((line) => line.id)).size).assertEqual(57);
      expect(new HomeAppearance().regionId).assertEqual('minhou');
      expect(HOME_DEFAULT_REGION.label).assertEqual('福州市闽侯县');
    });

    it('rejects data from the previous district and expired weather', 0, () => {
      const stamp = Date.parse('2026-11-27T13:00:00Z');
      const weather: HomeWeather = {
        regionId: 'minhou', validTime: '2026-11-27T13:00:00Z', conditionCode: 100, conditionText: '晴',
        sunrise: '2026-11-27T06:30:00+08:00', sunset: '2026-11-27T17:20:00+08:00'
      };
      expect(HomeContextRules.validWeather(weather, 'minhou', stamp)).assertTrue();
      expect(HomeContextRules.validWeather(weather, '1810815', stamp)).assertFalse();
      expect(HomeContextRules.validWeather(weather, 'minhou', stamp + 45 * 60 * 1000)).assertFalse();
      expect(HomeContextRules.weatherTopic(weather, stamp)).assertEqual('CLEAR_NIGHT');
    });

    it('picks a real upcoming course before rain and keeps a same-context reading', 0, () => {
      const now = new Date(2026, 10, 23, 8, 4).getTime();
      const snapshot = new TtSnapshot();
      snapshot.t = '2026-11-23';
      const course = new Course();
      course.name = '数据课';
      course.room = '测试楼';
      snapshot.c = [course];
      const plan = TtCalendar.plan(snapshot, now);
      const info = HomeContextRules.course(plan, HomeTimetableState.Ready, now);
      expect(info.topic).assertEqual('UPCOMING');
      expect(info.focus?.name ?? '').assertEqual('数据课');
      const weather: HomeWeather = { regionId: 'minhou', validTime: new Date(now).toISOString(),
        conditionCode: 305, conditionText: '小雨' };
      const context = new HomePhraseContext(now, 'minhou', weather, info);
      const prefs = new HomeAppearance();
      const history = new Map<string, number>();
      const phrase = HomeContextRules.pick(HOME_LOCAL_PHRASES, context, prefs, history, now, 1);
      expect(phrase?.topic ?? '').assertEqual('UPCOMING');
      if (phrase) {
        const saved = new HomeReading(phrase, context, 0);
        expect(HomeContextRules.keep(saved, context, prefs, now)).assertTrue();
        prefs.tone = 'PLAYFUL';
        expect(HomeContextRules.keep(saved, context, prefs, now)).assertFalse();
      }
    });

    it('distinguishes unavailable schedules from a known empty day and focuses tomorrow', 0, () => {
      const now = new Date(2026, 10, 23, 8).getTime();
      const empty = new TtPlan();
      expect(HomeContextRules.course(empty, HomeTimetableState.Loading, now).status).assertEqual('正在读取课表');
      expect(HomeContextRules.course(empty, HomeTimetableState.Failed, now).status).assertEqual('课表读取失败');
      expect(HomeContextRules.course(empty, HomeTimetableState.Unconfigured, now).status).assertEqual('尚未配置课表');
      const snapshot = new TtSnapshot();
      snapshot.t = '2026-11-23';
      const course = new Course();
      course.day = 1;
      course.name = '测试课';
      snapshot.c = [course];
      const info = HomeContextRules.course(TtCalendar.plan(snapshot, now), HomeTimetableState.Ready, now);
      expect(info.status).assertEqual('今日无课');
      expect(info.action).assertEqual('查看明日课表');
      expect(new Date(info.focus?.time ?? 0).getDate()).assertEqual(24);
      expect(info.focus?.name ?? '').assertEqual('');
    });

    it('checks batch validity and source and avoids recent lines when English is off', 0, () => {
      const now = Date.parse('2026-11-27T03:00:00Z');
      const sample: HomePhraseBatch = {
        generatedAt: '2026-11-27T00:00:00Z', expiresAt: '2026-11-30T00:00:00Z',
        entries: [{ id: 'ai-0123456789abcdefabcdef01', topic: 'STUDY', tone: 'GENTLE',
          text: '试着画出两个概念之间的联系。', sourceTitle: 'Concept Mapping',
          sourceUrl: 'https://lsc.cornell.edu/how-to-study/concept-maps/' }]
      };
      expect(HomeContextRules.batch(JSON.stringify(sample), now) !== undefined).assertTrue();
      expect(HomeContextRules.batch(JSON.stringify(sample), now + 72 * 60 * 60 * 1000) === undefined).assertTrue();
      expect(HomeContextRules.validSource('https://lsc.cornell.edu.example.org/a')).assertFalse();
      const context = new HomePhraseContext(now, 'minhou', undefined, new HomeCourseContext());
      const prefs = new HomeAppearance();
      prefs.english = false;
      const history = new Map<string, number>();
      const previous = HomeContextRules.pick(HOME_LOCAL_PHRASES, context, prefs, history, now, 4);
      history.set(previous?.id ?? '', now);
      const next = HomeContextRules.pick(HOME_LOCAL_PHRASES, context, prefs, history, now, 4);
      expect(next?.id !== previous?.id).assertTrue();
      expect(next?.topic !== 'ENGLISH').assertTrue();
    });
  });
}

