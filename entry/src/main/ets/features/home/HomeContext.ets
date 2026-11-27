import { SessionInfo, SessionState, TodayState, TtPeriods, TtPlan } from '../../data/timetable/TimetableModels';
import { TimetableFocus } from '../../data/timetable/TimetableFocus';

export const HOME_WEATHER_INTERVAL: number = 15 * 60 * 1000;
const WEATHER_FRESHNESS: number = 45 * 60 * 1000;
const CONTENT_LIFETIME: number = 72 * 60 * 60 * 1000;
const RECENT_WINDOW: number = 7 * 24 * 60 * 60 * 1000;
const DAY: number = 24 * 60 * 60 * 1000;
const CHINA_OFFSET: number = 8 * 60 * 60 * 1000;
const COURSE_TOPICS: string[] = ['UPCOMING', 'BREAK', 'ONGOING', 'ENDED', 'NO_CLASS'];
const WEATHER_TOPICS: string[] = ['CLEAR_DAY', 'CLEAR_NIGHT', 'CLOUD', 'RAIN', 'HEAT', 'COOLING'];
const WEATHER_CHANGES: string[] = ['RAIN', 'HEAT', 'COOLING'];
const SEVERE: number[] = [301, 302, 303, 304, 307, 308, 310, 311, 312, 313, 315, 316, 317,
  318, 402, 403, 410, 507, 508, 514, 515];

export class HomeRegion {
  id: string;
  label: string;
  parent: string;

  constructor(id: string, label: string, parent: string = '') {
    this.id = id;
    this.label = label;
    this.parent = parent;
  }
}

export const HOME_DEFAULT_REGION: HomeRegion = new HomeRegion('minhou', '福州市闽侯县');

export class HomeAppearance {
  funContent: boolean = true;
  onlineContent: boolean = true;
  english: boolean = true;
  motion: boolean = true;
  tone: string = 'GENTLE';
  regionId: string = HOME_DEFAULT_REGION.id;

  static read(raw: string): HomeAppearance {
    const value = new HomeAppearance();
    try {
      const saved = JSON.parse(raw) as HomeAppearance;
      value.funContent = saved.funContent !== false;
      value.onlineContent = saved.onlineContent !== false;
      value.english = saved.english !== false;
      value.motion = saved.motion !== false;
      if (['SIMPLE', 'GENTLE', 'PLAYFUL'].indexOf(saved.tone) >= 0) value.tone = saved.tone;
      if (typeof saved.regionId === 'string' && /^[0-9]{1,12}$/.test(saved.regionId)) value.regionId = saved.regionId;
    } catch (_) {}
    return value;
  }
}

export interface HomePhrase {
  id: string;
  text: string;
  topic: string;
  tone: string;
  translation?: string;
  sourceTitle?: string;
  sourceUrl?: string;
}

export interface HomePhraseBatch {
  generatedAt: string;
  expiresAt: string;
  entries: HomePhrase[];
}

export interface HomeWeather {
  regionId: string;
  validTime: string;
  conditionCode: number;
  conditionText: string;
  temperatureC?: number | null;
  sunrise?: string;
  sunset?: string;
  cooling?: boolean;
  attributions?: string[];
}

export enum HomeAtmosphere {
  None, Rain, Sun, Night
}

export enum HomeTimetableState {
  Loading, Ready, Unconfigured, Failed
}

export class HomeCourseContext {
  status: string = '';
  topic: string = '';
  current?: SessionInfo;
  next?: SessionInfo;
  focus?: TimetableFocus;
  action: string = '';
  cached: boolean = false;

  get occurrence(): number {
    return (this.current ?? this.next)?.startAt ?? 0;
  }

  get urgent(): boolean {
    return ['ONGOING', 'BREAK', 'UPCOMING'].indexOf(this.topic) >= 0;
  }
}

export class HomePhraseContext {
  day: string;
  time: string;
  weather: string;
  regionId: string;
  importantWeather: boolean;
  course: HomeCourseContext;

  constructor(now: number, regionId: string, weather: HomeWeather | undefined, course: HomeCourseContext) {
    const date = new Date(now);
    const hour = date.getHours();
    this.day = date.getFullYear() + '-' + (date.getMonth() + 1) + '-' + date.getDate();
    this.time = hour >= 5 && hour < 9 ? 'MORNING'
      : hour >= 9 && hour < 18 ? 'DAY' : hour >= 18 && hour < 23 ? 'DUSK' : 'NIGHT';
    this.weather = weather === undefined ? '' : HomeContextRules.weatherTopic(weather, now);
    this.regionId = regionId;
    this.importantWeather = weather !== undefined && SEVERE.indexOf(weather.conditionCode) >= 0;
    this.course = course;
  }
}

export class HomeReading {
  phrase: HomePhrase;
  day: string;
  time: string;
  weather: string;
  regionId: string;
  course: string;
  occurrence: number;
  expiresAt: number;
  openedAt: number;

  constructor(phrase: HomePhrase, context: HomePhraseContext, expiresAt: number, openedAt: number = 0) {
    this.phrase = phrase;
    this.day = context.day;
    this.time = context.time;
    this.weather = context.weather;
    this.regionId = context.regionId;
    this.course = context.course.topic;
    this.occurrence = context.course.occurrence;
    this.expiresAt = expiresAt;
    this.openedAt = openedAt;
  }
}

export class HomeContextRules {
  static online(phrase: HomePhrase): boolean {
    return phrase.topic === 'EVERYDAY' || phrase.topic === 'STUDY';
  }

  static validSource(value: string | undefined): boolean {
    return typeof value === 'string' && value.length <= 1024 &&
      /^https:\/\/(?:[a-z0-9-]+\.)*(?:cas\.cn|nlc\.cn)(?::443)?\/[^\s\\]+$|^https:\/\/lsc\.cornell\.edu(?::443)?\/[^\s\\]+$/.test(value);
  }

  static batch(raw: string, now: number): HomePhraseBatch | undefined {
    try {
      const value = JSON.parse(raw) as HomePhraseBatch;
      const start = Date.parse(value.generatedAt);
      const end = Date.parse(value.expiresAt);
      if (!(start <= now && now < end && end - start <= CONTENT_LIFETIME) ||
        !Array.isArray(value.entries) || value.entries.length < 1 || value.entries.length > 12) return undefined;
      const ids = new Set<string>();
      for (const entry of value.entries) {
        if (!entry || !HomeContextRules.online(entry) || !/^ai-[a-f0-9]{24}$/.test(entry.id) ||
          typeof entry.text !== 'string' || entry.text.trim() !== entry.text ||
          entry.text.length < 8 || entry.text.length > 46 || /[\x00-\x1f\x7f]/.test(entry.text) ||
          ['SIMPLE', 'GENTLE', 'PLAYFUL'].indexOf(entry.tone) < 0 || entry.translation !== undefined ||
          typeof entry.sourceTitle !== 'string' || !entry.sourceTitle.trim() ||
          !HomeContextRules.validSource(entry.sourceUrl) || ids.has(entry.id)) return undefined;
        ids.add(entry.id);
      }
      return value;
    } catch (_) {
      return undefined;
    }
  }

  static validWeather(value: HomeWeather | undefined, regionId: string, now: number): boolean {
    if (!value || value.regionId !== regionId || typeof value.validTime !== 'string') return false;
    const time = Date.parse(value.validTime);
    const temperature = value.temperatureC;
    return time > 0 && time <= now && now - time < WEATHER_FRESHNESS &&
      Number.isInteger(value.conditionCode) && value.conditionCode >= 100 && value.conditionCode < 999 &&
      typeof value.conditionText === 'string' && value.conditionText.trim().length > 0 &&
      (temperature === null || temperature === undefined || (Number.isFinite(temperature) && temperature >= -90 && temperature <= 65));
  }

  static weatherTopic(weather: HomeWeather, now: number): string {
    const code = weather.conditionCode;
    if (SEVERE.indexOf(code) >= 0) return '';
    if ([300, 305, 306, 309, 314, 399].indexOf(code) >= 0) return 'RAIN';
    if (code === 900 || (weather.temperatureC ?? 0) >= 35) return 'HEAT';
    if (weather.cooling === true) return 'COOLING';
    if (code >= 101 && code <= 104) return 'CLOUD';
    return code === 100 ? HomeContextRules.daylightTopic(weather, now) : '';
  }

  private static daylightTopic(weather: HomeWeather, now: number): string {
    const rise = Date.parse(weather.sunrise ?? '');
    const set = Date.parse(weather.sunset ?? '');
    const day = Math.floor((now + CHINA_OFFSET) / DAY);
    if (!(rise < set) || Math.floor((rise + CHINA_OFFSET) / DAY) !== day ||
      Math.floor((set + CHINA_OFFSET) / DAY) !== day) return '';
    return now >= rise && now < set ? 'CLEAR_DAY' : 'CLEAR_NIGHT';
  }

  static atmosphere(weather: HomeWeather | undefined, context: HomePhraseContext, now: number): HomeAtmosphere {
    const code = weather?.conditionCode ?? 0;
    if ((code >= 300 && code <= 318) || code === 350 || code === 351 || code === 399) return HomeAtmosphere.Rain;
    if (context.importantWeather) return HomeAtmosphere.None;
    const night = context.time === 'DUSK' || context.time === 'NIGHT';
    if (code >= 150 && code <= 153) return HomeAtmosphere.Night;
    if (weather?.conditionCode === 100) {
      const daylight = HomeContextRules.daylightTopic(weather, now);
      if (daylight === 'CLEAR_DAY') return HomeAtmosphere.Sun;
      if (daylight === 'CLEAR_NIGHT') return HomeAtmosphere.Night;
      return night ? HomeAtmosphere.Night : HomeAtmosphere.Sun;
    }
    return night ? HomeAtmosphere.Night : HomeAtmosphere.None;
  }

  static publicationDay(now: number): number {
    return Math.floor((now + CHINA_OFFSET - 6 * 60 * 60 * 1000) / DAY);
  }

  static course(plan: TtPlan, state: HomeTimetableState, now: number): HomeCourseContext {
    const result = new HomeCourseContext();
    result.next = plan.next && plan.next.startAt > now ? plan.next : undefined;
    if (state === HomeTimetableState.Loading) {
      result.status = '正在读取课表';
      result.next = undefined;
      return result;
    }
    result.action = '打开课表';
    result.focus = new TimetableFocus(now);
    if (state === HomeTimetableState.Failed) {
      result.cached = plan.hasData;
      result.status = result.cached ? '课表待更新 · 缓存参考' : '课表读取失败';
      return result;
    }
    if (state === HomeTimetableState.Unconfigured || !plan.hasData) {
      result.status = '尚未配置课表';
      return result;
    }
    const current = plan.today.find((item: SessionInfo) => item.state === SessionState.ONGOING &&
      now >= item.startAt && now < item.endAt);
    result.current = current;
    const next = result.next;
    if (current) result.topic = 'ONGOING';
    else if (next && next.dayOffset === 0 && Math.ceil((next.startAt - now) / 60000) <= 10) {
      const previous = TtPeriods.endText(next.start - 1).split(':');
      const start = new Date(next.startAt);
      const lastBell = previous.length === 2
        ? new Date(start.getFullYear(), start.getMonth(), start.getDate(), Number(previous[0]), Number(previous[1])).getTime() : 0;
      result.topic = next.afterShortBreak && lastBell > 0 && now >= lastBell ? 'BREAK' : 'UPCOMING';
      result.status = result.topic === 'BREAK' ? '课间' : '即将上课';
    } else if (plan.todayState === TodayState.DONE) {
      result.topic = 'ENDED';
      result.status = '今日课程已结束';
    } else if (plan.todayState === TodayState.NONE && plan.week !== undefined) {
      result.topic = 'NO_CLASS';
      result.status = '今日无课';
    } else if (plan.week === undefined && plan.today.length === 0) {
      result.status = '学期尚未开始';
    }
    if (!current && next?.dayOffset === 1 && ['ENDED', 'NO_CLASS'].indexOf(result.topic) >= 0) {
      result.action = '查看明日课表';
      result.focus = new TimetableFocus(next.startAt);
    } else {
      const target = current ?? next;
      if (target) {
        result.action = '查看课程';
      result.focus = TimetableFocus.fromSession(target);
      }
    }
    return result;
  }

  private static allows(phrase: HomePhrase, context: HomePhraseContext, prefs: HomeAppearance): boolean {
    if (!prefs.funContent || phrase.tone !== prefs.tone) return false;
    if (phrase.topic === 'ENGLISH') return prefs.english && !context.course.urgent && !context.importantWeather;
    if (HomeContextRules.online(phrase)) return prefs.onlineContent && !context.course.urgent && !context.importantWeather;
    if (WEATHER_TOPICS.indexOf(phrase.topic) >= 0) return !context.importantWeather && phrase.topic === context.weather;
    if (COURSE_TOPICS.indexOf(phrase.topic) >= 0) return phrase.topic === context.course.topic;
    return phrase.topic === context.time || phrase.topic === 'GENERAL';
  }

  static keep(reading: HomeReading, context: HomePhraseContext, prefs: HomeAppearance, now: number): boolean {
    const phrase = reading.phrase;
    if (!HomeContextRules.allows(phrase, context, prefs)) return false;
    if (HomeContextRules.online(phrase) && !(reading.expiresAt > now && HomeContextRules.validSource(phrase.sourceUrl))) return false;
    if (WEATHER_TOPICS.indexOf(phrase.topic) >= 0 && reading.regionId !== context.regionId) return false;
    if (COURSE_TOPICS.indexOf(phrase.topic) >= 0 && reading.occurrence !== context.course.occurrence) return false;
    return reading.day === context.day && reading.time === context.time &&
      (!context.course.urgent || (reading.course === context.course.topic && reading.occurrence === context.course.occurrence)) &&
      (WEATHER_CHANGES.indexOf(context.weather) < 0 || (reading.weather === context.weather && reading.regionId === context.regionId));
  }

  static pick(pool: HomePhrase[], context: HomePhraseContext, prefs: HomeAppearance,
    seen: Map<string, number>, now: number, seed: number, excluding: string = '', manual: boolean = false): HomePhrase | undefined {
    const eligible = pool.filter((phrase: HomePhrase) => HomeContextRules.allows(phrase, context, prefs));
    const alternatives = eligible.filter((phrase: HomePhrase) => phrase.id !== excluding);
    let candidates = alternatives.length > 0 ? alternatives : eligible;
    const priority = context.course.urgent ? context.course.topic
      : !manual && WEATHER_CHANGES.indexOf(context.weather) >= 0 ? context.weather : '';
    const prioritized = candidates.filter((phrase: HomePhrase) => phrase.topic === priority);
    if (prioritized.length > 0) candidates = prioritized;
    if (!candidates.length) return undefined;
    const stamp = (phrase: HomePhrase): number => {
      const time = seen.get(phrase.id) ?? 0;
      return time <= now && now - time < RECENT_WINDOW ? time : 0;
    };
    const unseen = candidates.filter((phrase: HomePhrase) => stamp(phrase) === 0);
    if (unseen.length) candidates = unseen;
    const english = candidates.filter((phrase: HomePhrase) => phrase.topic === 'ENGLISH');
    const other = candidates.filter((phrase: HomePhrase) => phrase.topic !== 'ENGLISH');
    if (seed % 4 === 0 && english.length) candidates = english;
    else if (other.length) candidates = other;
    if (!unseen.length) {
      const oldest = Math.min(...candidates.map((phrase: HomePhrase) => stamp(phrase)));
      candidates = candidates.filter((phrase: HomePhrase) => stamp(phrase) === oldest);
    }
    return candidates[Math.abs(seed) % candidates.length];
  }
}

