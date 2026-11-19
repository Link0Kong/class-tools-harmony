import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { TtParser, TtSnapshot } from './TimetableModels';

const TT_PATH: string = 'site_assets?select=*&id=eq.tt';
const DEFAULT_TTL_MS: number = 6 * 60 * 60 * 1000;

export enum TtSource {
  PERSONAL = 'personal',
  PUBLIC = 'public',
  CACHE = 'cache'
}

export class TtResult {
  ok: boolean;
  snapshot: TtSnapshot | undefined = undefined;
  fromCache: boolean = false;
  source: TtSource = TtSource.PUBLIC;
  message: string = '';

  constructor(ok: boolean, snapshot: TtSnapshot | undefined, fromCache: boolean, source: TtSource, message: string) {
    this.ok = ok;
    this.snapshot = snapshot;
    this.fromCache = fromCache;
    this.source = source;
    this.message = message;
  }
}

/**
 * 课表仓库（契约 ENDPOINTS E24）：
 *
 * 1. 个人课表优先：`userdata.tt.ttUseMine === true` 且 `ttLocal` 有课程 → 直接用（PERSONAL）；
 * 2. 否则读公共快照 `site_assets?id=eq.tt`（body 可能是 jsonb 对象或 JSON 字符串）；
 * 3. 6 小时 TTL；网络失败回落缓存。
 */
export class TimetableRepository {
  private api: Api;
  private clock: () => number;
  private ttlMs: number;
  private personalProvider: () => Blob | undefined;

  private cache: TtSnapshot | undefined = undefined;
  private cachedAt: number = 0;
  private loaded: boolean = false;
  /** 并发合并：工作台与通知扫描同时刷新时只保留一个请求。 */
  private inflight: Promise<TtResult> | undefined = undefined;

  constructor(api: Api, personalProvider: () => Blob | undefined = () => undefined,
    clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.personalProvider = personalProvider;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  async load(force: boolean): Promise<TtResult> {
    if (this.inflight !== undefined) {
      return await this.inflight;
    }
    const pending: Promise<TtResult> = this.loadOnce(force);
    this.inflight = pending;
    try {
      return await pending;
    } finally {
      if (this.inflight === pending) {
        this.inflight = undefined;
      }
    }
  }

  private async loadOnce(force: boolean): Promise<TtResult> {
    const now: number = this.clock();
    const personal: TtSnapshot | undefined = this.personalSnapshot();
    if (personal !== undefined && personal.c.length > 0) {
      return new TtResult(true, personal, true, TtSource.PERSONAL, '');
    }
    if (!force && this.loaded && now - this.cachedAt < this.ttlMs && this.cache !== undefined) {
      return new TtResult(true, this.cache, true, TtSource.CACHE, '');
    }
    const result: ApiResult = await this.api.get(TT_PATH, true);
    if (!result.ok) {
      if (this.cache !== undefined) {
        return new TtResult(true, this.cache, true, TtSource.CACHE,
          result.error !== undefined ? result.error.displayMessage() : '课表加载失败');
      }
      return new TtResult(false, undefined, false, TtSource.PUBLIC,
        result.error !== undefined ? result.error.displayMessage() : '课表加载失败');
    }
    const snapshot: TtSnapshot | undefined = TimetableRepository.parseSiteAsset(result.value);
    if (snapshot === undefined || snapshot.c.length === 0) {
      if (this.cache !== undefined) {
        return new TtResult(true, this.cache, true, TtSource.CACHE, '课表为空');
      }
      return new TtResult(false, undefined, false, TtSource.PUBLIC, '暂无课表数据');
    }
    this.cache = snapshot;
    this.cachedAt = now;
    this.loaded = true;
    return new TtResult(true, snapshot, false, TtSource.PUBLIC, '');
  }

  local(): TtSnapshot | undefined {
    return this.cache;
  }

  /** `site_assets` 响应（数组，取第一行 body）。 */
  static parseSiteAsset(raw: string): TtSnapshot | undefined {
    if (raw.trim().length === 0) {
      return undefined;
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (e) {
      return undefined;
    }
    const rows: Object[] | undefined = JsonBlob.asArray(parsed);
    if (rows === undefined || rows.length === 0) {
      return undefined;
    }
    const row: Blob | undefined = JsonBlob.asBlob(rows[0]);
    if (row === undefined) {
      return undefined;
    }
    const body: string = TtParser.bodyOf(row);
    return TtParser.parseSnapshot(body);
  }

  /** 个人课表（`userdata.tt` 的 ttUseMine + ttLocal）。 */
  private personalSnapshot(): TtSnapshot | undefined {
    const tt: Blob | undefined = this.personalProvider();
    if (tt === undefined) {
      return undefined;
    }
    if (!JsonBlob.asBoolean(JsonBlob.get(tt, 'ttUseMine'), false)) {
      return undefined;
    }
    const local = JsonBlob.get(tt, 'ttLocal');
    if (local === null || local === undefined) {
      return undefined;
    }
    const text: string = typeof local === 'string' ? local as string : JSON.stringify(local);
    return TtParser.parseSnapshot(text);
  }
}
