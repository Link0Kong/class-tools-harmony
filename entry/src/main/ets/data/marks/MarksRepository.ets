import { Api } from '../net/Api';
import { ApiError, ApiErrorKind, ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { MarkKind, MarkRow, MarksSnapshot } from './Marks';
import { AsyncLock } from '../../common/AsyncLock';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG: string = 'MarksRepo';
const MARKS_PATH: string = 'marks';
const UPSERT_PREFER: string = 'return=representation,resolution=merge-duplicates';
const DEFAULT_TTL_MS: number = 2 * 60 * 1000;

/** marks 本机缓存/待补发（接口化便于单测）。 */
export interface MarksLocalStore {
  readCache(): Promise<MarkRow[]>;

  writeCache(rows: MarkRow[]): Promise<void>;

  readPending(): Promise<MarkRow[]>;

  writePending(rows: MarkRow[]): Promise<void>;
}

export class InMemoryMarksLocalStore implements MarksLocalStore {
  private cache: MarkRow[] = [];
  private pending: MarkRow[] = [];

  async readCache(): Promise<MarkRow[]> {
    return this.cache;
  }

  async writeCache(rows: MarkRow[]): Promise<void> {
    this.cache = rows;
  }

  async readPending(): Promise<MarkRow[]> {
    return this.pending;
  }

  async writePending(rows: MarkRow[]): Promise<void> {
    this.pending = rows;
  }
}

interface MarksFileShape {
  cache?: Object[];
  pending?: Object[];
}

/** 文件实现：`<filesDir>/marks/marks_<sid>.json`。 */
export class FileMarksLocalStore implements MarksLocalStore {
  private sidProvider: () => string;
  private directory: string = '';

  constructor(sidProvider: () => string, directory: string = '') {
    this.sidProvider = sidProvider;
    this.directory = directory;
  }

  private dir(): string {
    if (this.directory.length > 0) {
      return this.directory;
    }
    const ctx = AppGlobal.context;
    return ctx !== undefined ? ctx.filesDir + '/marks' : '';
  }

  private path(): string {
    const sid: string = this.sidProvider().trim().replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '');
    const dir: string = this.dir();
    if (sid.length === 0 || dir.length === 0) {
      return '';
    }
    return dir + '/marks_' + sid + '.json';
  }

  private read(): MarksFileShape {
    const path: string = this.path();
    if (path.length === 0) {
      return {};
    }
    try {
      if (!fs.accessSync(path)) {
        return {};
      }
      const text: string = fs.readTextSync(path);
      return text.length > 0 ? JSON.parse(text) as MarksFileShape : {};
    } catch (e) {
      Log.w(TAG, '读取本机 marks 失败');
      return {};
    }
  }

  private write(shape: MarksFileShape): void {
    const path: string = this.path();
    const dir: string = this.dir();
    if (path.length === 0 || dir.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(shape));
      fs.closeSync(file);
    } catch (e) {
      Log.w(TAG, '写入本机 marks 失败');
    }
  }

  private rowsOf(raw: Object[] | undefined): MarkRow[] {
    const out: MarkRow[] = [];
    if (raw === undefined) {
      return out;
    }
    for (let i = 0; i < raw.length; i++) {
      const blob: Blob | undefined = JsonBlob.asBlob(raw[i]);
      if (blob === undefined) {
        continue;
      }
      const row: MarkRow | undefined = MarkRow.fromJson(blob);
      if (row !== undefined) {
        out.push(row);
      }
    }
    return out;
  }

  async readCache(): Promise<MarkRow[]> {
    return this.rowsOf(this.read().cache);
  }

  async writeCache(rows: MarkRow[]): Promise<void> {
    const shape: MarksFileShape = this.read();
    const raw: Object[] = [];
    for (let i = 0; i < rows.length; i++) {
      raw.push(rows[i].toJson());
    }
    shape.cache = raw;
    this.write(shape);
  }

  async readPending(): Promise<MarkRow[]> {
    return this.rowsOf(this.read().pending);
  }

  async writePending(rows: MarkRow[]): Promise<void> {
    const shape: MarksFileShape = this.read();
    const raw: Object[] = [];
    for (let i = 0; i < rows.length; i++) {
      raw.push(rows[i].toJson());
    }
    shape.pending = raw;
    this.write(shape);
  }
}

export class MarksUpdateResult {
  ok: boolean;
  error: ApiError | undefined;

  constructor(ok: boolean, error: ApiError | undefined) {
    this.ok = ok;
    this.error = error;
  }

  static success(): MarksUpdateResult {
    return new MarksUpdateResult(true, undefined);
  }

  static failure(error: ApiError): MarksUpdateResult {
    return new MarksUpdateResult(false, error);
  }
}

export class MarksRefreshResult {
  ok: boolean;
  snapshot: MarksSnapshot;
  error: ApiError | undefined;

  constructor(ok: boolean, snapshot: MarksSnapshot, error: ApiError | undefined) {
    this.ok = ok;
    this.snapshot = snapshot;
    this.error = error;
  }
}

/**
 * marks 仓库（契约 §5）：marks 是「作业完成 / 通知置顶 / 通知已处理」的跨端唯一真源。
 *
 * - 读：`GET marks?select=*&seat=eq.<sid>`，TTL 2 分钟；
 * - 写：`POST marks` + upsert（取消 = `val:false`，**不做 DELETE**）；
 * - 失败入本机 pending，下次刷新/补发；拉回后 pending 覆盖云端旧值。
 */
export class MarksRepository {
  private api: Api;
  private local: MarksLocalStore;
  private sidProvider: () => string;
  private clock: () => number;
  private ttlMs: number;

  private lock: AsyncLock = new AsyncLock();
  private snapshot: MarksSnapshot = new MarksSnapshot();
  private cacheLoaded: boolean = false;
  private lastFetchAt: number = 0;

  constructor(api: Api, sidProvider: () => string, local: MarksLocalStore = new InMemoryMarksLocalStore(),
    clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.sidProvider = sidProvider;
    this.local = local;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  marks(): MarksSnapshot {
    return this.snapshot;
  }

  async refresh(force: boolean): Promise<MarksRefreshResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return new MarksRefreshResult(false, this.snapshot,
        new ApiError(ApiErrorKind.Config, 0, 'no_session', '请先完成身份验证'));
    }
    return await this.lock.run<MarksRefreshResult>(async () => {
      await this.ensureCacheLoaded();
      if (!force && this.lastFetchAt > 0 && this.clock() - this.lastFetchAt < this.ttlMs) {
        return new MarksRefreshResult(true, this.snapshot, undefined);
      }
      const path: string = MARKS_PATH + '?select=*&seat=eq.' + encodeURIComponent(sid);
      const result: ApiResult = await this.api.get(path, true);
      if (!result.ok) {
        const err: ApiError = result.error !== undefined
          ? result.error
          : new ApiError(ApiErrorKind.Network, 0, 'network', '网络连接失败');
        return new MarksRefreshResult(false, this.snapshot, err);
      }
      const rows: MarkRow[] | undefined = parseRows(result.value);
      if (rows === undefined) {
        return new MarksRefreshResult(false, this.snapshot,
          new ApiError(ApiErrorKind.Parse, 0, 'parse', 'marks 响应不是合法数组'));
      }
      await this.local.writeCache(rows);
      this.lastFetchAt = this.clock();
      const pending: MarkRow[] = await this.local.readPending();
      const next: MarksSnapshot = new MarksSnapshot().replaceRows(rows).applyPending(pending);
      this.snapshot = next;
      return new MarksRefreshResult(true, next, undefined);
    });
  }

  async setMark(kind: MarkKind, ref: string, value: boolean): Promise<MarksUpdateResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return MarksUpdateResult.failure(new ApiError(ApiErrorKind.Config, 0, 'no_session', '请先完成身份验证'));
    }
    if (ref.trim().length === 0) {
      return MarksUpdateResult.failure(new ApiError(ApiErrorKind.Config, 0, 'empty_ref', 'ref 为空'));
    }
    return await this.lock.run<MarksUpdateResult>(async () => {
      await this.ensureCacheLoaded();
      const row: MarkRow = new MarkRow(MarkRow.idOf(sid, kind, ref), sid, kind, ref, value, this.clock());
      // 先本地乐观更新（UI 立即生效；失败也有本机状态）
      this.snapshot = this.snapshot.with(kind, ref, value);
      const cache: MarkRow[] = await this.local.readCache();
      const kept: MarkRow[] = [];
      for (let i = 0; i < cache.length; i++) {
        if (cache[i].id !== row.id) {
          kept.push(cache[i]);
        }
      }
      kept.push(row);
      await this.local.writeCache(kept);

      const rows: Object[] = [row.toJson()];
      const result: ApiResult = await this.api.post(MARKS_PATH, JSON.stringify(rows), UPSERT_PREFER, true);
      if (!result.ok) {
        const pending: MarkRow[] = await this.local.readPending();
        const nextPending: MarkRow[] = [];
        for (let i = 0; i < pending.length; i++) {
          if (pending[i].id !== row.id) {
            nextPending.push(pending[i]);
          }
        }
        nextPending.push(row);
        await this.local.writePending(nextPending);
        const err: ApiError = result.error !== undefined
          ? result.error
          : new ApiError(ApiErrorKind.Network, 0, 'network', '网络连接失败');
        return MarksUpdateResult.failure(err);
      }
      const pending: MarkRow[] = await this.local.readPending();
      const nextPending: MarkRow[] = [];
      for (let i = 0; i < pending.length; i++) {
        if (pending[i].id !== row.id) {
          nextPending.push(pending[i]);
        }
      }
      await this.local.writePending(nextPending);
      return MarksUpdateResult.success();
    });
  }

  /** 补发本机失败写入；返回成功条数。 */
  async flushPending(): Promise<number> {
    return await this.lock.run<number>(async () => {
      const pending: MarkRow[] = await this.local.readPending();
      if (pending.length === 0) {
        return 0;
      }
      let success: number = 0;
      const remaining: MarkRow[] = [];
      for (let i = 0; i < pending.length; i++) {
        const row: MarkRow = pending[i];
        const result: ApiResult = await this.api.post(MARKS_PATH, JSON.stringify([row.toJson()]), UPSERT_PREFER, true);
        if (result.ok) {
          success += 1;
        } else {
          remaining.push(row);
        }
      }
      await this.local.writePending(remaining);
      if (success > 0) {
        this.lastFetchAt = 0;
      }
      return success;
    });
  }

  async pendingCount(): Promise<number> {
    const pending: MarkRow[] = await this.local.readPending();
    return pending.length;
  }

  private async ensureCacheLoaded(): Promise<void> {
    if (this.cacheLoaded) {
      return;
    }
    this.cacheLoaded = true;
    const cached: MarkRow[] = await this.local.readCache();
    if (cached.length > 0) {
      this.snapshot = new MarksSnapshot().replaceRows(cached);
    }
    const pending: MarkRow[] = await this.local.readPending();
    if (pending.length > 0) {
      this.snapshot = this.snapshot.applyPending(pending);
    }
  }
}

/** 解析 `GET marks` 数组；不是数组 → undefined（调用方按 Parse 错误处理）。 */
export function parseRows(raw: string): MarkRow[] | undefined {
  if (raw.length === 0) {
    return undefined;
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return undefined;
  }
  const array: Object[] | undefined = JsonBlob.asArray(parsed);
  if (array === undefined) {
    return undefined;
  }
  const rows: MarkRow[] = [];
  for (let i = 0; i < array.length; i++) {
    const blob: Blob | undefined = JsonBlob.asBlob(array[i]);
    if (blob === undefined) {
      continue;
    }
    const row: MarkRow | undefined = MarkRow.fromJson(blob);
    if (row !== undefined && row.ref.trim().length > 0) {
      rows.push(row);
    }
  }
  return rows;
}
