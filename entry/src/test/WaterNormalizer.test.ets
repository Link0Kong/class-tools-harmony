import { describe, it, expect } from '@ohos/hypium';
import { WaterNormalizer } from '../main/ets/data/sync/WaterNormalizer';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';

function sectionWithRooms(rooms: Blob): Blob {
  const section: Blob = { 'rooms': rooms };
  return section;
}

function room(persons: number, recs: Object[]): Blob {
  const value: Blob = { 'p': persons, 'recs': recs };
  return value;
}

function rec(month: string, reading: number, ts: number): Blob {
  const value: Blob = { 'm': month, 'r': reading, 'ts': ts };
  return value;
}

export default function waterNormalizerTest() {
  describe('WaterNormalizer', () => {
    it('keeps_valid_rooms_and_drops_bad_ones', 0, () => {
      const rooms: Blob = {};
      rooms['1-16---305'] = room(6, [rec('2026-09', 80, 1), rec('2026-10', 93.555, 2)]);
      rooms[''] = room(4, []);
      rooms['bad'] = 'not-an-object';
      const out: Blob = WaterNormalizer.normalize(sectionWithRooms(rooms));
      const outRooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(out, 'rooms'));
      expect(outRooms !== undefined).assertTrue();
      if (outRooms !== undefined) {
        expect(JsonBlob.keys(outRooms).length).assertEqual(1);
        const kept: Blob | undefined = JsonBlob.asBlob(outRooms['1-16---305']);
        expect(kept !== undefined).assertTrue();
        if (kept !== undefined) {
          expect(JsonBlob.asNumber(JsonBlob.get(kept, 'p'), 0)).assertEqual(6);
          const recs: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(kept, 'recs'));
          expect(recs !== undefined).assertTrue();
          if (recs !== undefined) {
            expect(recs.length).assertEqual(2);
            const second: Blob | undefined = JsonBlob.asBlob(recs[1]);
            expect(JsonBlob.asNumber(JsonBlob.get(second, 'r'), 0)).assertEqual(93.56);
          }
        }
      }
    });

    it('persons_defaults_to_4_unless_6', 0, () => {
      const rooms: Blob = {};
      rooms['a'] = room(5, []);
      rooms['b'] = room(6, []);
      const out: Blob = WaterNormalizer.normalize(sectionWithRooms(rooms));
      const outRooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(out, 'rooms'));
      if (outRooms !== undefined) {
        const a: Blob | undefined = JsonBlob.asBlob(outRooms['a']);
        const b: Blob | undefined = JsonBlob.asBlob(outRooms['b']);
        expect(JsonBlob.asNumber(JsonBlob.get(a, 'p'), 0)).assertEqual(4);
        expect(JsonBlob.asNumber(JsonBlob.get(b, 'p'), 0)).assertEqual(6);
      }
    });

    it('records_sorted_by_month_and_deduped', 0, () => {
      const recs: Object[] = [
        rec('2026-11', 100, 3),
        rec('2026-09', 80, 1),
        rec('2026-11', 101, 4),
        rec('2026-13', 5, 5),
        rec('bad-month', 5, 6),
        rec('2026-10', -1, 7)
      ];
      const normalized: Object[] = WaterNormalizer.normalizeRecords(recs);
      expect(normalized.length).assertEqual(2);
      const first: Blob | undefined = JsonBlob.asBlob(normalized[0]);
      const second: Blob | undefined = JsonBlob.asBlob(normalized[1]);
      expect(JsonBlob.asString(JsonBlob.get(first, 'm'), '')).assertEqual('2026-09');
      expect(JsonBlob.asString(JsonBlob.get(second, 'm'), '')).assertEqual('2026-11');
      expect(JsonBlob.asNumber(JsonBlob.get(second, 'r'), 0)).assertEqual(101);
    });

    it('integer_readings_stay_integers', 0, () => {
      const normalized: Object[] = WaterNormalizer.normalizeRecords([rec('2026-09', 80, 1)]);
      const row: Blob | undefined = JsonBlob.asBlob(normalized[0]);
      const value: JsonValue | undefined = JsonBlob.get(row, 'r');
      expect(typeof value).assertEqual('number');
      expect(JsonBlob.asNumber(value, 0)).assertEqual(80);
      // 必须是整数形态（80 而非 80.0），保证跨端字节稳定
      expect(String(value)).assertEqual('80');
    });

    it('caps_records_to_120_keeping_latest_months', 0, () => {
      const recs: Object[] = [];
      for (let i = 1; i <= 130; i++) {
        const year: number = 2000 + Math.floor((i - 1) / 12);
        const month: number = ((i - 1) % 12) + 1;
        const mm: string = (month < 10 ? '0' : '') + month;
        recs.push(rec(year + '-' + mm, i, i));
      }
      const normalized: Object[] = WaterNormalizer.normalizeRecords(recs);
      expect(normalized.length).assertEqual(120);
      const last: Blob | undefined = JsonBlob.asBlob(normalized[normalized.length - 1]);
      expect(JsonBlob.asString(JsonBlob.get(last, 'm'), '')).assertEqual('2010-10');
    });

    it('empty_section_becomes_empty_rooms', 0, () => {
      const out: Blob = WaterNormalizer.normalize(undefined);
      const outRooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(out, 'rooms'));
      expect(outRooms !== undefined).assertTrue();
      if (outRooms !== undefined) {
        expect(JsonBlob.keys(outRooms).length).assertEqual(0);
      }
    });
  });
}
