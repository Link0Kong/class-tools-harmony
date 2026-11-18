import { Blob, JsonBlob, JsonValue } from './JsonBlob';

/**
 * `water` section 归一化（契约：`_water_contract.md` §7.1 + `USERDATA_V6.md` §1.3）。
 *
 * 结构：`{ "rooms": { "<roomverify>": { "p": 4|6, "recs": [ {"m":"YYYY-MM","r":<吨>,"ts":<ms>} ] } } }`
 * 规则：p 只允许 4/6；月份合法 `YYYY-MM`；读数有限且 ≥0、保留 2 位；按月唯一升序；≤120 条；坏房间丢弃。
 */
export class WaterNormalizer {
  static readonly MAX_RECORDS: number = 120;
  static readonly PERSONS_DEFAULT: number = 4;

  static normalize(section: JsonValue | undefined): Blob {
    const sectionBlob: Blob | undefined = JsonBlob.asBlob(section);
    const roomsElement: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sectionBlob, 'rooms'));
    const rooms: Blob = {};
    if (roomsElement !== undefined) {
      const keys: string[] = JsonBlob.keys(roomsElement);
      for (let i = 0; i < keys.length; i++) {
        const roomVerify: string = keys[i];
        if (roomVerify.trim().length === 0) {
          continue;
        }
        const room: Blob | undefined = JsonBlob.asBlob(roomsElement[roomVerify]);
        if (room === undefined) {
          continue;
        }
        const pRaw: number = JsonBlob.asNumber(JsonBlob.get(room, 'p'), WaterNormalizer.PERSONS_DEFAULT);
        const persons: number = pRaw === 6 ? 6 : WaterNormalizer.PERSONS_DEFAULT;
        const recs: Object[] = WaterNormalizer.normalizeRecords(JsonBlob.get(room, 'recs'));
        const roomOut: Blob = { 'p': persons, 'recs': recs };
        rooms[roomVerify] = roomOut;
      }
    }
    const out: Blob = { 'rooms': rooms };
    return out;
  }

  /** 归一记录列表（同月后者覆盖；按月升序；最多 120 条保留最新月份）。 */
  static normalizeRecords(input: JsonValue | undefined): Object[] {
    const array: Object[] | undefined = JsonBlob.asArray(input);
    if (array === undefined) {
      return [];
    }
    const byMonth: Map<string, Blob> = new Map<string, Blob>();
    for (let i = 0; i < array.length; i++) {
      const record: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (record === undefined) {
        continue;
      }
      const month: string = JsonBlob.asString(JsonBlob.get(record, 'm'), '');
      if (!WaterNormalizer.isValidMonth(month)) {
        continue;
      }
      const reading: number = WaterNormalizer.readingOf(JsonBlob.get(record, 'r'));
      if (!Number.isFinite(reading) || reading < 0) {
        continue;
      }
      const ts: number = JsonBlob.asNumber(JsonBlob.get(record, 'ts'), 0);
      const rounded: number = WaterNormalizer.round2(reading);
      // 与网页 `Math.round(r*100)/100` 的数字形态一致：整数读数输出 80 而不是 80.0
      const readingValue: JsonValue = WaterNormalizer.isInteger(rounded) ? Math.round(rounded) : rounded;
      const row: Blob = { 'm': month, 'r': readingValue, 'ts': ts };
      byMonth.set(month, row);
    }
    const months: string[] = [];
    byMonth.forEach((value: Blob, key: string) => {
      months.push(key);
    });
    months.sort();
    let selected: string[] = months;
    if (months.length > WaterNormalizer.MAX_RECORDS) {
      selected = months.slice(months.length - WaterNormalizer.MAX_RECORDS);
    }
    const out: Object[] = [];
    for (let i = 0; i < selected.length; i++) {
      const row: Blob | undefined = byMonth.get(selected[i]);
      if (row !== undefined) {
        out.push(row);
      }
    }
    return out;
  }

  /** 读数保留 2 位小数（与网页 `Math.round(r*100)/100` 一致）。 */
  static round2(value: number): number {
    return Math.round(value * 100) / 100;
  }

  private static readingOf(value: JsonValue | undefined): number {
    if (value === null || value === undefined) {
      return Number.NaN;
    }
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const parsed: number = Number(value as string);
      return Number.isFinite(parsed) ? parsed : Number.NaN;
    }
    return Number.NaN;
  }

  private static isValidMonth(month: string): boolean {
    if (month.length !== 7) {
      return false;
    }
    if (month.charAt(4) !== '-') {
      return false;
    }
    for (let i = 0; i < 7; i++) {
      if (i === 4) {
        continue;
      }
      const c: number = month.charCodeAt(i);
      if (c < 48 || c > 57) {
        return false;
      }
    }
    const mm: number = Number(month.substring(5, 7));
    return mm >= 1 && mm <= 12;
  }

  private static isInteger(value: number): boolean {
    return Math.abs(value - Math.round(value)) < 1e-9;
  }
}
