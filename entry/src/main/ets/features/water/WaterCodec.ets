import { Blob, JsonBlob, JsonValue } from '../../data/sync/JsonBlob';
import { WaterRecord, WaterRoomState, WaterRules, WaterState } from './WaterModels';

/**
 * `userdata.water` section 编解码（契约 `_water_contract.md` §2/§7）。
 *
 * 输出键序固定：`rooms` → `<roomverify>` → `p`、`recs` → `m`、`r`、`ts`。
 * 输入容错：人数非 4/6 → 4；月份非法/读数非有限负数丢弃；同月保留最后一条；按月升序；每间 ≤120 条。
 */
export class WaterCodec {
  private static readonly MONTH_PATTERN: RegExp = new RegExp('^\\d{4}-(0[1-9]|1[0-2])$');

  static fromJson(section: JsonValue | undefined): WaterState {
    const state: WaterState = new WaterState();
    const obj: Blob | undefined = JsonBlob.asBlob(section);
    if (obj === undefined) {
      return state;
    }
    const rooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(obj, 'rooms'));
    if (rooms === undefined) {
      return state;
    }
    const keys: string[] = JsonBlob.keys(rooms);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i].trim();
      if (key.length === 0) {
        continue;
      }
      const roomBlob: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(rooms, keys[i]));
      if (roomBlob === undefined) {
        continue;
      }
      const room: WaterRoomState = new WaterRoomState();
      room.persons = WaterCodec.normalizePersons(Math.round(JsonBlob.asNumber(JsonBlob.get(roomBlob, 'p'),
        WaterRules.PERSONS_DEFAULT)));
      room.records = WaterCodec.normalizeRecords(JsonBlob.get(roomBlob, 'recs'));
      state.rooms.set(key, room);
    }
    return state;
  }

  static toJson(state: WaterState): Blob {
    const rooms: Blob = {};
    const keys: string[] = [];
    state.rooms.forEach((room: WaterRoomState, key: string) => {
      keys.push(key);
    });
    keys.sort();
    for (let i = 0; i < keys.length; i++) {
      const room: WaterRoomState | undefined = state.rooms.get(keys[i]);
      if (room === undefined) {
        continue;
      }
      const recs: Object[] = [];
      const records: WaterRecord[] = WaterCodec.normalizeRecords(recordsToJson(room.records));
      for (let j = 0; j < records.length; j++) {
        recs.push(recordToBlob(records[j]));
      }
      const roomBlob: Blob = {};
      roomBlob['p'] = WaterCodec.normalizePersons(room.persons);
      roomBlob['recs'] = recs;
      rooms[keys[i]] = roomBlob;
    }
    const out: Blob = {};
    out['rooms'] = rooms;
    return out;
  }

  static normalizePersons(persons: number): number {
    for (let i = 0; i < WaterRules.PERSONS_OPTIONS.length; i++) {
      if (WaterRules.PERSONS_OPTIONS[i] === persons) {
        return persons;
      }
    }
    return WaterRules.PERSONS_DEFAULT;
  }

  static normalizeMonth(month: string): string | undefined {
    const text: string = month.trim();
    return WaterCodec.MONTH_PATTERN.test(text) ? text : undefined;
  }

  /** 归一记录：合法月份+读数；同月后者覆盖；升序；≤120。 */
  static normalizeRecords(value: JsonValue | undefined): WaterRecord[] {
    const array: Object[] | undefined = JsonBlob.asArray(value);
    if (array === undefined) {
      return [];
    }
    const byMonth: Map<string, WaterRecord> = new Map<string, WaterRecord>();
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj === undefined) {
        continue;
      }
      const month: string | undefined = WaterCodec.normalizeMonth(
        JsonBlob.asString(JsonBlob.get(obj, 'm'), ''));
      if (month === undefined) {
        continue;
      }
      const reading: number = readingOf(JsonBlob.get(obj, 'r'));
      if (!Number.isFinite(reading) || reading < 0) {
        continue;
      }
      const record: WaterRecord = new WaterRecord();
      record.month = month;
      record.reading = WaterCodec.round2(reading);
      record.ts = JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0);
      byMonth.set(month, record);
    }
    const months: string[] = [];
    byMonth.forEach((record: WaterRecord, month: string) => {
      months.push(month);
    });
    months.sort();
    const start: number = months.length > WaterRules.MAX_RECORDS_PER_ROOM
      ? months.length - WaterRules.MAX_RECORDS_PER_ROOM : 0;
    const out: WaterRecord[] = [];
    for (let i = start; i < months.length; i++) {
      const record: WaterRecord | undefined = byMonth.get(months[i]);
      if (record !== undefined) {
        out.push(record);
      }
    }
    return out;
  }

  static round2(value: number): number {
    return Number.isFinite(value) ? Math.round(value * 100) / 100 : 0;
  }

  static round1(value: number): number {
    return Number.isFinite(value) ? Math.round(value * 10) / 10 : 0;
  }
}

function readingOf(value: JsonValue | undefined): number {
  if (typeof value === 'number') {
    return value as number;
  }
  if (typeof value === 'string') {
    return Number(value as string);
  }
  return Number.NaN;
}

function recordToBlob(record: WaterRecord): Blob {
  const blob: Blob = {};
  blob['m'] = record.month;
  const rounded: number = WaterCodec.round2(record.reading);
  if (Math.abs(rounded - Math.round(rounded)) < 1e-9) {
    blob['r'] = Math.round(rounded);
  } else {
    blob['r'] = rounded;
  }
  blob['ts'] = record.ts;
  return blob;
}

function recordsToJson(records: WaterRecord[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < records.length; i++) {
    out.push(recordToBlob(records[i]));
  }
  return out;
}
