import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { AppGlobal } from '../../app/AppGlobal';
import { HOME_DEFAULT_REGION, HOME_WEATHER_INTERVAL, HomeAppearance, HomeContextRules, HomePhraseBatch,
  HomeReading, HomeRegion, HomeWeather } from '../../features/home/HomeContext';

const ENDPOINT: string = 'https://tool.furina.fun/home-context';
const PREF_NAME: string = 'ct_home_context_v1';
const MAX_BODY: number = 64 * 1024;
const CONTENT_RETRY: number = 60 * 60 * 1000;
const HISTORY_LIMIT: number = 96;
const HISTORY_AGE: number = 7 * 24 * 60 * 60 * 1000;

interface WeatherAttempt {
  time: number;
  value?: HomeWeather;
}

interface SeenEntry {
  id: string;
  time: number;
}

interface ReadingRecord {
  reading: HomeReading;
  seen: SeenEntry[];
}

export class HomeContextRepository {
  private static regionsCache?: HomeRegion[];
  private static weatherCache = new Map<string, WeatherAttempt>();
  private static weatherRequests = new Map<string, Promise<HomeWeather | undefined>>();
  private static batch: HomePhraseBatch | undefined = undefined;
  private static contentRequest: Promise<HomePhraseBatch | undefined> | undefined = undefined;
  private static lastContentAttempt: number = 0;
  private static loadedBatch: boolean = false;
  private static appearance = new Map<string, HomeAppearance>();
  private static writes: Promise<void> = Promise.resolve();

  static regions(): HomeRegion[] {
    if (HomeContextRepository.regionsCache) return HomeContextRepository.regionsCache;
    const list: HomeRegion[] = [HOME_DEFAULT_REGION];
    try {
      const bytes = AppGlobal.context?.resourceManager.getRawFileContentSync('home_regions.tsv');
      if (bytes) {
        const raw = util.TextDecoder.create('utf-8').decodeToString(bytes);
        for (const line of raw.split('\n')) {
          const fields = line.split('\t');
          if (fields.length === 5 && /^[0-9]{1,12}$/.test(fields[0])) {
            const label = fields[2].length ? fields[2] + ' · ' + fields[1] : fields[1];
            list.push(new HomeRegion(fields[0], label, fields[2]));
          }
        }
      }
    } catch (_) {}
    if (AppGlobal.context) HomeContextRepository.regionsCache = list;
    return list;
  }

  static region(id: string): HomeRegion {
    if (id === HOME_DEFAULT_REGION.id) return HOME_DEFAULT_REGION;
    return HomeContextRepository.regions().find((region: HomeRegion) => region.id === id) ?? HOME_DEFAULT_REGION;
  }

  private static async store(): Promise<preferences.Preferences | undefined> {
    try {
      const context = AppGlobal.context;
      if (context) return await preferences.getPreferences(context, { name: PREF_NAME });
    } catch (_) {}
    return undefined;
  }

  private static async get(key: string): Promise<string> {
    try {
      await HomeContextRepository.writes;
      const store = await HomeContextRepository.store();
      if (store) return await store.get(key, '') as string;
    } catch (_) {}
    return '';
  }

  private static put(key: string, value: string): Promise<void> {
    const next = HomeContextRepository.writes.then(async () => {
      try {
        const store = await HomeContextRepository.store();
        if (store) {
          await store.put(key, value);
          await store.flush();
        }
      } catch (_) {}
    });
    HomeContextRepository.writes = next;
    return next;
  }

  static async settings(sid: string): Promise<HomeAppearance> {
    if (sid.length === 0) return new HomeAppearance();
    const cached = HomeContextRepository.appearance.get(sid);
    if (cached) return HomeAppearance.read(JSON.stringify(cached));
    const value = HomeAppearance.read(await HomeContextRepository.get('settings_' + sid));
    return HomeAppearance.read(JSON.stringify(HomeContextRepository.appearance.get(sid) ?? value));
  }

  static async saveSettings(sid: string, value: HomeAppearance): Promise<void> {
    if (!sid.length) return;
    const raw = JSON.stringify(value);
    HomeContextRepository.appearance.set(sid, HomeAppearance.read(raw));
    const revision = AppStorage.get<number>('homeContentRevision') ?? 0;
    AppStorage.setOrCreate<number>('homeContentRevision', revision + 1);
    await HomeContextRepository.put('settings_' + sid, raw);
  }

  static async readHistory(sid: string, now: number): Promise<Map<string, number>> {
    const history = new Map<string, number>();
    if (!sid.length) return history;
    try {
      const raw = await HomeContextRepository.get('reading_' + sid);
      const record = JSON.parse(raw) as ReadingRecord;
      for (const item of record.seen) {
        if (typeof item.id === 'string' && item.time <= now && now - item.time < HISTORY_AGE) {
          history.set(item.id, item.time);
        }
      }
    } catch (_) {}
    return history;
  }

  static async remember(sid: string, reading: HomeReading, history: Map<string, number>): Promise<void> {
    if (!sid.length) return;
    const entries: SeenEntry[] = [];
    history.forEach((time: number, id: string) => {
      entries.push({ id: id, time: time });
    });
    entries.sort((first: SeenEntry, second: SeenEntry) => first.time - second.time);
    const record: ReadingRecord = { reading: reading, seen: entries.slice(-HISTORY_LIMIT) };
    await HomeContextRepository.put('reading_' + sid, JSON.stringify(record));
  }

  static async reading(sid: string): Promise<HomeReading | undefined> {
    if (!sid.length) return undefined;
    try {
      const record = JSON.parse(await HomeContextRepository.get('reading_' + sid)) as ReadingRecord;
      const value = record.reading;
      if (value && value.phrase && typeof value.phrase.id === 'string' &&
        typeof value.phrase.text === 'string' && typeof value.day === 'string') return value;
    } catch (_) {}
    return undefined;
  }

  static cachedWeather(regionId: string, now: number): HomeWeather | undefined {
    const value = HomeContextRepository.weatherCache.get(regionId)?.value;
    return HomeContextRules.validWeather(value, regionId, now) ? value : undefined;
  }

  static async weather(regionId: string, now: number): Promise<HomeWeather | undefined> {
    const previous = HomeContextRepository.weatherCache.get(regionId);
    if (previous && now >= previous.time && now - previous.time < HOME_WEATHER_INTERVAL) {
      return HomeContextRepository.cachedWeather(regionId, now);
    }
    const pending = HomeContextRepository.weatherRequests.get(regionId);
    if (pending) return await pending;
    const request = HomeContextRepository.fetchWeather(regionId, now);
    HomeContextRepository.weatherRequests.set(regionId, request);
    try {
      return await request;
    } finally {
      HomeContextRepository.weatherRequests.delete(regionId);
    }
  }

  private static async fetchWeather(regionId: string, now: number): Promise<HomeWeather | undefined> {
    let fresh: HomeWeather | undefined;
    const raw = await HomeContextRepository.httpGet('/weather/v1?region=' + encodeURIComponent(regionId));
    try {
      const value = JSON.parse(raw) as HomeWeather;
      if (HomeContextRules.validWeather(value, regionId, Date.now())) fresh = value;
    } catch (_) {}
    HomeContextRepository.weatherCache.delete(regionId);
    HomeContextRepository.weatherCache.set(regionId, { time: now, value: fresh });
    if (HomeContextRepository.weatherCache.size > 32) {
      const oldest = HomeContextRepository.weatherCache.keys().next();
      if (!oldest.done) HomeContextRepository.weatherCache.delete(oldest.value);
    }
    return fresh;
  }

  static async cachedContent(now: number): Promise<HomePhraseBatch | undefined> {
    if (!HomeContextRepository.loadedBatch) {
      const raw = await HomeContextRepository.get('public_batch');
      if (!HomeContextRepository.loadedBatch) {
        HomeContextRepository.batch = HomeContextRules.batch(raw, now);
        HomeContextRepository.loadedBatch = true;
      }
    }
    const current = HomeContextRepository.batch;
    return current && Date.parse(current.generatedAt) <= now && Date.parse(current.expiresAt) > now ? current : undefined;
  }

  static async content(now: number): Promise<HomePhraseBatch | undefined> {
    const current = await HomeContextRepository.cachedContent(now);
    const pending = HomeContextRepository.contentRequest;
    if (pending) return await pending;
    if ((current && HomeContextRules.publicationDay(Date.parse(current.generatedAt)) >= HomeContextRules.publicationDay(now)) ||
      (now >= HomeContextRepository.lastContentAttempt && now - HomeContextRepository.lastContentAttempt < CONTENT_RETRY)) {
      return current;
    }
    HomeContextRepository.lastContentAttempt = now;
    const request = HomeContextRepository.fetchContent(current);
    HomeContextRepository.contentRequest = request;
    try {
      return await request;
    } finally {
      HomeContextRepository.contentRequest = undefined;
    }
  }

  private static async fetchContent(current: HomePhraseBatch | undefined): Promise<HomePhraseBatch | undefined> {
    const raw = await HomeContextRepository.httpGet('/content/v1');
    const incoming = HomeContextRules.batch(raw, Date.now());
    if (incoming && (!current || Date.parse(incoming.generatedAt) > Date.parse(current.generatedAt))) {
      HomeContextRepository.batch = incoming;
      await HomeContextRepository.put('public_batch', raw);
      return incoming;
    }
    return current;
  }

  private static async httpGet(path: string): Promise<string> {
    const client = http.createHttp();
    try {
      const result = await client.request(ENDPOINT + path, {
        method: http.RequestMethod.GET, connectTimeout: 4000, readTimeout: 8000, usingCache: false,
        expectDataType: http.HttpDataType.STRING, maxLimit: MAX_BODY, header: { 'Accept': 'application/json' }
      });
      return result.responseCode === 200 && typeof result.result === 'string' && result.result.length <= MAX_BODY
        ? result.result : '';
    } catch (_) {
      return '';
    } finally {
      client.destroy();
    }
  }
}

