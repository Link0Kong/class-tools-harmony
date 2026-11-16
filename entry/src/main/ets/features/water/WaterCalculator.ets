import {
  WaterCharge,
  WaterMonthStats,
  WaterRecord,
  WaterRoomState,
  WaterRules
} from './WaterModels';
import { WaterCodec } from './WaterCodec';
import { WaterMonth } from './WaterMonth';

/**
 * 水量计算（纯函数，契约 `_water_contract.md` §0/§7）：
 * - 本期用量 = 本次读数 − 该宿舍月份升序的上一条读数；
 * - 水费 = `max(0, 用量 − 2×人数) × 3.03`（2 位）；
 * - 折合扣电 = `水费 ÷ 0.58`（1 位）；
 * - 无上一条 → 首次记录（用量/水费/扣电均无，不伪造 0）。
 */
export class WaterCalculator {
  static freeWater(persons: number): number {
    return WaterRules.WATER_FREE_PER_PERSON * WaterCodec.normalizePersons(persons);
  }

  static freeElec(persons: number): number {
    return WaterRules.ELEC_FREE_PER_PERSON * WaterCodec.normalizePersons(persons);
  }

  /** 同宿舍、月份升序的上一条记录（不含 month 本身）。 */
  static previousRecord(room: WaterRoomState, month: string): WaterRecord | undefined {
    let found: WaterRecord | undefined = undefined;
    for (let i = 0; i < room.records.length; i++) {
      const record: WaterRecord = room.records[i];
      if (record.month < month && (found === undefined || record.month > found.month)) {
        found = record;
      }
    }
    return found;
  }

  /** 同宿舍的下一条记录（用于录入校验）。 */
  static nextRecord(room: WaterRoomState, month: string): WaterRecord | undefined {
    let found: WaterRecord | undefined = undefined;
    for (let i = 0; i < room.records.length; i++) {
      const record: WaterRecord = room.records[i];
      if (record.month > month && (found === undefined || record.month < found.month)) {
        found = record;
      }
    }
    return found;
  }

  static recordOf(room: WaterRoomState, month: string): WaterRecord | undefined {
    for (let i = 0; i < room.records.length; i++) {
      if (room.records[i].month === month) {
        return room.records[i];
      }
    }
    return undefined;
  }

  /** 某条记录的用量/水费/折合扣电。 */
  static charge(room: WaterRoomState, record: WaterRecord, personsOverride: number): WaterCharge {
    const charge: WaterCharge = new WaterCharge();
    const persons: number = WaterCodec.normalizePersons(personsOverride);
    charge.free = WaterCalculator.freeWater(persons);
    const previous: WaterRecord | undefined = WaterCalculator.previousRecord(room, record.month);
    if (previous === undefined) {
      return charge;
    }
    charge.hasPrevious = true;
    charge.hasUsage = true;
    charge.usage = WaterCodec.round2(Math.max(0, record.reading - previous.reading));
    charge.excess = WaterCodec.round2(Math.max(0, charge.usage - charge.free));
    charge.fee = WaterCodec.round2(charge.excess * WaterRules.WATER_PRICE);
    charge.degree = WaterCodec.round1(charge.fee / WaterRules.ELEC_PRICE);
    charge.within = charge.excess <= 0.001;
    return charge;
  }

  /** 某个月份的统计卡数据。 */
  static stats(room: WaterRoomState, month: string, nowMillis: number): WaterMonthStats {
    const stats: WaterMonthStats = new WaterMonthStats();
    const safeMonth: string | undefined = WaterCodec.normalizeMonth(month);
    stats.month = safeMonth !== undefined ? safeMonth : WaterMonth.current(nowMillis);
    stats.persons = WaterCodec.normalizePersons(room.persons);
    stats.record = WaterCalculator.recordOf(room, stats.month);
    stats.previous = WaterCalculator.previousRecord(room, stats.month);
    if (stats.record !== undefined) {
      stats.charge = WaterCalculator.charge(room, stats.record, stats.persons);
    } else {
      const charge: WaterCharge = new WaterCharge();
      charge.free = WaterCalculator.freeWater(stats.persons);
      charge.hasPrevious = stats.previous !== undefined;
      stats.charge = charge;
    }
    if (stats.charge.hasUsage) {
      const days: number = Math.max(1, WaterMonth.elapsedDays(stats.month, nowMillis));
      stats.dailyAverage = WaterCodec.round2(stats.charge.usage / days);
      stats.hasDailyAverage = true;
    }
    const previousMonth: string = WaterMonth.shift(stats.month, -1);
    const previousMonthRecord: WaterRecord | undefined = WaterCalculator.recordOf(room, previousMonth);
    if (previousMonthRecord !== undefined) {
      const previousCharge: WaterCharge = WaterCalculator.charge(room, previousMonthRecord, stats.persons);
      if (previousCharge.hasUsage) {
        stats.previousMonthUsage = previousCharge.usage;
        stats.hasPreviousMonthUsage = true;
      }
    }
    if (stats.charge.hasUsage && stats.hasPreviousMonthUsage) {
      stats.deltaVsPreviousMonth = WaterCodec.round2(stats.charge.usage - stats.previousMonthUsage);
      stats.hasDelta = true;
    }
    return stats;
  }

  static fmtReading(value: number, hasValue: boolean): string {
    return hasValue ? value.toFixed(2) : '—';
  }

  static fmtMoney(value: number, hasValue: boolean): string {
    return hasValue ? value.toFixed(2) : '—';
  }

  static fmtDegree(value: number, hasValue: boolean): string {
    return hasValue ? value.toFixed(1) : '—';
  }

  /** 规则卡文案（与网页一致）。 */
  static ruleLines(persons: number): string[][] {
    const safe: number = WaterCodec.normalizePersons(persons);
    const quota: number = WaterCalculator.freeWater(safe);
    const lines: string[][] = [
      ['水价', WaterRules.WATER_PRICE.toFixed(2) + ' 元/吨（无阶梯）'],
      ['免费水量', '2 吨/人/月 × ' + safe + ' 人 = ' + quota.toFixed(1) + ' 吨'],
      ['折合扣电', '水费 ÷ 0.58 元/度（1 吨 ≈ ' + WaterRules.tonToDegree().toFixed(2) + ' 度）'],
      ['学年划拨', WaterRules.CYCLE_MONTHS + ' 个月']
    ];
    return lines;
  }
}
