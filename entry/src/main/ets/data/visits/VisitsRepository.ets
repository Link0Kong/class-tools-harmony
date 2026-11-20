import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';

/**
 * `public.visits` 一行（统计页只读）。
 *
 * 隐私：`sid` / `did` 只作聚合与去重键，**任何页面都不显示**（契约 §2）；
 * `name` 是上报时的姓名快照，`ver` / `dev` 是 2026-11-20 起记录的新列（旧行为空串）。
 */
export class VisitRow {
  slot: string = '';
  sid: string = '';
  name: string = '';
  ts: number = 0;
  client: string = '';
  ver: string = '';
  dev: string = '';
  did: string = '';
}

/** 读取结果：失败不抛异常，返回错误文案（页面显示失败态）。 */
export class VisitLoadResult {
  ok: boolean = false;
  rows: VisitRow[] = [];
  message: string = '';

  constructor(ok: boolean = false, rows: VisitRow[] = [], message: string = '') {
    this.ok = ok;
    this.rows = rows;
    this.message = message;
  }
}

/**
 * 访问统计读取仓库（契约 §2，五端同一查询）。
 *
 * `GET visits?select=slot,sid,name,ts,client,ver,dev,did&slot=gte.<今天-6>-00&order=ts.desc&limit=5000`
 * - 一次拉 7 天，页面内切换「今天 / 近 7 天」不重新请求；
 * - 只管理员可读（RLS 不变），非管理员由页面在发请求前拦截；
 * - 解析失败 / 网络失败一律返回空数组 + 错误文案，不抛异常。
 */
export class VisitsRepository {
  private api: Api;
  private clock: () => number;

  constructor(api: Api, clock: () => number = () => Date.now()) {
    this.api = api;
    this.clock = clock;
  }

  async load(): Promise<VisitLoadResult> {
    const result: ApiResult = await this.api.get(VisitsRepository.statsPath(this.clock()), true);
    if (!result.ok) {
      const message: string = result.error !== undefined ? result.error.displayMessage() : '访问统计加载失败';
      return new VisitLoadResult(false, [], message);
    }
    return new VisitLoadResult(true, VisitsRepository.parseRows(result.value), '');
  }

  /** 统计页查询路径（`from` 固定「今天 - 6 天」的 00 时，共 7 个自然日）。 */
  static statsPath(nowMs: number): string {
    return 'visits?select=slot,sid,name,ts,client,ver,dev,did&slot=gte.' + VisitsRepository.fromSlot(nowMs)
      + '&order=ts.desc&limit=5000';
  }

  /** `from` 槽位：`YYYY-MM-DD-00`（本地时区）。 */
  static fromSlot(nowMs: number): string {
    const now: Date = new Date(nowMs);
    const start: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
    const month: string = pad2(start.getMonth() + 1);
    const day: string = pad2(start.getDate());
    return start.getFullYear() + '-' + month + '-' + day + '-00';
  }

  /** 解析 PostgREST 数组；坏行跳过，非数组 / 坏 JSON 返回空数组。 */
  static parseRows(raw: string): VisitRow[] {
    const out: VisitRow[] = [];
    const text: string = raw.trim();
    if (text.length === 0) {
      return out;
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (e) {
      return out;
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined) {
      return out;
    }
    for (let i = 0; i < array.length; i++) {
      const blob: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (blob === undefined) {
        continue;
      }
      const row: VisitRow = new VisitRow();
      row.slot = JsonBlob.asString(JsonBlob.get(blob, 'slot'), '');
      row.sid = JsonBlob.asString(JsonBlob.get(blob, 'sid'), '');
      row.name = JsonBlob.asString(JsonBlob.get(blob, 'name'), '');
      row.ts = JsonBlob.numMs(JsonBlob.get(blob, 'ts'));
      row.client = JsonBlob.asString(JsonBlob.get(blob, 'client'), '');
      row.ver = JsonBlob.asString(JsonBlob.get(blob, 'ver'), '');
      row.dev = JsonBlob.asString(JsonBlob.get(blob, 'dev'), '');
      row.did = JsonBlob.asString(JsonBlob.get(blob, 'did'), '');
      out.push(row);
    }
    return out;
  }
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
