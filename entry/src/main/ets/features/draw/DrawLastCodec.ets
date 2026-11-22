import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { DrawConfigCodec } from './DrawConfigCodec';
import { DrawEntry, DrawResult } from './DrawModels';

/** 最近一次成功抽签的本机快照（不参与 userdata 同步）。 */
export class DrawLast {
  at: number = 0;
  result: DrawResult = new DrawResult();

  constructor(at: number = 0, result: DrawResult = new DrawResult()) {
    this.at = at;
    this.result = result;
  }
}

/**
 * 「最近一次抽签结果」本机存储编解码（契约 `web/group/CONTRACT.md` §3）。
 *
 * 线格式（逻辑等价，字段名只在本端使用）：
 * `{"v":1,"at":<ms>,"result":[3,7],"names":["甲",""],"pool":[1..70],
 *   "cfg":{"start":1,"end":70,"count":2,"dup":false,"sort":"draw"}}`
 *
 * - `result` 只存序号数组，`names` 与它等长（空串 = 无名称），
 *   分组沿用时的名称优先级仍是「名称映射 > 班级名单派生名 > 空」，由分组页兜底；
 * - `pool` 用于把快照还原成完整 `DrawResult`（重抽/剔除补抽仍可用）；
 * - 读取容错：缺字段/脏数据回落默认值，空结果视为无快照。
 */
export class DrawLastCodec {
  static readonly VERSION: number = 1;

  static encode(result: DrawResult, at: number): Blob {
    const seats: Object[] = [];
    const names: Object[] = [];
    for (let i = 0; i < result.entries.length; i++) {
      seats.push(result.entries[i].number);
      names.push(result.entries[i].name);
    }
    const pool: Object[] = [];
    for (let i = 0; i < result.pool.length; i++) {
      pool.push(result.pool[i].number);
    }
    const cfg: Blob = {
      'start': result.config.start,
      'end': result.config.end,
      'count': result.config.count,
      'dup': result.config.allowDuplicates,
      'sort': result.config.sort
    };
    return {
      'v': DrawLastCodec.VERSION,
      'at': at,
      'result': seats,
      'names': names,
      'pool': pool,
      'cfg': cfg
    };
  }

  static decode(blob: Blob | undefined): DrawLast | undefined {
    if (blob === undefined) {
      return undefined;
    }
    const seats: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(blob, 'result'));
    if (seats === undefined || seats.length === 0) {
      return undefined;
    }
    const names: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(blob, 'names'));
    const entries: DrawEntry[] = [];
    for (let i = 0; i < seats.length; i++) {
      const seat: number = DrawLastCodec.seatOf(seats[i]);
      if (seat < 1 || seat > 999) {
        continue;
      }
      const name: string = names !== undefined && i < names.length
        ? JsonBlob.asString(names[i], '').trim()
        : '';
      entries.push(new DrawEntry(seat, name));
    }
    if (entries.length === 0) {
      return undefined;
    }
    const result: DrawResult = new DrawResult();
    result.entries = entries;
    result.pool = DrawLastCodec.decodePool(JsonBlob.asArray(JsonBlob.get(blob, 'pool')));
    result.config = DrawConfigCodec.fromJson(JsonBlob.asBlob(JsonBlob.get(blob, 'cfg')));
    result.log = [];
    return new DrawLast(JsonBlob.numMs(JsonBlob.get(blob, 'at')), result);
  }

  private static decodePool(values: Object[] | undefined): DrawEntry[] {
    const out: DrawEntry[] = [];
    if (values === undefined) {
      return out;
    }
    for (let i = 0; i < values.length; i++) {
      const seat: number = DrawLastCodec.seatOf(values[i]);
      if (seat >= 1 && seat <= 999) {
        out.push(new DrawEntry(seat, ''));
      }
    }
    return out;
  }

  private static seatOf(value: Object): number {
    let parsed: number = Number.NaN;
    if (typeof value === 'number') {
      parsed = value as number;
    } else if (typeof value === 'string') {
      parsed = Number((value as string).trim());
    }
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    return Math.round(parsed);
  }
}
