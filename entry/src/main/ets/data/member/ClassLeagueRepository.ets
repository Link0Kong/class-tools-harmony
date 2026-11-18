import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import { LeagueMember } from './ClassMember';

const LEAGUE_PATH: string = 'rpc/class_league';
const DEFAULT_TTL_MS: number = 6 * 60 * 60 * 1000;

export class ClassLeagueResult {
  ok: boolean;
  members: LeagueMember[];
  fromCache: boolean;
  message: string;

  constructor(ok: boolean, members: LeagueMember[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.members = members;
    this.fromCache = fromCache;
    this.message = message;
  }

  static success(members: LeagueMember[], fromCache: boolean, message: string): ClassLeagueResult {
    return new ClassLeagueResult(true, members, fromCache, message);
  }

  static failure(message: string): ClassLeagueResult {
    return new ClassLeagueResult(false, [], false, message);
  }
}

/**
 * 团员名单仓库（名单三分类之「团员」）。
 *
 * 读取 `class_league` RPC（只读、**不返回学号**）；会话内缓存 TTL 6h；
 * 网络失败 → 有缓存返回缓存（fromCache=true + warning），否则 Failure；空名单视为有效空。
 */
export class ClassLeagueRepository {
  private api: Api;
  private sidProvider: () => string;
  private clock: () => number;
  private ttlMs: number;

  private cacheSid: string = '';
  private cache: LeagueMember[] = [];
  private loadedOnce: boolean = false;
  private lastFetchAt: number = 0;

  constructor(api: Api, sidProvider: () => string, clock: () => number = () => Date.now(),
    ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.sidProvider = sidProvider;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  async load(force: boolean): Promise<ClassLeagueResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length > 0 && sid !== this.cacheSid) {
      this.cacheSid = sid;
      this.cache = [];
      this.loadedOnce = false;
      this.lastFetchAt = 0;
    }
    const now: number = this.clock();
    if (!force && this.loadedOnce && now - this.lastFetchAt < this.ttlMs) {
      return ClassLeagueResult.success(this.cache, true, '');
    }
    const result: ApiResult = await this.api.post(LEAGUE_PATH, '{}', '', true);
    if (!result.ok) {
      const message: string = result.error !== undefined ? result.error.displayMessage() : '团员名单加载失败';
      if (this.loadedOnce) {
        return ClassLeagueResult.success(this.cache, true, message);
      }
      return ClassLeagueResult.failure(message);
    }
    const members: LeagueMember[] | undefined = parseLeague(result.value);
    if (members === undefined) {
      if (this.loadedOnce) {
        return ClassLeagueResult.success(this.cache, true, '团员名单格式异常');
      }
      return ClassLeagueResult.failure('团员名单格式异常');
    }
    this.cache = members;
    this.loadedOnce = true;
    this.lastFetchAt = now;
    return ClassLeagueResult.success(members, false, '');
  }

  async cached(): Promise<LeagueMember[]> {
    return this.cache;
  }

  async clear(): Promise<void> {
    this.cacheSid = '';
    this.cache = [];
    this.loadedOnce = false;
    this.lastFetchAt = 0;
  }
}

/** 解析 `class_league` 响应：`{ok,seats:[{seat,name}]}`；结构异常 → undefined。 */
export function parseLeague(raw: string): LeagueMember[] | undefined {
  if (raw.length === 0) {
    return undefined;
  }
  let parsed: JsonValue | undefined = undefined;
  try {
    parsed = JSON.parse(raw) as JsonValue;
  } catch (e) {
    return undefined;
  }
  let body: Blob | undefined = JsonBlob.asBlob(parsed);
  if (body === undefined) {
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array !== undefined && array.length > 0) {
      body = JsonBlob.asBlob(array[0]);
    }
  }
  if (body === undefined) {
    return undefined;
  }
  if (JsonBlob.asBoolean(JsonBlob.get(body, 'ok'), true) === false) {
    return undefined;
  }
  const seats: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(body, 'seats'));
  if (seats === undefined) {
    return [];
  }
  const out: LeagueMember[] = [];
  for (let i = 0; i < seats.length; i++) {
    const item: Blob | undefined = JsonBlob.asBlob(seats[i]);
    if (item === undefined) {
      continue;
    }
    const seat: number = JsonBlob.asNumber(JsonBlob.get(item, 'seat'), 0);
    const name: string = JsonBlob.asString(JsonBlob.get(item, 'name'), '').trim();
    if (seat <= 0 || name.length === 0) {
      continue;
    }
    out.push(new LeagueMember(Math.round(seat), name));
  }
  out.sort((a: LeagueMember, b: LeagueMember) => a.seat - b.seat);
  return out;
}
