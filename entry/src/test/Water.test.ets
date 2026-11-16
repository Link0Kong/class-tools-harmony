import { describe, it, expect } from '@ohos/hypium';
import {
  WaterRecord,
  WaterRecordReview,
  WaterRoomState,
  WaterRules,
  WaterState
} from '../main/ets/features/water/WaterModels';
import { WaterCodec } from '../main/ets/features/water/WaterCodec';
import { WaterCalculator } from '../main/ets/features/water/WaterCalculator';
import { WaterMonth } from '../main/ets/features/water/WaterMonth';
import { WaterMutator } from '../main/ets/features/water/WaterMutator';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';

const ROOM: string = '4-23A---321';

function record(month: string, reading: number): WaterRecord {
  const r: WaterRecord = new WaterRecord();
  r.month = month;
  r.reading = reading;
  r.ts = 1;
  return r;
}

function roomWith(persons: number, records: WaterRecord[]): WaterRoomState {
  const room: WaterRoomState = new WaterRoomState();
  room.persons = persons;
  room.records = records;
  return room;
}

function stateWith(room: WaterRoomState): WaterState {
  const state: WaterState = new WaterState();
  state.rooms.set(ROOM, room);
  return state;
}

function parseJson(text: string): Blob {
  return JSON.parse(text) as Blob;
}

export default function waterTest() {
  describe('WaterCodec', () => {
    it('parses_tolerant_section', 0, () => {
      const raw: Blob = parseJson('{"rooms":{"4-23A---321":{"p":7,"recs":['
        + '{"m":"2026-10","r":120.456,"ts":11},'
        + '{"m":"2026-09","r":100,"ts":10},'
        + '{"m":"2026-09","r":101,"ts":12},'
        + '{"m":"bad","r":5},'
        + '{"m":"2026-11","r":-3}]}}}');
      const state: WaterState = WaterCodec.fromJson(raw);
      const room: WaterRoomState = state.roomOrDefault(ROOM);
      expect(room.persons).assertEqual(WaterRules.PERSONS_DEFAULT);
      expect(room.records.length).assertEqual(2);
      expect(room.records[0].month).assertEqual('2026-09');
      expect(room.records[0].reading).assertEqual(101);
      expect(room.records[1].reading).assertEqual(120.46);
    });

    it('empty_and_bad_sections', 0, () => {
      expect(WaterCodec.fromJson(undefined).rooms.size).assertEqual(0);
      const empty: Blob = {};
      expect(WaterCodec.fromJson(empty).rooms.size).assertEqual(0);
      const bad: Blob = parseJson('{"rooms":"x"}');
      expect(WaterCodec.fromJson(bad).rooms.size).assertEqual(0);
    });

    it('to_json_key_order_and_integer_reading', 0, () => {
      const state: WaterState = stateWith(roomWith(6, [record('2026-11', 130.1), record('2026-10', 120)]));
      const blob: Blob = WaterCodec.toJson(state);
      expect(JsonBlob.keys(blob).join(',')).assertEqual('rooms');
      const rooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'rooms'));
      expect(JsonBlob.keys(rooms).join(',')).assertEqual(ROOM);
      const roomBlob: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(rooms, ROOM));
      expect(JsonBlob.keys(roomBlob).join(',')).assertEqual('p,recs');
      const recs: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(roomBlob, 'recs'));
      expect(recs !== undefined && recs.length === 2).assertTrue();
      if (recs !== undefined) {
        const first: Blob | undefined = JsonBlob.asBlob(recs[0]);
        expect(JsonBlob.keys(first).join(',')).assertEqual('m,r,ts');
        expect(JsonBlob.asNumber(JsonBlob.get(first, 'r'), 0)).assertEqual(120);
      }
    });

    it('roundtrip_preserves_values', 0, () => {
      const state: WaterState = stateWith(roomWith(4, [record('2026-10', 100.5), record('2026-11', 112.25)]));
      const back: WaterState = WaterCodec.fromJson(WaterCodec.toJson(state));
      const room: WaterRoomState = back.roomOrDefault(ROOM);
      expect(room.persons).assertEqual(4);
      expect(room.records.length).assertEqual(2);
      expect(room.records[1].reading).assertEqual(112.25);
    });

    it('normalizes_helpers', 0, () => {
      expect(WaterCodec.normalizePersons(6)).assertEqual(6);
      expect(WaterCodec.normalizePersons(5)).assertEqual(4);
      expect(WaterCodec.normalizeMonth(' 2026-11 ')).assertEqual('2026-11');
      expect(WaterCodec.normalizeMonth('2026-13') === undefined).assertTrue();
      expect(WaterCodec.round2(12.345)).assertEqual(12.35);
      expect(WaterCodec.round1(23.45)).assertEqual(23.5);
    });
  });

  describe('WaterMonth', () => {
    it('current_and_shift', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      expect(WaterMonth.current(now)).assertEqual('2026-11');
      expect(WaterMonth.shift('2026-11', -1)).assertEqual('2026-10');
      expect(WaterMonth.shift('2026-01', -1)).assertEqual('2025-12');
      expect(WaterMonth.shift('2026-12', 1)).assertEqual('2027-01');
    });

    it('elapsed_days', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      expect(WaterMonth.elapsedDays('2026-11', now)).assertEqual(14);
      expect(WaterMonth.elapsedDays('2026-10', now)).assertEqual(31);
      expect(WaterMonth.elapsedDays('2026-12', now)).assertEqual(1);
      expect(WaterMonth.daysInMonth('2026-02')).assertEqual(28);
      expect(WaterMonth.daysInMonth('2024-02')).assertEqual(29);
    });
  });

  describe('WaterCalculator', () => {
    it('charge_uses_previous_month', 0, () => {
      const room: WaterRoomState = roomWith(4, [record('2026-10', 100), record('2026-11', 112.5)]);
      const charge = WaterCalculator.charge(room, room.records[1], 4);
      expect(charge.hasPrevious).assertTrue();
      expect(charge.usage).assertEqual(12.5);
      expect(charge.free).assertEqual(8);
      expect(charge.excess).assertEqual(4.5);
      expect(charge.fee).assertEqual(13.64);
      expect(charge.degree).assertEqual(23.5);
      expect(charge.within).assertFalse();
    });

    it('within_free_quota', 0, () => {
      const room: WaterRoomState = roomWith(4, [record('2026-10', 100), record('2026-11', 106)]);
      const charge = WaterCalculator.charge(room, room.records[1], 4);
      expect(charge.usage).assertEqual(6);
      expect(charge.excess).assertEqual(0);
      expect(charge.fee).assertEqual(0);
      expect(charge.within).assertTrue();
    });

    it('first_record_has_no_usage', 0, () => {
      const room: WaterRoomState = roomWith(4, [record('2026-10', 100)]);
      const charge = WaterCalculator.charge(room, room.records[0], 4);
      expect(charge.hasPrevious).assertFalse();
      expect(charge.hasUsage).assertFalse();
      expect(charge.free).assertEqual(8);
      expect(WaterCalculator.fmtReading(charge.usage, charge.hasUsage)).assertEqual('—');
      expect(WaterCalculator.fmtDegree(charge.degree, charge.hasUsage)).assertEqual('—');
    });

    it('stats_with_daily_and_delta', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      const room: WaterRoomState = roomWith(4, [
        record('2026-09', 80), record('2026-10', 100), record('2026-11', 112)
      ]);
      const stats = WaterCalculator.stats(room, '2026-11', now);
      expect(stats.charge.usage).assertEqual(12);
      expect(stats.hasDailyAverage).assertTrue();
      expect(stats.dailyAverage).assertEqual(WaterCodec.round2(12 / 14));
      expect(stats.hasPreviousMonthUsage).assertTrue();
      expect(stats.previousMonthUsage).assertEqual(20);
      expect(stats.hasDelta).assertTrue();
      expect(stats.deltaVsPreviousMonth).assertEqual(-8);
    });

    it('rule_lines', 0, () => {
      const lines: string[][] = WaterCalculator.ruleLines(6);
      expect(lines.length).assertEqual(4);
      expect(lines[0][1].indexOf('3.03') === 0).assertTrue();
      expect(lines[1][1].indexOf('2 吨/人/月 × 6 人 = 12.0 吨') >= 0).assertTrue();
    });
  });

  describe('WaterMutator', () => {
    it('review_rejects_bad_input', 0, () => {
      const room: WaterRoomState = roomWith(4, []);
      expect(WaterMutator.review(room, '2026-11', 'abc', 1).valid).assertFalse();
      expect(WaterMutator.review(room, '2026-13', '10', 1).valid).assertFalse();
      expect(WaterMutator.review(room, '2026-11', '-1', 1).valid).assertFalse();
      expect(WaterMutator.review(room, '2026-11', '', 1).message.length > 0).assertTrue();
    });

    it('review_enforces_monotonic_readings', 0, () => {
      const room: WaterRoomState = roomWith(4, [record('2026-10', 100), record('2026-12', 130)]);
      expect(WaterMutator.review(room, '2026-11', '99', 1).valid).assertFalse();
      expect(WaterMutator.review(room, '2026-11', '131', 1).valid).assertFalse();
      const ok: WaterRecordReview = WaterMutator.review(room, '2026-11', '110.555', 1);
      expect(ok.valid).assertTrue();
      if (ok.record !== undefined) {
        expect(ok.record.reading).assertEqual(110.56);
        expect(ok.record.month).assertEqual('2026-11');
      }
    });

    it('review_detects_replace_existing', 0, () => {
      const room: WaterRoomState = roomWith(4, [record('2026-11', 110)]);
      const review: WaterRecordReview = WaterMutator.review(room, '2026-11', '115', 1);
      expect(review.valid).assertTrue();
      expect(review.replaceExisting).assertTrue();
    });

    it('put_sorts_and_overwrites', 0, () => {
      let state: WaterState = stateWith(roomWith(4, [record('2026-10', 100)]));
      const rec: WaterRecord = record('2026-09', 90);
      state = WaterMutator.put(state, ROOM, rec);
      state = WaterMutator.put(state, ROOM, record('2026-11', 120));
      state = WaterMutator.put(state, ROOM, record('2026-10', 105));
      const room: WaterRoomState = state.roomOrDefault(ROOM);
      expect(room.records.length).assertEqual(3);
      expect(room.records[0].month).assertEqual('2026-09');
      expect(room.records[1].reading).assertEqual(105);
      expect(room.records[2].month).assertEqual('2026-11');
    });

    it('delete_and_persons_and_clear', 0, () => {
      let state: WaterState = stateWith(roomWith(4, [record('2026-10', 100), record('2026-11', 110)]));
      state = WaterMutator.delete(state, ROOM, '2026-10');
      expect(state.roomOrDefault(ROOM).records.length).assertEqual(1);
      state = WaterMutator.withPersons(state, ROOM, 6);
      expect(state.roomOrDefault(ROOM).persons).assertEqual(6);
      state = WaterMutator.clearRoom(state, ROOM);
      expect(state.rooms.size).assertEqual(0);
      expect(state.room(ROOM) === undefined).assertTrue();
    });

    it('unknown_room_delete_noop', 0, () => {
      const state: WaterState = stateWith(roomWith(4, [record('2026-10', 100)]));
      expect(WaterMutator.delete(state, 'nope', '2026-10') === state).assertTrue();
      expect(WaterMutator.clearRoom(state, 'nope') === state).assertTrue();
    });
  });
}
