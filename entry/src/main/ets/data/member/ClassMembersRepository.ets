import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import { ClassMember } from './ClassMember';
import { Log } from '../../common/Log';
import { AppGlobal } from '../../app/AppGlobal';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG: string = 'MembersRepo';
const MEMBERS_PATH: string = 'rpc/class_members';
const DEFAULT_TTL_MS: number = 6 * 60 * 60 * 1000;

export class ClassMembersResult {
  ok: boolean;
  members: ClassMember[];
  /** true = 来自本机缓存（TTL 内或网络失败时的降级）。 */
  fromCache: boolean;
  message: string;

  constructor(ok: boolean, members: ClassMember[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.members = members;
    this.fromCache = fromCache;
    this.message = message;
  }

  static success(members: ClassMember[], fromCache: boolean): ClassMembersResult {
    return new ClassMembersResult(true, members, fromCache, '');
  }

  static failure(message: string): ClassMembersResult {
    return new ClassMembersResult(false, [], false, message);
  }
}

export class MemberCacheEntry {
  members: ClassMember[] = [];
  savedAt: number = 0;

  constructor(members: ClassMember[], savedAt: number) {
    this.members = members;
    this.savedAt = savedAt;
  }
}

/** 班级名单落盘缓存（按 sid 隔离）。 */
export interface ClassMemberCache {
  read(sid: string): Promise<MemberCacheEntry | undefined>;

  write(sid: string, members: ClassMember[], savedAt: number): Promise<void>;

  clear(sid: string): Promise<void>;
}

export class InMemoryClassMemberCache implements ClassMemberCache {
  private data: Map<string, MemberCacheEntry> = new Map<string, MemberCacheEntry>();

  async read(sid: string): Promise<MemberCacheEntry | undefined> {
    return this.data.get(sid);
  }

  async write(sid: string, members: ClassMember[], savedAt: number): Promise<void> {
    this.data.set(sid, new MemberCacheEntry(members, savedAt));
  }

  async clear(sid: string): Promise<void> {
    this.data.delete(sid);
  }
}

interface MemberCacheFile {
  savedAt?: number;
  members?: Object[];
}

export class FileClassMemberCache implements ClassMemberCache {
  private directory: string = '';

  constructor(directory: string = '') {
    this.directory = directory;
  }

  private dir(): string {
    if (this.directory.length > 0) {
      return this.directory;
    }
    const ctx = AppGlobal.context;
    return ctx !== undefined ? ctx.filesDir + '/members' : '';
  }

  private pathFor(sid: string): string {
    const safe: string = sid.replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '');
    const dir: string = this.dir();
    return dir.length > 0 && safe.length > 0 ? dir + '/members_' + safe + '.json' : '';
  }

  async read(sid: string): Promise<MemberCacheEntry | undefined> {
    const path: string = this.pathFor(sid);
    if (path.length === 0) {
      return undefined;
    }
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      const text: string = fs.readTextSync(path);
      if (text.length === 0) {
        return undefined;
      }
      const file: MemberCacheFile = JSON.parse(text) as MemberCacheFile;
      const raw: Object[] = file.members !== undefined ? file.members : [];
      const members: ClassMember[] = [];
      for (let i = 0; i < raw.length; i++) {
        const blob: Blob | undefined = JsonBlob.asBlob(raw[i]);
        if (blob === undefined) {
          continue;
        }
        const member: ClassMember | undefined = ClassMember.fromJson(blob);
        if (member !== undefined) {
          members.push(member);
        }
      }
      const savedAt: number = file.savedAt !== undefined ? file.savedAt : 0;
      return new MemberCacheEntry(members, savedAt);
    } catch (e) {
      Log.w(TAG, '读取名单缓存失败');
      return undefined;
    }
  }

  async write(sid: string, members: ClassMember[], savedAt: number): Promise<void> {
    const path: string = this.pathFor(sid);
    const dir: string = this.dir();
    if (path.length === 0 || dir.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const raw: Object[] = [];
      for (let i = 0; i < members.length; i++) {
        raw.push(members[i].toJson());
      }
      const file: MemberCacheFile = { 'savedAt': savedAt, 'members': raw };
      const handle = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(handle.fd, JSON.stringify(file));
      fs.closeSync(handle);
    } catch (e) {
      Log.w(TAG, '写入名单缓存失败');
    }
  }

  async clear(sid: string): Promise<void> {
    const path: string = this.pathFor(sid);
    if (path.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      Log.w(TAG, '清除名单缓存失败');
    }
  }
}

/**
 * 班级名单仓库：`POST rpc/class_members`（body `{}`，带身份 token）。
 *
 * 缓存：内存 L1（按 sid 隔离）+ 落盘；TTL 6h。
 * 失败语义：网络失败/空数组 → **不覆盖旧缓存**，返回旧缓存并标记 fromCache。
 */
export class ClassMembersRepository {
  private api: Api;
  private cache: ClassMemberCache;
  private sidProvider: () => string;
  private clock: () => number;
  private ttlMs: number;

  private memorySid: string = '';
  private memoryMembers: ClassMember[] = [];
  private memorySavedAt: number = 0;

  constructor(api: Api, cache: ClassMemberCache, sidProvider: () => string,
    clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.cache = cache;
    this.sidProvider = sidProvider;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  async load(force: boolean): Promise<ClassMembersResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return ClassMembersResult.failure('请先完成身份验证');
    }
    const now: number = this.clock();
    if (!force && this.memorySid === sid && this.memoryMembers.length > 0
      && now - this.memorySavedAt < this.ttlMs) {
      return ClassMembersResult.success(this.memoryMembers, true);
    }

    let cached: ClassMember[] = [];
    let cachedAt: number = 0;
    if (this.memorySid === sid && this.memoryMembers.length > 0) {
      cached = this.memoryMembers;
      cachedAt = this.memorySavedAt;
    } else {
      const entry: MemberCacheEntry | undefined = await this.cache.read(sid);
      if (entry !== undefined) {
        cached = entry.members;
        cachedAt = entry.savedAt;
        this.memorySid = sid;
        this.memoryMembers = cached;
        this.memorySavedAt = cachedAt;
      }
    }
    if (!force && cached.length > 0 && now - cachedAt < this.ttlMs) {
      return ClassMembersResult.success(cached, true);
    }

    const result: ApiResult = await this.api.post(MEMBERS_PATH, '{}', '', true);
    if (!result.ok) {
      if (cached.length > 0) {
        return ClassMembersResult.success(cached, true);
      }
      const message: string = result.error !== undefined ? result.error.displayMessage() : '名单加载失败';
      return ClassMembersResult.failure(message);
    }
    const members: ClassMember[] = parseMembers(result.value);
    if (members.length === 0) {
      // 契约：空数组视为失败，保留旧缓存
      if (cached.length > 0) {
        return ClassMembersResult.success(cached, true);
      }
      return ClassMembersResult.failure('班级名单为空，请稍后重试');
    }
    this.memorySid = sid;
    this.memoryMembers = members;
    this.memorySavedAt = now;
    await this.cache.write(sid, members, now);
    return ClassMembersResult.success(members, false);
  }

  async searchSeats(query: string): Promise<number[]> {
    const sid: string = this.sidProvider();
    const text: string = query.trim();
    if (!sid || !text || Array.from(text).length > 128) return [];
    const body: Blob = { 'p_query': text };
    try {
      const result: ApiResult = await this.api.post('rpc/class_roster_search', JSON.stringify(body), '', true);
      if (!result.ok || this.sidProvider() !== sid) return [];
      const arr: Object[] = JsonBlob.asArray(JSON.parse(result.value) as JsonValue) ?? [];
      return arr.map((value: Object) => JsonBlob.asNumber(value, 0))
        .filter((seat: number) => Number.isInteger(seat) && seat > 0);
    } catch (_) {
      return [];
    }
  }

  /** 只读本机内存/文件缓存，不发请求。 */
  async cached(): Promise<ClassMember[]> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return [];
    }
    if (this.memorySid === sid && this.memoryMembers.length > 0) {
      return this.memoryMembers;
    }
    const entry: MemberCacheEntry | undefined = await this.cache.read(sid);
    if (entry === undefined) {
      return [];
    }
    this.memorySid = sid;
    this.memoryMembers = entry.members;
    this.memorySavedAt = entry.savedAt;
    return entry.members;
  }

  async clear(): Promise<void> {
    const sid: string = this.sidProvider().trim();
    this.memorySid = '';
    this.memoryMembers = [];
    this.memorySavedAt = 0;
    if (sid.length > 0) {
      await this.cache.clear(sid);
    }
  }
}

/** 解析 `class_members` 数组；坏行跳过。 */
export function parseMembers(raw: string): ClassMember[] {
  if (raw.length === 0) {
    return [];
  }
  let parsed: JsonValue | undefined = undefined;
  try {
    parsed = JSON.parse(raw) as JsonValue;
  } catch (e) {
    return [];
  }
  const array: Object[] | undefined = JsonBlob.asArray(parsed);
  if (array === undefined) {
    return [];
  }
  const out: ClassMember[] = [];
  for (let i = 0; i < array.length; i++) {
    const blob: Blob | undefined = JsonBlob.asBlob(array[i]);
    if (blob === undefined) {
      continue;
    }
    const member: ClassMember | undefined = ClassMember.fromJson(blob);
    if (member !== undefined) {
      out.push(member);
    }
  }
  return out;
}
