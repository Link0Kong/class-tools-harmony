import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import { PowerPoint, PowerRange, PowerRow } from './PowerModels';

const ROW_TTL_MS: number = 3 * 60 * 1000;
const HISTORY_TTL_MS: number = 5 * 60 * 1000;
const HISTORY_LIMIT: number = 2000;

export class PowerRowResult {
  ok: boolean;
  row: PowerRow | undefined = undefined;
  fromCache: boolean = false;
  message: string = '';

  constructor(ok: boolean, row: PowerRow | undefined, fromCache: boolean, message: string) {
    this.ok = ok;
    this.row = row;
    this.fromCache = fromCache;
    this.message = message;
  }
}

export class PowerHistoryResult {
  ok: boolean;
  points: PowerPoint[] = [];
  fromCache: boolean = false;
  message: string = '';

  constructor(ok: boolean, points: PowerPoint[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.points = points;
    this.fromCache = fromCache;
    this.message = message;
  }
}

/**
 * 电费仓库（契约 E22/E23）：
 * - 当前值：`power?select=id,label,building,room,quantity,unit,low,updated_at&id=eq.<rv>`（3 分钟 TTL）；
 * - 历史：`power_history?select=ts,quantity&roomverify=eq.<rv>&ts=gte.<iso>&order=ts.asc&limit=2000`（5 分钟 TTL）。
 */
export class PowerRepository {
  private api: Api;
  private clock: () => number;

  private rowCache: Map<string, PowerRow> = new Map<string, PowerRow>();
  private rowAt: Map<string, number> = new Map<string, number>();
  private historyCache: Map<string, PowerPoint[]> = new Map<string, PowerPoint[]>();
  private historyAt: Map<string, number> = new Map<string, number>();

  constructor(api: Api, clock: () => number = () => Date.now()) {
    this.api = api;
    this.clock = clock;
  }

  async loadRow(rv: string, force: boolean): Promise<PowerRowResult> {
    const cached: PowerRow | undefined = this.rowCache.get(rv);
    const at: number = this.rowAt.get(rv) !== undefined ? this.rowAt.get(rv) as number : 0;
    if (!force && cached !== undefined && this.clock() - at < ROW_TTL_MS) {
      return new PowerRowResult(true, cached, true, '');
    }
    const path: string = 'power?select=id,label,building,room,quantity,unit,low,updated_at&id=eq.'
      + encodeURIComponent(rv);
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      if (cached !== undefined) {
        return new PowerRowResult(true, cached, true,
          result.error !== undefined ? result.error.displayMessage() : '电费加载失败');
      }
      return new PowerRowResult(false, undefined, false,
        result.error !== undefined ? result.error.displayMessage() : '电费加载失败');
    }
    const row: PowerRow | undefined = PowerRepository.parseRow(result.value);
    if (row === undefined) {
      if (cached !== undefined) {
        return new PowerRowResult(true, cached, true, '电费数据为空');
      }
      return new PowerRowResult(false, undefined, false, '该宿舍暂无电费数据');
    }
    this.rowCache.set(rv, row);
    this.rowAt.set(rv, this.clock());
    return new PowerRowResult(true, row, false, '');
  }

  async loadHistory(rv: string, range: PowerRange, force: boolean): Promise<PowerHistoryResult> {
    const key: string = rv + '|' + range.key;
    const cached: PowerPoint[] | undefined = this.historyCache.get(key);
    const at: number = this.historyAt.get(key) !== undefined ? this.historyAt.get(key) as number : 0;
    if (!force && cached !== undefined && this.clock() - at < HISTORY_TTL_MS) {
      return new PowerHistoryResult(true, cached, true, '');
    }
    const cutoff: string = new Date(this.clock() - range.windowMs).toISOString();
    const path: string = 'power_history?select=ts,quantity&roomverify=eq.' + encodeURIComponent(rv)
      + '&ts=gte.' + encodeURIComponent(cutoff) + '&order=ts.asc&limit=' + HISTORY_LIMIT;
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      if (cached !== undefined) {
        return new PowerHistoryResult(true, cached, true,
          result.error !== undefined ? result.error.displayMessage() : '趋势加载失败');
      }
      return new PowerHistoryResult(false, [], false,
        result.error !== undefined ? result.error.displayMessage() : '趋势加载失败');
    }
    const points: PowerPoint[] = PowerRepository.parseHistory(result.value);
    this.historyCache.set(key, points);
    this.historyAt.set(key, this.clock());
    return new PowerHistoryResult(true, points, false, '');
  }

  /** 任意窗口历史（同期比较用；不走缓存）。 */
  async loadHistoryWindow(rv: string, windowMs: number, force: boolean): Promise<PowerHistoryResult> {
    const cutoff: string = new Date(this.clock() - windowMs).toISOString();
    const path: string = 'power_history?select=ts,quantity&roomverify=eq.' + encodeURIComponent(rv)
      + '&ts=gte.' + encodeURIComponent(cutoff) + '&order=ts.asc&limit=' + HISTORY_LIMIT;
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      return new PowerHistoryResult(false, [], false,
        result.error !== undefined ? result.error.displayMessage() : '趋势加载失败');
    }
    return new PowerHistoryResult(true, PowerRepository.parseHistory(result.value), false, '');
  }

  static parseRow(raw: string): PowerRow | undefined {
    const rows: Blob[] = PowerRepository.rowsOf(raw);
    if (rows.length === 0) {
      return undefined;
    }
    const obj: Blob = rows[0];
    const row: PowerRow = new PowerRow();
    row.id = JsonBlob.asString(JsonBlob.get(obj, 'id'), '');
    row.label = JsonBlob.asString(JsonBlob.get(obj, 'label'), '');
    row.building = JsonBlob.asString(JsonBlob.get(obj, 'building'), '');
    row.room = JsonBlob.asString(JsonBlob.get(obj, 'room'), '');
    row.unit = JsonBlob.asString(JsonBlob.get(obj, 'unit'), '度');
    row.low = JsonBlob.asBoolean(JsonBlob.get(obj, 'low'), false);
    row.updatedAt = JsonBlob.asString(JsonBlob.get(obj, 'updated_at'), '');
    const quantity = JsonBlob.get(obj, 'quantity');
    if (typeof quantity === 'number' && Number.isFinite(quantity as number)) {
      row.q = quantity as number;
      row.hasValue = true;
    } else if (typeof quantity === 'string') {
      const parsed: number = Number(quantity as string);
      if (Number.isFinite(parsed)) {
        row.q = parsed;
        row.hasValue = true;
      }
    }
    return row;
  }

  static parseHistory(raw: string): PowerPoint[] {
    const rows: Blob[] = PowerRepository.rowsOf(raw);
    const out: PowerPoint[] = [];
    for (let i = 0; i < rows.length; i++) {
      const obj: Blob = rows[i];
      const q: number = JsonBlob.asNumber(JsonBlob.get(obj, 'quantity'), Number.NaN);
      const t: number = PowerRepository.timeOf(JsonBlob.get(obj, 'ts'));
      if (Number.isFinite(q) && t > 0) {
        const point: PowerPoint = new PowerPoint();
        point.q = q;
        point.t = t;
        out.push(point);
      }
    }
    out.sort((a: PowerPoint, b: PowerPoint) => a.t - b.t);
    return out;
  }

  private static timeOf(value: JsonValue | undefined): number {
    if (typeof value === 'number') {
      const num: number = value as number;
      return num > 1e12 ? num : num * 1000;
    }
    if (typeof value === 'string') {
      const text: string = value as string;
      const parsed: number = Date.parse(text);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private static rowsOf(raw: string): Blob[] {
    if (raw.trim().length === 0) {
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
    const out: Blob[] = [];
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj !== undefined) {
        out.push(obj);
      }
    }
    return out;
  }
}
