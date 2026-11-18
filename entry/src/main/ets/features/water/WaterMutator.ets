import { WaterRecord, WaterRecordReview, WaterRoomState, WaterRules, WaterState } from './WaterModels';
import { WaterCodec } from './WaterCodec';
import { WaterCalculator } from './WaterCalculator';
import { WaterMonth } from './WaterMonth';

/**
 * 水量状态变更（纯函数）：
 * - 录入：月份合法、读数 ≥0、2 位小数；不得小于上一条、不得大于下一条；同月覆盖需确认；
 * - 删除：按月份；人数切换 4/6；清空单间；
 * - 所有变更返回新 WaterState（整段 LWW 写回 userdata.water）。
 */
export class WaterMutator {
  static review(room: WaterRoomState, monthRaw: string, readingRaw: string, nowMillis: number): WaterRecordReview {
    const review: WaterRecordReview = new WaterRecordReview();
    const month: string | undefined = WaterCodec.normalizeMonth(monthRaw);
    if (month === undefined) {
      review.message = '月份格式应为 YYYY-MM';
      return review;
    }
    const text: string = readingRaw.trim().replace(new RegExp('\\s+', 'g'), '');
    const reading: number = Number(text);
    if (text.length === 0 || !Number.isFinite(reading)) {
      review.message = '请输入水表读数（吨）';
      return review;
    }
    if (reading < 0) {
      review.message = '读数需为 ≥0 的数字';
      return review;
    }
    const rounded: number = WaterCodec.round2(reading);
    const previous: WaterRecord | undefined = WaterCalculator.previousRecord(room, month);
    if (previous !== undefined && rounded < previous.reading) {
      review.message = '读数不能小于上月（' + previous.month + '）的 ' + previous.reading.toFixed(2) + ' 吨';
      return review;
    }
    const next: WaterRecord | undefined = WaterCalculator.nextRecord(room, month);
    if (next !== undefined && rounded > next.reading) {
      review.message = '读数不能大于下一条记录（' + next.month + '）的 ' + next.reading.toFixed(2) + ' 吨';
      return review;
    }
    const existing: WaterRecord | undefined = WaterCalculator.recordOf(room, month);
    review.valid = true;
    review.replaceExisting = existing !== undefined;
    const record: WaterRecord = new WaterRecord();
    record.month = month;
    record.reading = rounded;
    record.ts = nowMillis;
    review.record = record;
    return review;
  }

  /** 写入/覆盖一条记录。 */
  static put(state: WaterState, roomVerify: string, record: WaterRecord): WaterState {
    const key: string = roomVerify.trim();
    const month: string | undefined = WaterCodec.normalizeMonth(record.month);
    if (key.length === 0 || month === undefined) {
      return state;
    }
    const next: WaterState = state.copy();
    const room: WaterRoomState = next.rooms.has(key) ? next.rooms.get(key) as WaterRoomState : new WaterRoomState();
    const merged: Map<string, WaterRecord> = new Map<string, WaterRecord>();
    for (let i = 0; i < room.records.length; i++) {
      merged.set(room.records[i].month, room.records[i]);
    }
    const normalized: WaterRecord = new WaterRecord();
    normalized.month = month;
    normalized.reading = WaterCodec.round2(record.reading);
    normalized.ts = record.ts;
    merged.set(month, normalized);
    const months: string[] = [];
    merged.forEach((value: WaterRecord, keyMonth: string) => {
      months.push(keyMonth);
    });
    months.sort();
    const start: number = months.length > WaterRules.MAX_RECORDS_PER_ROOM
      ? months.length - WaterRules.MAX_RECORDS_PER_ROOM : 0;
    const records: WaterRecord[] = [];
    for (let i = start; i < months.length; i++) {
      const item: WaterRecord | undefined = merged.get(months[i]);
      if (item !== undefined) {
        records.push(item);
      }
    }
    room.records = records;
    next.rooms.set(key, room);
    return next;
  }

  /** 删除某月记录。 */
  static delete(state: WaterState, roomVerify: string, month: string): WaterState {
    const key: string = roomVerify.trim();
    const safeMonth: string | undefined = WaterCodec.normalizeMonth(month);
    const room: WaterRoomState | undefined = state.rooms.get(key);
    if (safeMonth === undefined || room === undefined) {
      return state;
    }
    const next: WaterState = state.copy();
    const nextRoom: WaterRoomState = next.rooms.get(key) as WaterRoomState;
    const records: WaterRecord[] = [];
    for (let i = 0; i < nextRoom.records.length; i++) {
      if (nextRoom.records[i].month !== safeMonth) {
        records.push(nextRoom.records[i]);
      }
    }
    if (records.length === nextRoom.records.length) {
      return state;
    }
    nextRoom.records = records;
    return next;
  }

  /** 切换 4/6 人间（影响免费额度与计费；历史记录不变）。 */
  static withPersons(state: WaterState, roomVerify: string, persons: number): WaterState {
    const key: string = roomVerify.trim();
    if (key.length === 0) {
      return state;
    }
    const safePersons: number = WaterCodec.normalizePersons(persons);
    const next: WaterState = state.copy();
    const room: WaterRoomState = next.rooms.has(key) ? next.rooms.get(key) as WaterRoomState : new WaterRoomState();
    room.persons = safePersons;
    next.rooms.set(key, room);
    return next;
  }

  /** 删除单间宿舍水量数据。 */
  static clearRoom(state: WaterState, roomVerify: string): WaterState {
    const key: string = roomVerify.trim();
    if (!state.rooms.has(key)) {
      return state;
    }
    const next: WaterState = state.copy();
    next.rooms.delete(key);
    return next;
  }

  /** 当前月份（供 UI 默认值）。 */
  static currentMonth(nowMillis: number): string {
    return WaterMonth.current(nowMillis);
  }
}
