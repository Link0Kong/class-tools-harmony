import { Api } from '../net/Api';
import { ApiError, ApiErrorKind, ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { FitCodec } from '../../features/fit/FitCodec';
import { FitRecord } from '../../features/fit/FitModels';
import { AsyncLock } from '../../common/AsyncLock';

const FITRECS_PATH: string = 'fitrecs';
const UPSERT_PREFER: string = 'return=representation,resolution=merge-duplicates';
const DEFAULT_TTL_MS: number = 2 * 60 * 1000;

export class FitRecsResult {
  ok: boolean;
  records: FitRecord[];
  fromCache: boolean;
  message: string;

  constructor(ok: boolean, records: FitRecord[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.records = records;
    this.fromCache = fromCache;
    this.message = message;
  }
}

export class FitRecsWriteResult {
  ok: boolean;
  error: ApiError | undefined;

  constructor(ok: boolean, error: ApiError | undefined) {
    this.ok = ok;
    this.error = error;
  }
}

/**
 * 体测历史仓库（`fitrecs`，契约 ENDPOINTS E14/E15/E16）。
 *
 * - 读：`GET fitrecs?select=*&acc=eq.<sid>&arch=eq.false&order=ts.desc`，TTL 2min；
 * - 写：`POST fitrecs` + upsert（按 id）；取消不 DELETE，`PATCH fitrecs?id=eq.<id>` `{arch:true}` 软删；
 * - 最多保留 2 条（由调用方把 dropped 记录 archive）。
 */
export class FitRecsRepository {
  private api: Api;
  private sidProvider: () => string;
  private clock: () => number;
  private ttlMs: number;

  private lock: AsyncLock = new AsyncLock();
  private cache: FitRecord[] = [];
  private cachedAt: number = 0;
  private loaded: boolean = false;

  constructor(api: Api, sidProvider: () => string, clock: () => number = () => Date.now(),
    ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.sidProvider = sidProvider;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  async refresh(force: boolean): Promise<FitRecsResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return new FitRecsResult(false, [], false, '请先完成身份验证');
    }
    const now: number = this.clock();
    if (!force && this.loaded && now - this.cachedAt < this.ttlMs) {
      return new FitRecsResult(true, this.cache, true, '');
    }
    const path: string = FITRECS_PATH + '?select=*&acc=eq.' + encodeURIComponent(sid)
      + '&arch=eq.false&order=ts.desc';
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      if (this.loaded) {
        const message: string = result.error !== undefined ? result.error.displayMessage() : '历史加载失败';
        return new FitRecsResult(true, this.cache, true, message);
      }
      return new FitRecsResult(false, [], false,
        result.error !== undefined ? result.error.displayMessage() : '历史加载失败');
    }
    const records: FitRecord[] = FitRecsRepository.parseRows(result.value);
    this.cache = records.slice(0, FitRecord.MAX_RECORDS);
    this.cachedAt = now;
    this.loaded = true;
    return new FitRecsResult(true, this.cache, false, '');
  }

  async save(record: FitRecord): Promise<FitRecsWriteResult> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0) {
      return new FitRecsWriteResult(false, new ApiError(ApiErrorKind.Config, 0, 'no_session', '请先完成身份验证'));
    }
    return await this.lock.run<FitRecsWriteResult>(async () => {
      const row: Blob = FitCodec.rowForUpload(record, sid);
      const rows: Object[] = [row];
      const result: ApiResult = await this.api.post(FITRECS_PATH, JSON.stringify(rows), UPSERT_PREFER, true);
      if (!result.ok) {
        return new FitRecsWriteResult(false, result.error);
      }
      return new FitRecsWriteResult(true, undefined);
    });
  }

  /** 软删（arch=true），不发 DELETE。 */
  async archive(id: string): Promise<FitRecsWriteResult> {
    if (id.trim().length === 0) {
      return new FitRecsWriteResult(true, undefined);
    }
    const path: string = FITRECS_PATH + '?id=eq.' + encodeURIComponent(id);
    const body: Blob = { 'arch': true };
    const result: ApiResult = await this.api.patch(path, JSON.stringify(body), '', true);
    if (!result.ok) {
      return new FitRecsWriteResult(false, result.error);
    }
    return new FitRecsWriteResult(true, undefined);
  }

  /** 改名：fitrecs 行只有 data 列，重写 data.n（成绩/时间不变）。 */
  async rename(record: FitRecord, name: string): Promise<FitRecsWriteResult> {
    const trimmed: string = name.trim();
    if (record.id.trim().length === 0 || trimmed.length === 0) {
      return new FitRecsWriteResult(true, undefined);
    }
    const copy: FitRecord = new FitRecord();
    copy.id = record.id;
    copy.ts = record.ts;
    copy.name = trimmed;
    copy.sex = record.sex;
    copy.gradeBucket = record.gradeBucket;
    copy.fields = record.fields;
    copy.total = record.total;
    copy.grade = record.grade;
    copy.syncPending = record.syncPending;
    const path: string = FITRECS_PATH + '?id=eq.' + encodeURIComponent(record.id);
    const body: Blob = { 'data': FitCodec.recordToData(copy), 'ts': record.ts };
    const result: ApiResult = await this.api.patch(path, JSON.stringify(body), '', true);
    if (!result.ok) {
      return new FitRecsWriteResult(false, result.error);
    }
    return new FitRecsWriteResult(true, undefined);
  }

  /** 本地镜像（不联网）。 */
  local(): FitRecord[] {
    return this.cache;
  }

  static parseRows(raw: string): FitRecord[] {
    if (raw.length === 0) {
      return [];
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (e) {
      return [];
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined) {
      return [];
    }
    const out: FitRecord[] = [];
    for (let i = 0; i < array.length; i++) {
      const row: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (row === undefined) {
        continue;
      }
      const data: string = JsonBlob.asString(JsonBlob.get(row, 'data'), '');
      const record: FitRecord | undefined = FitCodec.recordFromData(data);
      if (record !== undefined) {
        out.push(record);
      }
    }
    out.sort((a: FitRecord, b: FitRecord) => b.ts - a.ts);
    return out;
  }
}
