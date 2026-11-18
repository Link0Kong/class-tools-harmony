import { Blob, JsonBlob, JsonValue } from '../../data/sync/JsonBlob';
import { DrawConfig, DrawPoolSource, drawSortFromWire, DrawSortMode } from './DrawModels';

/**
 * `userdata` v6 `draw` section 编解码。
 *
 * 线格式（与网页/小程序一致，键序固定）：
 * `{"start":1,"end":70,"count":10,"dup":false,"excl":"","sort":"draw"}`
 * 读取对脏数据容错：数值越界 clamp、缺失字段回落默认值。
 */
export class DrawConfigCodec {
  /**
   * 写回 `userdata.draw`。
   *
   * `existing` 传入当前 section 时，**保留未知字段**（例如网页 2026-11-12 新增的 `names` 自定义名称文本），
   * 否则会把别的端的字段覆盖丢失（契约：不拥有/不认识的字段必须原样保留）。
   */
  static toJson(config: DrawConfig, existing?: Blob): Blob {
    const out: Blob = {
      'start': config.start,
      'end': config.end,
      'count': config.count,
      'dup': config.allowDuplicates,
      'excl': config.excludedText,
      'sort': config.sort
    };
    if (existing !== undefined) {
      const keys: string[] = JsonBlob.keys(existing);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        if (JsonBlob.get(out, key) === undefined) {
          out[key] = existing[key];
        }
      }
    }
    return out;
  }

  /** 从 `userdata.draw`（可能缺失/脏数据）解析；失败一律回落默认值。 */
  static fromJson(section: JsonValue | undefined, fallback: DrawConfig = new DrawConfig()): DrawConfig {
    const obj: Blob | undefined = JsonBlob.asBlob(section);
    if (obj === undefined) {
      return fallback.copy();
    }
    const config: DrawConfig = new DrawConfig();
    config.start = intField(obj, 'start', fallback.start, DrawConfig.MIN_NUMBER, DrawConfig.MAX_NUMBER);
    config.end = intField(obj, 'end', fallback.end, DrawConfig.MIN_NUMBER, DrawConfig.MAX_NUMBER);
    config.count = intField(obj, 'count', fallback.count, DrawConfig.MIN_COUNT, DrawConfig.MAX_COUNT);
    config.allowDuplicates = JsonBlob.asBoolean(JsonBlob.get(obj, 'dup'), fallback.allowDuplicates);
    config.excludedText = JsonBlob.asString(JsonBlob.get(obj, 'excl'), fallback.excludedText);
    config.sort = drawSortFromWire(JsonBlob.asString(JsonBlob.get(obj, 'sort'), fallback.sort));
    // 候选池来源不属于跨端契约（仅本机 UI 选择），读取时恒为 RANGE
    config.poolSource = DrawPoolSource.RANGE;
    return config;
  }

  static defaults(): DrawConfig {
    return new DrawConfig();
  }
}

function intField(obj: Blob, key: string, fallback: number, min: number, max: number): number {
  const raw: JsonValue | undefined = JsonBlob.get(obj, key);
  if (raw === null || raw === undefined) {
    return fallback;
  }
  let value: number = Number.NaN;
  if (typeof raw === 'number') {
    value = raw as number;
  } else if (typeof raw === 'string') {
    value = Number((raw as string).trim());
  }
  if (!Number.isFinite(value)) {
    return fallback;
  }
  const rounded: number = Math.round(value);
  if (rounded < min) {
    return min;
  }
  if (rounded > max) {
    return max;
  }
  return rounded;
}

export function drawSortWireOf(mode: DrawSortMode): string {
  return mode;
}
