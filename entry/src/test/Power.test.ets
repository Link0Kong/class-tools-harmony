import { describe, it, expect } from '@ohos/hypium';
import {
  PowerPoint,
  PowerCompare,
  SlowEstimate,
  PowerEstimate,
  PowerRange,
  PowerRangeKey,
  PowerRooms,
  PowerStats,
  RoomInfo
} from '../main/ets/data/power/PowerModels';
import { PowerRepository, PowerHistoryResult, PowerRowResult } from '../main/ets/data/power/PowerRepository';
import { RangeStats } from '../main/ets/data/power/PowerModels';
import { PowerPrefs, PowerPrefsData } from '../main/ets/data/power/PowerPrefs';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';
import { FakeApi } from './support/FakeApi';

function point(q: number, t: number): PowerPoint {
  const p: PowerPoint = new PowerPoint();
  p.q = q;
  p.t = t;
  return p;
}

const HOUR: number = 60 * 60 * 1000;

export default function powerTest() {
  describe('PowerRooms', () => {
    it('catalog_is_17_rooms', 0, () => {
      expect(PowerRooms.ROOMS.length).assertEqual(17);
      expect(PowerRooms.BUILDINGS.length).assertEqual(4);
      expect(PowerRooms.labelOf('4-23A---321')).assertEqual('23号楼A座321');
      expect(PowerRooms.buildingOf('4-23A---321')).assertEqual('23号楼A座');
    });

    it('normalize_rejects_unknown', 0, () => {
      expect(PowerRooms.normalizeSel(' 4-23A---321 ')).assertEqual('4-23A---321');
      expect(PowerRooms.normalizeSel('bogus')).assertEqual('');
      expect(PowerRooms.normalizeSel('')).assertEqual('');
    });

    it('rooms_by_building_and_rv', 0, () => {
      expect(PowerRooms.roomsOfBuilding('23号楼B座').length).assertEqual(4);
      expect(PowerRooms.rvOf('23号楼B座', '422')).assertEqual('4-23B---422');
      expect(PowerRooms.rvOf('23号楼B座', '999')).assertEqual('');
    });

    it('slow_buildings_13_16', 0, () => {
      expect(PowerRooms.isSlowBuilding('13号楼')).assertTrue();
      expect(PowerRooms.isSlowBuilding('16号楼')).assertTrue();
      expect(PowerRooms.isSlowBuilding('23号楼A座')).assertFalse();
    });
  });

  describe('PowerStats', () => {
    it('derive_range_with_baseline', 0, () => {
      const now: number = 100 * HOUR;
      const points: PowerPoint[] = [
        point(50, now - 30 * HOUR), // 窗口外基线
        point(48, now - 20 * HOUR),
        point(40, now - 2 * HOUR),
        point(38, now - 1 * HOUR)
      ];
      const stats = PowerStats.deriveRange(points, PowerRange.H24, now);
      expect(stats.n).assertEqual(3);
      expect(stats.start).assertEqual(50);
      expect(stats.end).assertEqual(38);
      expect(stats.drop).assertEqual(12);
      expect(stats.valid).assertTrue();
      expect(Math.round(stats.hours)).assertEqual(29);
      expect(PowerStats.round2(stats.perDay)).assertEqual(PowerStats.round2(12 / 29 * 24));
    });

    it('insufficient_samples_invalid', 0, () => {
      const now: number = 100 * HOUR;
      const one: PowerPoint[] = [point(30, now - HOUR)];
      const stats = PowerStats.deriveRange(one, PowerRange.H24, now);
      expect(stats.valid).assertFalse();
      expect(stats.drop).assertEqual(0);
      expect(PowerStats.deriveRange([], PowerRange.H24, now).n).assertEqual(0);
    });

    it('recharge_jump_is_excluded_from_drop', 0, () => {
      const now: number = 100 * HOUR;
      const jump: PowerPoint[] = [point(5, now - 3 * HOUR), point(60, now - HOUR)];
      const stats = PowerStats.deriveRange(jump, PowerRange.H24, now);
      expect(stats.drop).assertEqual(0);
      expect(stats.end).assertEqual(60);
      // 充值前 20→10 用掉 10，充值到 80 后 80→70 再用 10 → 合计 20
      const mixed: PowerPoint[] = [point(20, now - 6 * HOUR), point(10, now - 5 * HOUR),
        point(80, now - 4 * HOUR), point(70, now - 2 * HOUR)];
      const mixedStats = PowerStats.deriveRange(mixed, PowerRange.H24, now);
      expect(mixedStats.drop).assertEqual(20);
      expect(mixedStats.end).assertEqual(70);
    });

    it('window_points_include_baseline', 0, () => {
      const now: number = 100 * HOUR;
      const points: PowerPoint[] = [point(50, now - 30 * HOUR), point(45, now - 2 * HOUR)];
      const view: PowerPoint[] = PowerStats.windowPoints(points, PowerRange.H24, now);
      expect(view.length).assertEqual(2);
      expect(view[0].q).assertEqual(50);
    });

    it('downsample_keeps_ends', 0, () => {
      const points: PowerPoint[] = [];
      for (let i = 0; i < 100; i++) {
        points.push(point(100 - i, i * HOUR));
      }
      const out: PowerPoint[] = PowerStats.downsample(points, 10);
      expect(out.length).assertEqual(10);
      expect(out[0].q).assertEqual(100);
      expect(out[9].q).assertEqual(1);
    });

    it('derive_window_and_compare', 0, () => {
      const now: number = new Date(2026, 10, 15, 12, 0).getTime();
      const todayStart: number = new Date(2026, 10, 15, 0, 0).getTime();
      const yStart: number = new Date(2026, 10, 14, 0, 0).getTime();
      const points: PowerPoint[] = [
        point(100, yStart), point(90, yStart + 6 * HOUR), point(80, yStart + 12 * HOUR),
        point(70, todayStart), point(65, todayStart + 6 * HOUR), point(60, todayStart + 12 * HOUR)
      ];
      const window: RangeStats = PowerStats.deriveWindow(points, todayStart, now);
      expect(window.drop).assertEqual(10);
      expect(window.valid).assertTrue();
      const compare: PowerCompare = PowerStats.compare(points, PowerRange.H24, now);
      expect(compare.label).assertEqual('较昨日同期');
      expect(compare.valid).assertTrue();
      expect(compare.currentDrop).assertEqual(10);
      expect(compare.previousDrop).assertEqual(20);
      expect(compare.deltaPct).assertEqual(-50);
    });

    it('compare_invalid_without_history', 0, () => {
      const now: number = new Date(2026, 10, 15, 12, 0).getTime();
      const todayStart: number = new Date(2026, 10, 15, 0, 0).getTime();
      const points: PowerPoint[] = [point(70, todayStart), point(60, todayStart + 12 * HOUR)];
      const compare: PowerCompare = PowerStats.compare(points, PowerRange.H24, now);
      expect(compare.valid).assertFalse();
      expect(compare.label).assertEqual('较昨日同期');
    });

    it('cursor_hit_nearest', 0, () => {
      const points: PowerPoint[] = [point(10, 0), point(9, 1000), point(8, 2000)];
      expect(PowerStats.cursorIndex(points, 0)).assertEqual(0);
      expect(PowerStats.cursorIndex(points, 0.5)).assertEqual(1);
      expect(PowerStats.cursorIndex(points, 1)).assertEqual(2);
      expect(PowerStats.cursorIndex([], 0.3)).assertEqual(-1);
    });

    it('estimate_and_deducts', 0, () => {
      const t0: number = new Date(2026, 10, 1).getTime();
      const normal: PowerPoint[] = [point(10, t0), point(8, t0 + 24 * HOUR), point(6, t0 + 48 * HOUR)];
      const est: PowerEstimate = PowerStats.estimate(normal);
      expect(est.valid).assertTrue();
      expect(est.ratePerDay).assertEqual(2);
      expect(est.deductCount).assertEqual(0);
      expect(PowerStats.daysLeft(10, 2)).assertEqual(5);
      expect(PowerStats.daysLeft(10, 3)).assertEqual(3.3);
      expect(PowerStats.daysLeft(10, 0)).assertEqual(0);
      const withDeduct: PowerPoint[] = [point(30, t0), point(28, t0 + 24 * HOUR), point(12, t0 + 25 * HOUR)];
      const est2: PowerEstimate = PowerStats.estimate(withDeduct);
      expect(est2.deductCount).assertEqual(1);
      expect(est2.deductDeg).assertEqual(16);
    });

    it('detects_recharges', 0, () => {
      const pts: PowerPoint[] = [point(10, 0), point(20, 1000), point(19, 2000), point(30, 3000)];
      const last: PowerPoint | undefined = PowerStats.lastRecharge(pts);
      expect(last !== undefined).assertTrue();
      if (last !== undefined) {
        expect(last.q).assertEqual(30);
        expect(last.t).assertEqual(3000);
      }
      expect(PowerStats.lastRecharge([point(10, 0), point(9, 1)]) === undefined).assertTrue();
      const points: PowerPoint[] = [point(10, 0), point(9, 1000), point(20, 2000), point(19, 3000)];
      const rises: PowerPoint[] = PowerStats.recharges(points);
      expect(rises.length).assertEqual(1);
      expect(rises[0].q).assertEqual(20);
      expect(PowerStats.recharges([point(10, 0), point(10.01, 1)]).length).assertEqual(0);
    });

    it('slow_estimate_segments', 0, () => {
      const t0: number = new Date(2026, 10, 1).getTime();
      const two: PowerPoint[] = [point(10, t0), point(8, t0 + 24 * HOUR), point(6, t0 + 48 * HOUR)];
      const estimate: SlowEstimate = PowerStats.slowEstimate(two);
      expect(estimate.valid).assertTrue();
      expect(estimate.segments).assertEqual(2);
      expect(estimate.perDay).assertEqual(2);
      expect(estimate.ref).assertFalse();
      const one: PowerPoint[] = [point(10, t0), point(7, t0 + 24 * HOUR)];
      const single: SlowEstimate = PowerStats.slowEstimate(one);
      expect(single.valid).assertTrue();
      expect(single.segments).assertEqual(1);
      expect(single.perDay).assertEqual(3);
      expect(single.ref).assertTrue();
      expect(PowerStats.slowEstimate([]).valid).assertFalse();
    });

    it('formats', 0, () => {
      expect(PowerStats.fmtMain(12.345, true)).assertEqual('12.35');
      expect(PowerStats.fmtMain(0, false)).assertEqual('—');
      expect(PowerStats.fmtDrop(3.2, true)).assertEqual('3.20');
      expect(PowerStats.fmtDrop(3.2, false)).assertEqual('—');
      expect(PowerStats.fmtRate(1.234, true)).assertEqual('1.2');
    });

    it('low_normalization', 0, () => {
      expect(PowerStats.normalizeLow(40)).assertEqual(40);
      expect(PowerStats.normalizeLow(37)).assertEqual(30);
      expect(PowerStats.normalizeLow(0)).assertEqual(30);
      expect(PowerStats.defaultLow()).assertEqual(30);
    });

    it('range_from_key', 0, () => {
      expect(PowerRange.fromKey('24h').key).assertEqual(PowerRangeKey.H24);
      expect(PowerRange.fromKey('30d').windowMs).assertEqual(30 * 24 * HOUR);
      expect(PowerRange.fromKey('x').key).assertEqual(PowerRangeKey.H24);
    });
  });

  describe('PowerPrefs', () => {
    it('read_defaults_and_normalize', 0, () => {
      const empty: Blob = {};
      expect(PowerPrefs.read(empty).sel).assertEqual('');
      expect(PowerPrefs.read(empty).low).assertEqual(30);
      const section: Blob = { 'sel': '4-23A---321', 'at': 5, 'low': 50 };
      const sections: Blob = { 'power': section };
      const data: PowerPrefsData = PowerPrefs.read(sections);
      expect(data.sel).assertEqual('4-23A---321');
      expect(data.low).assertEqual(50);
      const bad: Blob = { 'sel': 'nope', 'low': 37 };
      const badSections: Blob = { 'power': bad };
      expect(PowerPrefs.read(badSections).sel).assertEqual('');
      expect(PowerPrefs.read(badSections).low).assertEqual(30);
    });

    it('write_preserves_other_keys', 0, () => {
      const draw: Blob = { 'count': 3 };
      const current: Blob = { 'v': 6, 'draw': draw };
      const next: Blob = PowerPrefs.write(current, '4-23B---422', 40, 1234);
      expect(JsonBlob.keys(next).join(',')).assertEqual('v,draw,power');
      const power: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(next, 'power'));
      expect(JsonBlob.asString(JsonBlob.get(power, 'sel'), '')).assertEqual('4-23B---422');
      expect(JsonBlob.asNumber(JsonBlob.get(power, 'low'), 0)).assertEqual(40);
      expect(JsonBlob.asNumber(JsonBlob.get(power, 'at'), 0)).assertEqual(1234);
    });

    it('is_low_respects_value', 0, () => {
      expect(PowerPrefs.isLow(20, true, 30)).assertTrue();
      expect(PowerPrefs.isLow(40, true, 30)).assertFalse();
      expect(PowerPrefs.isLow(0, false, 30)).assertFalse();
    });
  });

  describe('PowerRepository', () => {
    it('parses_row', 0, () => {
      const row = PowerRepository.parseRow('[{"id":"4-23A---321","label":"23号楼A座321","building":"23号楼A座",'
        + '"room":"321","quantity":42.5,"unit":"度","low":false,"updated_at":"2026-11-14T12:00:00+08:00"}]');
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row.q).assertEqual(42.5);
        expect(row.hasValue).assertTrue();
        expect(row.unit).assertEqual('度');
        expect(row.updatedAt.indexOf('2026-11-14') === 0).assertTrue();
      }
      const textQty = PowerRepository.parseRow('[{"id":"x","quantity":"12.25"}]');
      expect(textQty !== undefined && textQty.q === 12.25).assertTrue();
      const bad = PowerRepository.parseRow('[{"id":"x","quantity":"n/a"}]');
      expect(bad !== undefined && !bad.hasValue).assertTrue();
      expect(PowerRepository.parseRow('[]') === undefined).assertTrue();
      expect(PowerRepository.parseRow('bad') === undefined).assertTrue();
    });

    it('parses_history_iso_and_epoch', 0, () => {
      const iso: string = '[{"ts":"2026-11-14T10:00:00+08:00","quantity":30.5},'
        + '{"ts":"2026-11-14T09:00:00+08:00","quantity":31}]';
      const points: PowerPoint[] = PowerRepository.parseHistory(iso);
      expect(points.length).assertEqual(2);
      expect(points[0].q).assertEqual(31);
      expect(points[0].t < points[1].t).assertTrue();
      const epoch: string = '[{"ts":1763000000,"quantity":20}]';
      expect(PowerRepository.parseHistory(epoch)[0].t).assertEqual(1763000000000);
      expect(PowerRepository.parseHistory('[]').length).assertEqual(0);
    });

    it('loads_row_and_history_with_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.powerBody = '[{"id":"4-23A---321","quantity":33.3,"unit":"度","updated_at":"2026-11-14T12:00:00+08:00"}]';
      api.powerHistoryBody = '[{"ts":"2026-11-14T11:00:00+08:00","quantity":34},'
        + '{"ts":"2026-11-14T12:00:00+08:00","quantity":33.3}]';
      let now: number = 1000000;
      const repo: PowerRepository = new PowerRepository(api, () => now);
      const row: PowerRowResult = await repo.loadRow('4-23A---321', false);
      expect(row.ok).assertTrue();
      expect(row.row !== undefined && row.row.q === 33.3).assertTrue();
      expect(api.getPaths[0].indexOf('id=eq.4-23A---321') > 0).assertTrue();
      const history: PowerHistoryResult = await repo.loadHistory('4-23A---321', PowerRange.D7, false);
      expect(history.points.length).assertEqual(2);
      expect(api.getPaths[1].indexOf('roomverify=eq.4-23A---321') > 0).assertTrue();
      expect(api.getPaths[1].indexOf('order=ts.asc') > 0).assertTrue();
      expect(api.getPaths[1].indexOf('limit=2000') > 0).assertTrue();
      const cachedRow: PowerRowResult = await repo.loadRow('4-23A---321', false);
      expect(cachedRow.fromCache).assertTrue();
      expect(api.getPaths.length).assertEqual(2);
      now = 1000000 + 4 * 60 * 1000;
      const cachedHistory: PowerHistoryResult = await repo.loadHistory('4-23A---321', PowerRange.D7, false);
      expect(cachedHistory.fromCache).assertTrue();
      expect(api.getPaths.length).assertEqual(2);
    });

    it('failure_falls_back_to_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.powerBody = '[{"id":"4-23A---321","quantity":10}]';
      let now: number = 0;
      const repo: PowerRepository = new PowerRepository(api, () => now);
      await repo.loadRow('4-23A---321', false);
      now = 10 * 60 * 1000;
      api.failGets = true;
      const fallback: PowerRowResult = await repo.loadRow('4-23A---321', true);
      expect(fallback.ok).assertTrue();
      expect(fallback.fromCache).assertTrue();
      expect(fallback.row !== undefined && fallback.row.q === 10).assertTrue();
    });
  });
}
