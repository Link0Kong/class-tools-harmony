/**
 * JSON 树工具（ArkTS 没有 kotlinx.serialization 的 JsonElement，用 Record<string, JsonValue> 表达）。
 *
 * 约定：
 * - 合并/比较一律在 JSON 树上做（保序、保留未知字段），**不要**转成 data class——
 *   那会丢掉「未拥有 section 原样保留」和未知字段，导致跨端覆盖（契约 §4.4）。
 * - 比较是「结构相等」（对象键序无关、数组有序），与 kotlinx JsonObject.equals 语义一致。
 */
export type JsonValue = Object | null;
export type Blob = Record<string, JsonValue>;

export class JsonBlob {
  static parse(text: string): Blob | undefined {
    if (text.length === 0) {
      return undefined;
    }
    try {
      const value: JsonValue = JSON.parse(text) as JsonValue;
      return JsonBlob.asBlob(value);
    } catch (e) {
      return undefined;
    }
  }

  static encode(blob: Blob): string {
    return JSON.stringify(blob);
  }

  static isNullish(value: JsonValue | undefined): boolean {
    return value === null || value === undefined;
  }

  static asBlob(value: JsonValue | undefined): Blob | undefined {
    if (value === null || value === undefined) {
      return undefined;
    }
    if (typeof value !== 'object') {
      return undefined;
    }
    if (Array.isArray(value)) {
      return undefined;
    }
    return value as Blob;
  }

  static asArray(value: JsonValue | undefined): Object[] | undefined {
    if (value === null || value === undefined) {
      return undefined;
    }
    if (!Array.isArray(value)) {
      return undefined;
    }
    return value as Object[];
  }

  static asString(value: JsonValue | undefined, fallback: string): string {
    if (value === null || value === undefined) {
      return fallback;
    }
    if (typeof value !== 'string') {
      return fallback;
    }
    return value as string;
  }

  static asNumber(value: JsonValue | undefined, fallback: number): number {
    if (value === null || value === undefined) {
      return fallback;
    }
    if (typeof value !== 'number') {
      return fallback;
    }
    const n: number = value as number;
    return Number.isFinite(n) ? n : fallback;
  }

  static asBoolean(value: JsonValue | undefined, fallback: boolean): boolean {
    if (value === null || value === undefined) {
      return fallback;
    }
    if (typeof value !== 'boolean') {
      return fallback;
    }
    return value as boolean;
  }

  /** 时间戳解析：只有有限且 >0 的数才有效（与 web/mp `num(v)=isFinite(v)&&v>0?v:0` 等价）。 */
  static numMs(value: JsonValue | undefined): number {
    if (value === null || value === undefined) {
      return 0;
    }
    if (typeof value === 'string') {
      return 0;
    }
    if (typeof value !== 'number') {
      return 0;
    }
    const n: number = value as number;
    if (!Number.isFinite(n) || n <= 0) {
      return 0;
    }
    return n;
  }

  static clone(value: JsonValue | undefined): JsonValue | undefined {
    if (value === undefined) {
      return undefined;
    }
    return JSON.parse(JSON.stringify(value)) as JsonValue;
  }

  static keys(blob: Blob): string[] {
    return Object.keys(blob);
  }

  static has(blob: Blob | undefined, key: string): boolean {
    if (blob === undefined) {
      return false;
    }
    return Object.keys(blob).indexOf(key) >= 0;
  }

  static get(blob: Blob | undefined, key: string): JsonValue | undefined {
    if (blob === undefined) {
      return undefined;
    }
    const keys: string[] = Object.keys(blob);
    if (keys.indexOf(key) < 0) {
      return undefined;
    }
    return blob[key];
  }

  /** 结构相等：对象键序无关、数组有序、null 等于 null/缺失。 */
  static deepEqual(a: JsonValue | undefined, b: JsonValue | undefined): boolean {
    if (a === undefined || a === null) {
      return b === undefined || b === null;
    }
    if (b === undefined || b === null) {
      return false;
    }
    if (typeof a !== typeof b) {
      return false;
    }
    if (Array.isArray(a)) {
      if (!Array.isArray(b)) {
        return false;
      }
      const aa: Object[] = a as Object[];
      const bb: Object[] = b as Object[];
      if (aa.length !== bb.length) {
        return false;
      }
      for (let i = 0; i < aa.length; i++) {
        if (!JsonBlob.deepEqual(aa[i], bb[i])) {
          return false;
        }
      }
      return true;
    }
    if (typeof a === 'object') {
      const ao: Blob | undefined = JsonBlob.asBlob(a);
      const bo: Blob | undefined = JsonBlob.asBlob(b);
      if (ao === undefined || bo === undefined) {
        return false;
      }
      const ak: string[] = Object.keys(ao);
      const bk: string[] = Object.keys(bo);
      if (ak.length !== bk.length) {
        return false;
      }
      for (let i = 0; i < ak.length; i++) {
        const k: string = ak[i];
        if (bk.indexOf(k) < 0) {
          return false;
        }
        if (!JsonBlob.deepEqual(ao[k], bo[k])) {
          return false;
        }
      }
      return true;
    }
    return a === b;
  }
}
