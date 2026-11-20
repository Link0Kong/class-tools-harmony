import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { CloudConfig } from '../main/ets/config/CloudConfig';
import { VisitDevice } from '../main/ets/data/visits/VisitDevice';
import { VisitLoadResult, VisitRow, VisitsRepository } from '../main/ets/data/visits/VisitsRepository';
import {
  VisitAccount,
  VisitClientCount,
  VisitDeviceGroup,
  VisitRange,
  VisitStats,
  VisitStatsReport,
  VisitVersionCount
} from '../main/ets/data/visits/VisitStats';

/** 固定「现在」：2026-11-20 22:00（本地时区，测试用虚构学号）。 */
const NOW: number = new Date(2026, 10, 20, 22, 0, 0).getTime();

function at(hour: number, minute: number): number {
  return new Date(2026, 10, 20, hour, minute, 0).getTime();
}

function daysAgo(days: number, hour: number): number {
  return new Date(2026, 10, 20 - days, hour, 0, 0).getTime();
}

function rowOf(sid: string, name: string, ts: number, client: string = 'web', ver: string = '2.0.0',
  dev: string = 'Xiaomi 14 · Android 15', did: string = 'dida'): VisitRow {
  const row: VisitRow = new VisitRow();
  row.sid = sid;
  row.name = name;
  row.ts = ts;
  row.client = client;
  row.ver = ver;
  row.dev = dev;
  row.did = did;
  row.slot = '';
  return row;
}

function legacyRow(sid: string, name: string, slot: string): VisitRow {
  const row: VisitRow = new VisitRow();
  row.sid = sid;
  row.name = name;
  row.ts = 0;
  row.slot = slot;
  row.client = 'android';
  return row;
}

function clientLabels(items: VisitClientCount[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].label);
  }
  return out;
}

function versionLabels(items: VisitVersionCount[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].label);
  }
  return out;
}

function deviceLabels(items: VisitDeviceGroup[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].devLabel);
  }
  return out;
}

function accountOf(report: VisitStatsReport, name: string): VisitAccount {
  for (let i = 0; i < report.accounts.length; i++) {
    if (report.accounts[i].name === name) {
      return report.accounts[i];
    }
  }
  return new VisitAccount();
}

export default function visitStatsTest() {
  describe('VisitStatsFilter', () => {
    it('filters_anonymous_test_and_out_of_range', 0, () => {
      const rows: VisitRow[] = [
        rowOf('', '匿名', at(10, 0)),
        rowOf('3260799999', '官方测试', at(10, 5)),
        rowOf('9999000001', 'QA 测试', at(10, 10)),
        rowOf('9000000001', '甲', daysAgo(1, 10), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(9, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a')
      ];
      const today: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(today.accounts.length).assertEqual(1);
      expect(today.summary.visits).assertEqual(1);
      expect(today.totalRows).assertEqual(1);
      expect(today.accounts[0].count).assertEqual(1);

      const week: VisitStatsReport = VisitStats.build(rows, VisitRange.WEEK, NOW);
      expect(week.accounts.length).assertEqual(1);
      expect(week.summary.visits).assertEqual(2);
      expect(week.accounts[0].count).assertEqual(2);
      expect(week.accounts[0].activeDays).assertEqual(2);
      expect(week.accounts[0].activeToday).assertTrue();
    });

    it('future_and_too_old_rows_are_ignored', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', new Date(2026, 10, 21, 0, 30, 0).getTime()),
        rowOf('9000000002', '乙', daysAgo(7, 12)),
        rowOf('9000000003', '丙', at(12, 0))
      ];
      const today: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(today.summary.visits).assertEqual(1);
      expect(today.accounts[0].name).assertEqual('丙');
      const week: VisitStatsReport = VisitStats.build(rows, VisitRange.WEEK, NOW);
      expect(week.summary.visits).assertEqual(1);
    });

    it('test_sid_rule_is_official_and_9999_segment', 0, () => {
      expect(VisitStats.isTestAccount('3260799999')).assertTrue();
      expect(VisitStats.isTestAccount('9999000001')).assertTrue();
      expect(VisitStats.isTestAccount(' 9999000002 ')).assertTrue();
      expect(VisitStats.isTestAccount('9000000001')).assertFalse();
      expect(VisitStats.isTestAccount('9000000002')).assertFalse();
      expect(VisitStats.isTestAccount('999900001')).assertFalse();
    });
  });

  describe('VisitStatsSort', () => {
    it('sorts_by_count_then_last_ts_then_name', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', at(20, 0)),
        rowOf('9000000001', '甲', at(19, 0)),
        rowOf('9000000002', '乙', at(21, 0)),
        rowOf('9000000002', '乙', at(18, 0)),
        rowOf('9000000003', '丙', at(9, 0)),
        rowOf('9000000003', '丙', at(8, 0)),
        rowOf('9000000003', '丙', at(7, 0)),
        rowOf('9000000004', '丁', at(12, 0)),
        rowOf('9000000005', '戊', at(12, 0))
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      const names: string[] = [];
      for (let i = 0; i < report.accounts.length; i++) {
        names.push(report.accounts[i].name);
      }
      // 次数降序：丙 3 → 乙 2（最近 21:00）→ 甲 2（最近 20:00）→ 丁/戊 1（同时间按姓名升序：丁 U+4E01 / 戊 U+620A）
      expect(names.join(',')).assertEqual('丙,乙,甲,丁,戊');
      expect(report.accounts[0].count).assertEqual(3);
      expect(report.accounts[0].ratio).assertEqual(1);
      expect(report.accounts[1].ratio > 0.6 && report.accounts[1].ratio < 0.7).assertTrue();
    });

    it('ratios_use_max_account_count', 0, () => {
      const rows: VisitRow[] = [];
      for (let i = 0; i < 4; i++) {
        rows.push(rowOf('9000000001', '甲', at(10 + i, 0)));
      }
      rows.push(rowOf('9000000002', '乙', at(10, 0)));
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(report.accounts[0].count).assertEqual(4);
      expect(report.accounts[0].ratio).assertEqual(1);
      expect(report.accounts[1].ratio).assertEqual(0.25);
    });
  });

  describe('VisitStatsTime', () => {
    it('legacy_row_falls_back_to_slot_hour', 0, () => {
      expect(VisitStats.slotToTs('2026-11-20-09')).assertEqual(new Date(2026, 10, 20, 9, 0, 0).getTime());
      expect(VisitStats.effectiveTs(legacyRow('9000000001', '甲', '2026-11-20-09')))
        .assertEqual(new Date(2026, 10, 20, 9, 0, 0).getTime());
      expect(VisitStats.slotToTs('bad-slot')).assertEqual(0);
      expect(VisitStats.slotToTs('2026-13-20-09')).assertEqual(0);
      expect(VisitStats.slotToTs('')).assertEqual(0);
    });

    it('keeps_minutes_for_ts_rows_and_slot_rows', 0, () => {
      const rows: VisitRow[] = [
        legacyRow('9000000001', '甲', '2026-11-20-09'),
        rowOf('9000000002', '乙', at(21, 3))
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      const legacy: VisitAccount = accountOf(report, '甲');
      expect(legacy.lastTs).assertEqual(new Date(2026, 10, 20, 9, 0, 0).getTime());
      expect(legacy.detailText).assertEqual('首次 11/20 09:00 · 最近 11/20 09:00');
      const fresh: VisitAccount = accountOf(report, '乙');
      expect(fresh.detailText).assertEqual('首次 11/20 21:03 · 最近 11/20 21:03');
    });

    it('detail_text_week_includes_active_days', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', daysAgo(6, 9), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(21, 3), 'harmony', '1.0.8', 'Mate 60 · HarmonyOS 5.0.0', 'a')
      ];
      const week: VisitStatsReport = VisitStats.build(rows, VisitRange.WEEK, NOW);
      expect(week.accounts[0].detailText)
        .assertEqual('活跃 2/7 天 · 首次 11/14 09:00 · 最近 11/20 21:03');
      const today: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(today.accounts[0].activeDays).assertEqual(1);
      expect(today.accounts[0].detailText).assertEqual('首次 11/20 21:03 · 最近 11/20 21:03');
    });
  });

  describe('VisitStatsAccount', () => {
    it('aggregates_clients_versions_devices_and_last_row', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', at(10, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(10, 1), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(10, 2), 'android', '1.0.0', 'Pixel 8', 'b'),
        rowOf('9000000001', '甲', at(10, 3), 'harmony', '', '', '')
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      const account: VisitAccount = report.accounts[0];
      expect(account.count).assertEqual(4);
      expect(clientLabels(account.clients).join(',')).assertEqual('网页,安卓,鸿蒙');
      expect(account.clients[0].count).assertEqual(2);
      expect(versionLabels(account.versions).join(',')).assertEqual('2.0.0,1.0.0,未记录');
      expect(account.versions[0].count).assertEqual(2);
      expect(deviceLabels(account.devices).join(',')).assertEqual('Xiaomi 14 · Android 15,未记录,Pixel 8');
      expect(account.devices[0].count).assertEqual(2);
      expect(account.deviceCount).assertEqual(3);
      expect(account.lastClientLabel()).assertEqual('鸿蒙');
      expect(account.lastVerLabel()).assertEqual('未记录');
      expect(account.lastDevLabel()).assertEqual('未记录');
      expect(account.clientText()).assertEqual('网页 2 · 安卓 1 · 鸿蒙 1');
      expect(account.versionText()).assertEqual('2.0.0 ×2 · 1.0.0 ×1 · 未记录 ×1');
    });

    it('name_is_latest_named_row_then_roster_then_unknown', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '', at(10, 0)),
        rowOf('9000000001', '旧名', at(11, 0)),
        rowOf('9000000001', '新名', at(12, 0)),
        rowOf('9000000002', '', at(10, 0)),
        rowOf('9000000003', '  ', at(10, 0))
      ];
      const nameOf: (sid: string) => string = (sid: string): string => {
        return sid === '9000000002' ? '名单名' : '';
      };
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW, nameOf);
      expect(accountOf(report, '新名').count).assertEqual(3);
      expect(accountOf(report, '名单名').count).assertEqual(1);
      expect(accountOf(report, VisitStats.UNKNOWN_NAME).count).assertEqual(1);
    });

    it('device_count_prefers_did_and_falls_back_to_client_dev', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', at(10, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(11, 0), 'web', '2.0.0', 'Xiaomi 14 · Chrome 131', 'a'),
        rowOf('9000000001', '甲', at(12, 0), 'win', '1.0.0', '', '')
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(report.accounts[0].deviceCount).assertEqual(2);
      expect(report.summary.devices).assertEqual(2);
    });

    it('caps_version_and_device_lists_at_six_plus_other', 0, () => {
      const rows: VisitRow[] = [];
      for (let i = 0; i < 8; i++) {
        rows.push(rowOf('9000000001', '甲', at(10, i), 'web', '1.0.' + i, 'Device ' + i, 'd' + i));
      }
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      const account: VisitAccount = report.accounts[0];
      expect(account.versions.length).assertEqual(7);
      expect(account.versions[6].label).assertEqual('其他');
      expect(account.versions[6].other).assertTrue();
      expect(account.versions[6].count).assertEqual(2);
      expect(account.devices.length).assertEqual(7);
      expect(account.devices[6].devLabel).assertEqual('其他');
      expect(account.devices[6].other).assertTrue();
      expect(account.devices[6].count).assertEqual(2);
      let sum: number = 0;
      for (let i = 0; i < account.versions.length; i++) {
        sum += account.versions[i].percent;
      }
      expect(sum).assertEqual(100);
      expect(account.versions[6].percent).assertEqual(22);
    });

    it('roster_fallback_does_not_override_row_name', 0, () => {
      const rows: VisitRow[] = [rowOf('9000000001', '行内名', at(10, 0))];
      const nameOf: (sid: string) => string = (sid: string): string => '名单名';
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW, nameOf);
      expect(report.accounts[0].name).assertEqual('行内名');
    });
  });

  describe('VisitStatsGlobal', () => {
    it('summary_counts_accounts_visits_active_today_devices', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', at(10, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000002', '乙', at(11, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000003', '丙', at(12, 0), 'harmony', '1.0.8', 'Mate 60 · HarmonyOS 5.0.0', ''),
        rowOf('9000000001', '甲', daysAgo(1, 9), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a')
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.WEEK, NOW);
      expect(report.summary.accounts).assertEqual(3);
      expect(report.summary.visits).assertEqual(4);
      expect(report.summary.activeToday).assertEqual(3);
      // did: a ×3 行 → 1 台；无 did 的 鸿蒙|Mate 60 行 → 1 台。
      expect(report.summary.devices).assertEqual(2);
    });

    it('client_distribution_has_fixed_labels_and_percents', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', at(10, 0), 'web'),
        rowOf('9000000001', '甲', at(10, 1), 'web'),
        rowOf('9000000001', '甲', at(10, 2), 'web'),
        rowOf('9000000002', '乙', at(10, 3), 'mp'),
        rowOf('9000000003', '丙', at(10, 4), ''),
        rowOf('9000000004', '丁', at(10, 5), 'unknown')
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(clientLabels(report.clients).join(',')).assertEqual('网页,未记录,小程序');
      const unknown: VisitClientCount = report.clients[1];
      // 空 client 与未知识别都归「未记录」：2 行。
      expect(unknown.count).assertEqual(2);
      expect(unknown.client).assertEqual('');
      expect(report.clients[0].color).assertEqual('#4E9082');
      let sum: number = 0;
      for (let i = 0; i < report.clients.length; i++) {
        sum += report.clients[i].percent;
      }
      expect(sum).assertEqual(100);
    });

    it('trend_today_has_24_hours_and_peak', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', new Date(2026, 10, 20, 0, 10, 0).getTime()),
        rowOf('9000000001', '甲', new Date(2026, 10, 20, 9, 5, 0).getTime()),
        rowOf('9000000002', '乙', new Date(2026, 10, 20, 9, 45, 0).getTime()),
        rowOf('9000000003', '丙', new Date(2026, 10, 20, 23, 50, 0).getTime())
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(report.trend.length).assertEqual(24);
      expect(report.trend[0].count).assertEqual(1);
      expect(report.trend[9].count).assertEqual(2);
      expect(report.trend[23].count).assertEqual(1);
      expect(report.trend[0].label).assertEqual('00');
      expect(report.trend[23].label).assertEqual('23');
      expect(report.trend[9].ratio).assertEqual(1);
      expect(report.trendPeak).assertEqual('峰值 2 · 09 时');
      expect(report.trendTitle).assertEqual('今天 24 小时');
    });

    it('trend_week_has_7_days_and_today_highlight', 0, () => {
      const rows: VisitRow[] = [
        rowOf('9000000001', '甲', daysAgo(6, 10), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000001', '甲', at(10, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'a'),
        rowOf('9000000002', '乙', at(11, 0), 'web', '2.0.0', 'Xiaomi 14 · Android 15', 'b')
      ];
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.WEEK, NOW);
      expect(report.trend.length).assertEqual(7);
      expect(report.trend[0].label).assertEqual('11/14');
      expect(report.trend[0].count).assertEqual(1);
      expect(report.trend[6].label).assertEqual('11/20');
      expect(report.trend[6].count).assertEqual(2);
      expect(report.trend[6].highlight).assertTrue();
      expect(report.trend[0].highlight).assertFalse();
      expect(report.trendTitle).assertEqual('近 7 天');
      expect(report.trendPeak).assertEqual('峰值 2 · 11/20');
    });

    it('global_versions_devices_cap_at_six_plus_other', 0, () => {
      const rows: VisitRow[] = [];
      for (let i = 0; i < 8; i++) {
        rows.push(rowOf('900000000' + (i + 1), '账号' + i, at(10, i), 'web', '3.0.' + i, 'Device ' + i, 'd' + i));
      }
      const report: VisitStatsReport = VisitStats.build(rows, VisitRange.TODAY, NOW);
      expect(report.versions.length).assertEqual(7);
      expect(report.versions[6].label).assertEqual('其他');
      expect(report.versions[6].count).assertEqual(2);
      expect(report.devices.length).assertEqual(7);
      expect(report.devices[6].other).assertTrue();
      expect(report.devices[6].count).assertEqual(2);
      expect(report.devices[0].clientLabel).assertEqual('网页');
    });

    it('empty_data_has_zero_summary_and_range_hint', 0, () => {
      const today: VisitStatsReport = VisitStats.build([], VisitRange.TODAY, NOW);
      expect(today.empty).assertTrue();
      expect(today.emptyText).assertEqual('今天暂无访问');
      expect(today.summary.accounts).assertEqual(0);
      expect(today.summary.visits).assertEqual(0);
      expect(today.summary.activeToday).assertEqual(0);
      expect(today.summary.devices).assertEqual(0);
      expect(today.accounts.length).assertEqual(0);
      expect(today.trend.length).assertEqual(24);
      const week: VisitStatsReport = VisitStats.build([], VisitRange.WEEK, NOW);
      expect(week.emptyText).assertEqual('近 7 天暂无访问');
      expect(week.trend.length).assertEqual(7);
    });

    it('percents_round_and_pad_last_segment', 0, () => {
      const percents: number[] = VisitStats.percents([1, 1, 1], 3);
      expect(percents[0]).assertEqual(33);
      expect(percents[1]).assertEqual(33);
      expect(percents[2]).assertEqual(34);
      expect(VisitStats.percents([2, 1], 3).join(',')).assertEqual('67,33');
      expect(VisitStats.percents([], 0).length).assertEqual(0);
      expect(VisitStats.percents([0], 0)[0]).assertEqual(0);
    });
  });

  describe('VisitsRepository', () => {
    it('builds_contract_query_and_from_slot', 0, () => {
      const path: string = VisitsRepository.statsPath(NOW);
      expect(path.indexOf('visits?select=slot,sid,name,ts,client,ver,dev,did') === 0).assertTrue();
      expect(path.indexOf('slot=gte.2026-11-14-00') > 0).assertTrue();
      expect(path.indexOf('order=ts.desc') > 0).assertTrue();
      expect(path.indexOf('limit=5000') > 0).assertTrue();
      expect(VisitsRepository.fromSlot(new Date(2026, 10, 1, 8, 0, 0).getTime())).assertEqual('2026-10-26-00');
    });

    it('parses_rows_and_skips_bad_entries', 0, () => {
      const body: string = '[{"slot":"2026-11-20-21","sid":"9000000001","name":"甲",'
        + '"ts":1795000000000,"client":"harmony","ver":"1.0.8","dev":"Mate 60 · HarmonyOS 5.0.0",'
        + '"did":"0123456789abcdef"},42,{"sid":"9000000002"}]';
      const rows: VisitRow[] = VisitsRepository.parseRows(body);
      expect(rows.length).assertEqual(2);
      expect(rows[0].slot).assertEqual('2026-11-20-21');
      expect(rows[0].sid).assertEqual('9000000001');
      expect(rows[0].ver).assertEqual('1.0.8');
      expect(rows[0].dev).assertEqual('Mate 60 · HarmonyOS 5.0.0');
      expect(rows[0].did).assertEqual('0123456789abcdef');
      expect(rows[0].ts).assertEqual(1795000000000);
      expect(rows[1].name).assertEqual('');
      expect(VisitsRepository.parseRows('').length).assertEqual(0);
      expect(VisitsRepository.parseRows('not-json').length).assertEqual(0);
      expect(VisitsRepository.parseRows('{}').length).assertEqual(0);
    });

    it('load_parses_response_and_reports_failure', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.visitsBody = '[{"sid":"9000000001","name":"甲","ts":' + at(10, 0)
        + ',"client":"web","ver":"2.0.0","dev":"Xiaomi 14 · Android 15","did":"a","slot":"2026-11-20-10"}]';
      const repo: VisitsRepository = new VisitsRepository(api, () => NOW);
      const result: VisitLoadResult = await repo.load();
      expect(result.ok).assertTrue();
      expect(result.rows.length).assertEqual(1);
      expect(api.getPaths.length).assertEqual(1);
      expect(api.getPaths[0].indexOf('slot=gte.2026-11-14-00') > 0).assertTrue();

      const failing: FakeApi = new FakeApi();
      failing.failGets = true;
      const failed: VisitLoadResult = await new VisitsRepository(failing, () => NOW).load();
      expect(failed.ok).assertFalse();
      expect(failed.message.length > 0).assertTrue();
      expect(failed.rows.length).assertEqual(0);
    });
  });

  describe('VisitDevice', () => {
    it('device_label_merges_brand_model_and_os', 0, () => {
      expect(VisitDevice.deviceLabel('HUAWEI', 'Mate 60', 'HarmonyOS 5.0.0'))
        .assertEqual('HUAWEI Mate 60 · HarmonyOS 5.0.0');
      expect(VisitDevice.deviceLabel('Xiaomi', 'Xiaomi 14', 'Android 15'))
        .assertEqual('Xiaomi 14 · Android 15');
      expect(VisitDevice.deviceLabel('', 'Mate 60', 'HarmonyOS 5.0.0'))
        .assertEqual('Mate 60 · HarmonyOS 5.0.0');
      expect(VisitDevice.deviceLabel('HUAWEI', 'HUAWEI Mate 60', ''))
        .assertEqual('HUAWEI Mate 60');
      expect(VisitDevice.deviceLabel('HUAWEI', '', 'HarmonyOS 5.0.0'))
        .assertEqual('HUAWEI · HarmonyOS 5.0.0');
      expect(VisitDevice.deviceLabel('', '', '')).assertEqual('');
    });

    it('device_label_normalizes_space_and_truncates_48', 0, () => {
      expect(VisitDevice.deviceLabel('  A ', '  Model   X  ', ' OS  1 ')).assertEqual('A Model X · OS 1');
      expect(VisitDevice.normalize('  A   B\tC\nD  ')).assertEqual('A B C D');
      const longModel: string = 'X'.repeat(64);
      const label: string = VisitDevice.deviceLabel('', longModel, '');
      expect(label.length).assertEqual(48);
      expect(VisitDevice.truncate('abcdef', 3)).assertEqual('abc');
      expect(VisitDevice.truncate('abc', 10)).assertEqual('abc');
    });

    it('version_label_strips_v_prefix_and_truncates_32', 0, () => {
      expect(VisitDevice.versionLabel('v1.0.8')).assertEqual('1.0.8');
      expect(VisitDevice.versionLabel(' V2.0.0-beta14 ')).assertEqual('2.0.0-beta14');
      expect(VisitDevice.versionLabel('1.0.8').length).assertEqual(5);
      expect(VisitDevice.versionLabel('1'.repeat(40)).length).assertEqual(32);
      expect(VisitDevice.appVersion()).assertEqual(CloudConfig.APP_VERSION);
    });

    it('current_device_label_is_safe_fallback_in_tests', 0, () => {
      const label: string = VisitDevice.current();
      expect(label.length > 0).assertTrue();
      expect(label.length <= 48).assertTrue();
      expect(label.indexOf('undefined') < 0).assertTrue();
    });
  });
}
