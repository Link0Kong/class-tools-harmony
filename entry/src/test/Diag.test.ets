import { describe, it, expect } from '@ohos/hypium';
import {
  DiagAnalysis,
  DiagAnalysisResult,
  DiagCheck,
  DiagHealthResult,
  DiagStatus,
  DiagSummary,
  RepairTask,
  ServiceHealthRow,
  diagStatusColor,
  diagStatusLabel
} from '../main/ets/data/diag/DiagModels';
import { DiagRepository, GatewayProbe } from '../main/ets/data/diag/DiagRepository';
import { FakeApi } from './support/FakeApi';
import { DiagReport, DiagThrottle } from '../main/ets/data/diag/DiagReport';
import { Blob } from '../main/ets/data/sync/JsonBlob';

const HEALTH_JSON: string = '['
  + '{"id":"gateway","name":"云端网关","kind":"cloud","status":"ok","detail":"全部通过","checked_at":"2026-11-15T00:30:00+08:00"},'
  + '{"id":"site_static","name":"静态站","kind":"cloud","status":"warn","detail":"已按备案暂停","checked_at":"2026-11-15T00:30:00+08:00"},'
  + '{"id":"dns_domain","name":"域名解析","kind":"dns","status":"down","detail":"","checked_at":""},'
  + '{"id":"cloud_power_sync","name":"电费同步","kind":"cloud","status":"weird"}'
  + ']';

const ANALYSIS_JSON: string = '['
  + '{"id":"a1","severity":"warn","title":"静态站暂停","status":"done","cause":"备案暂停期","fix":"等待备案","ts":1794670000000,"related":"{\\"health_ids\\":[\\"site_static\\"]}"},'
  + '{"id":"a2","severity":"error","title":"网关延迟偏高","status":"running","cause":"","fix":"","ts":1794660000000}'
  + ']';

const REPAIR_JSON: string = '[{"id":"r1","action":"recheck_health","status":"done","error":"","created_at":1794670000000},'
  + '{"id":"r2","action":"restart_gateway","status":"failed","error":"timeout","created_at":1794660000000}]';

function check(id: string, status: DiagStatus): DiagCheck {
  const item: DiagCheck = new DiagCheck();
  item.id = id;
  item.label = id;
  item.status = status;
  return item;
}

export default function diagTest() {
  describe('DiagStatus', () => {
    it('labels_and_colors', 0, () => {
      expect(diagStatusLabel(DiagStatus.PASS)).assertEqual('正常');
      expect(diagStatusLabel(DiagStatus.WARN)).assertEqual('注意');
      expect(diagStatusLabel(DiagStatus.FAIL)).assertEqual('异常');
      expect(diagStatusLabel(DiagStatus.INFO)).assertEqual('信息');
      expect(diagStatusColor(DiagStatus.PASS)).assertEqual('#4E9082');
      expect(diagStatusColor(DiagStatus.FAIL)).assertEqual('#B4543F');
    });

    it('health_row_display_status', 0, () => {
      const row: ServiceHealthRow = new ServiceHealthRow();
      row.status = 'ok';
      expect(row.displayStatus()).assertEqual(DiagStatus.PASS);
      row.status = 'WARN';
      expect(row.displayStatus()).assertEqual(DiagStatus.WARN);
      row.status = 'down';
      expect(row.displayStatus()).assertEqual(DiagStatus.FAIL);
      row.status = 'unknown-x';
      expect(row.displayStatus()).assertEqual(DiagStatus.INFO);
    });

    it('summary_counts_and_overall', 0, () => {
      const summary: DiagSummary = new DiagSummary();
      summary.checks = [check('a', DiagStatus.PASS), check('b', DiagStatus.PASS)];
      expect(summary.passCount()).assertEqual(2);
      expect(summary.overall()).assertEqual(DiagStatus.PASS);
      summary.checks.push(check('c', DiagStatus.WARN));
      expect(summary.warnCount()).assertEqual(1);
      expect(summary.overall()).assertEqual(DiagStatus.WARN);
      summary.checks.push(check('d', DiagStatus.FAIL));
      expect(summary.failCount()).assertEqual(1);
      expect(summary.overall()).assertEqual(DiagStatus.FAIL);
      expect(summary.checks[2].shouldReport()).assertTrue();
      expect(summary.checks[0].shouldReport()).assertFalse();
    });
  });

  describe('DiagReport', () => {
    it('builds_anomaly_row', 0, () => {
      const warn: DiagCheck = check('gateway', DiagStatus.WARN);
      warn.value = '3200 ms';
      warn.hint = '延迟偏高';
      const row: Blob | undefined = DiagReport.build([check('app', DiagStatus.PASS), warn], 1234);
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        expect(row['kind']).assertEqual('diag');
        expect(row['level']).assertEqual('warn');
        expect(row['fingerprint']).assertEqual('gateway');
        const detail: Blob | undefined = row['detail'] as Blob;
        expect(detail['check']).assertEqual('gateway');
      }
    });

    it('includes_service_health', 0, () => {
      const warn: ServiceHealthRow = new ServiceHealthRow();
      warn.id = 'hw_sync';
      warn.name = '学工记云同步';
      warn.status = 'warn';
      warn.detail = '暂无作业';
      const pass: ServiceHealthRow = new ServiceHealthRow();
      pass.id = 'db';
      pass.status = 'pass';
      const checks: DiagCheck[] = DiagReport.fromHealth([warn, pass]);
      expect(checks.length).assertEqual(1);
      expect(checks[0].id).assertEqual('svc:hw_sync');
      expect(checks[0].label).assertEqual('学工记云同步');
      const row: Blob | undefined = DiagReport.buildAll([check('app', DiagStatus.PASS)], [warn], 7);
      expect(row !== undefined).assertTrue();
      if (row !== undefined) {
        const detail: Blob | undefined = row['detail'] as Blob;
        expect(detail['check']).assertEqual('svc:hw_sync');
      }
      expect(DiagReport.buildAll([], [pass], 8) === undefined).assertTrue();
    });

    it('error_level_and_multi', 0, () => {
      const a: DiagCheck = check('gateway', DiagStatus.FAIL);
      const b: DiagCheck = check('session', DiagStatus.WARN);
      const row: Blob | undefined = DiagReport.build([a, b], 99);
      if (row !== undefined) {
        expect(row['level']).assertEqual('error');
        expect(row['fingerprint']).assertEqual('gateway+session');
        const detail: Blob | undefined = row['detail'] as Blob;
        expect(detail['check']).assertEqual('multi');
      }
      expect(DiagReport.build([check('x', DiagStatus.PASS)], 1) === undefined).assertTrue();
    });

    it('throttle_window', 0, () => {
      expect(DiagThrottle.canReport(0, 1000)).assertTrue();
      expect(DiagThrottle.canReport(1000, 1000 + 5 * 60 * 1000)).assertFalse();
      expect(DiagThrottle.canReport(1000, 1000 + 11 * 60 * 1000)).assertTrue();
    });
  });

  describe('DiagRepository', () => {
    it('parses_health_rows', 0, () => {
      const rows: ServiceHealthRow[] = DiagRepository.parseHealth(HEALTH_JSON);
      expect(rows.length).assertEqual(4);
      expect(rows[0].id).assertEqual('gateway');
      expect(rows[0].name).assertEqual('云端网关');
      expect(rows[0].displayStatus()).assertEqual(DiagStatus.PASS);
      expect(rows[1].displayStatus()).assertEqual(DiagStatus.WARN);
      expect(rows[2].displayStatus()).assertEqual(DiagStatus.FAIL);
      expect(DiagRepository.parseHealth('bad').length).assertEqual(0);
    });

    it('parses_analyses_and_repairs', 0, () => {
      const analyses: DiagAnalysis[] = DiagRepository.parseAnalyses(ANALYSIS_JSON);
      expect(analyses.length).assertEqual(2);
      expect(analyses[0].title).assertEqual('静态站暂停');
      expect(analyses[0].severity).assertEqual('warn');
      expect(analyses[0].related.indexOf('site_static') > 0).assertTrue();
      const repairs: RepairTask[] = DiagRepository.parseRepairs(REPAIR_JSON);
      expect(repairs.length).assertEqual(2);
      expect(repairs[0].action).assertEqual('recheck_health');
      expect(repairs[1].status).assertEqual('failed');
    });

    it('loads_health_and_analyses_via_api', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.diagHealthBody = HEALTH_JSON;
      api.diagAnalysisBody = ANALYSIS_JSON;
      api.diagRepairBody = REPAIR_JSON;
      const repo: DiagRepository = new DiagRepository(api);
      const health: DiagHealthResult = await repo.health();
      expect(health.ok).assertTrue();
      expect(health.rows.length).assertEqual(4);
      expect(api.getPaths[0].indexOf('service_health?select=id,name') === 0).assertTrue();
      const analyses: DiagAnalysisResult = await repo.analyses();
      expect(analyses.ok).assertTrue();
      expect(analyses.analyses.length).assertEqual(2);
      expect(analyses.repairs.length).assertEqual(2);
    });

    it('probe_measures_latency_and_failure', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.diagHealthBody = '[]';
      let now: number = 1000;
      const repo: DiagRepository = new DiagRepository(api, () => now);
      const probe: GatewayProbe = await repo.probe();
      expect(probe.ok).assertTrue();
      expect(probe.latencyMs >= 1).assertTrue();
      api.failGets = true;
      const failed: GatewayProbe = await repo.probe();
      expect(failed.ok).assertFalse();
      expect(failed.message.length > 0).assertTrue();
    });
  });
}
