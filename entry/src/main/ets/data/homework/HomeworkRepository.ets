import { fileIo as fs } from '@kit.CoreFileKit';
import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { HomeworkRow } from './HomeworkModels';

const HOMEWORK_PATH: string = 'homework?select=*&order=ts.asc&archived=eq.false';
const DEFAULT_TTL_MS: number = 10 * 60 * 1000;

export class HomeworkResult {
  ok: boolean;
  rows: HomeworkRow[];
  fromCache: boolean;
  message: string;

  constructor(ok: boolean, rows: HomeworkRow[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.rows = rows;
    this.fromCache = fromCache;
    this.message = message;
  }
}

/**
 * 作业仓库（只读）：`GET homework?select=*&order=ts.asc&archived=eq.false`（TTL 10 分钟）。
 * 完成状态不在本表，由 `marks`（kind='hw'）提供。
 */
export class HomeworkRepository {
  private api: Api;
  private clock: () => number;
  private ttlMs: number;

  private cache: HomeworkRow[] = [];
  private cachedAt: number = 0;
  private loaded: boolean = false;
  private hydrated: boolean = false;
  private generation: number = 0;
  private cacheFile: string;
  /** 并发合并：同一时刻只发一个请求（工作台与通知扫描会同时触发）。 */
  private inflight: Promise<HomeworkResult> | undefined = undefined;

  constructor(api: Api, clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS, cacheFile: string = '') {
    this.cacheFile = cacheFile;
    this.api = api;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  async load(force: boolean): Promise<HomeworkResult> {
    if (this.inflight !== undefined) {
      return await this.inflight;
    }
    const pending: Promise<HomeworkResult> = this.loadOnce(force);
    this.inflight = pending;
    try {
      return await pending;
    } finally {
      if (this.inflight === pending) {
        this.inflight = undefined;
      }
    }
  }

  private async loadOnce(force: boolean): Promise<HomeworkResult> {
    this.local();
    const generation = this.generation;
    const now: number = this.clock();
    if (!force && this.loaded && now - this.cachedAt < this.ttlMs) {
      return new HomeworkResult(true, this.cache, true, '');
    }
    const result: ApiResult = await this.api.get(HOMEWORK_PATH, true);
    if (generation !== this.generation) return new HomeworkResult(false, [], false, '账号已切换');
    if (!result.ok) {
      if (this.loaded) {
        return new HomeworkResult(true, this.cache, true,
          result.error !== undefined ? result.error.displayMessage() : '作业加载失败');
      }
      return new HomeworkResult(false, [], false,
        result.error !== undefined ? result.error.displayMessage() : '作业加载失败');
    }
    const rows = HomeworkRepository.decodeRows(result.value);
    // Invalid gateway responses must not erase the last readable offline copy.
    if (rows === undefined) {
      return new HomeworkResult(this.loaded, this.cache, this.loaded, '班级作业数据格式异常');
    }
    if (this.cacheFile) {
      try {
        const temp = this.cacheFile + '.tmp';
        const handle = fs.openSync(temp, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try { fs.writeSync(handle.fd, result.value); } finally { fs.closeSync(handle); }
        fs.renameSync(temp, this.cacheFile);
      } catch (_) { /* Full storage does not interrupt a successful refresh. */ }
    }
    this.cache = rows;
    this.cachedAt = now;
    this.loaded = true;
    return new HomeworkResult(true, rows, false, '');
  }

  clearLocal(): void {
    this.generation++;
    this.cache = [];
    this.loaded = false;
    this.hydrated = true;
    this.cachedAt = 0;
    if (!this.cacheFile) return;
    for (const path of [this.cacheFile, this.cacheFile + '.tmp']) {
      try { if (fs.accessSync(path)) fs.unlinkSync(path); } catch (_) {}
    }
  }

  local(): HomeworkRow[] {
    if (!this.hydrated && this.cacheFile) {
      this.hydrated = true;
      try {
        if (fs.accessSync(this.cacheFile)) {
          this.cache = HomeworkRepository.parseRows(fs.readTextSync(this.cacheFile));
          this.loaded = true;
        }
      } catch (_) {}
    }
    return this.cache;
  }

  static parseRows(raw: string): HomeworkRow[] {
    return HomeworkRepository.decodeRows(raw) ?? [];
  }

  private static decodeRows(raw: string): HomeworkRow[] | undefined {
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
    const out: HomeworkRow[] = [];
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj === undefined) {
        continue;
      }
      const id: string = JsonBlob.asString(JsonBlob.get(obj, 'id'), '').trim();
      if (id.length === 0) {
        continue;
      }
      const row: HomeworkRow = new HomeworkRow();
      row.id = id;
      row.subject = JsonBlob.asString(JsonBlob.get(obj, 'subject'), '');
      row.content = JsonBlob.asString(JsonBlob.get(obj, 'content'), '');
      row.due = JsonBlob.asString(JsonBlob.get(obj, 'due'), '');
      row.date = JsonBlob.asString(JsonBlob.get(obj, 'date'), '');
      row.time = JsonBlob.asString(JsonBlob.get(obj, 'time'), '');
      row.author = JsonBlob.asString(JsonBlob.get(obj, 'author'), '');
      row.owner = JsonBlob.asString(JsonBlob.get(obj, 'owner'), '');
      row.attachments = JsonBlob.asString(JsonBlob.get(obj, 'attachments'), '');
      row.archived = JsonBlob.asBoolean(JsonBlob.get(obj, 'archived'), false);
      row.ts = JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0);
      out.push(row);
    }
    return out;
  }
}
