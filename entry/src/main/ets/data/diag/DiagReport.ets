import { Blob } from '../sync/JsonBlob';
import { DiagCheck, DiagStatus, ServiceHealthRow } from './DiagModels';

/** 上报节流（同指纹 10 分钟一次）。 */
export class DiagThrottle {
  static readonly WINDOW_MS: number = 10 * 60 * 1000;

  static canReport(lastAt: number, nowMillis: number): boolean {
    if (lastAt <= 0) {
      return true;
    }
    return nowMillis - lastAt >= DiagThrottle.WINDOW_MS;
  }

  /** 指纹：kind + 异常检查项 id（排序去重）。 */
  static fingerprint(checks: DiagCheck[]): string {
    const ids: string[] = [];
    for (let i = 0; i < checks.length; i++) {
      const check: DiagCheck = checks[i];
      if (check.status === DiagStatus.WARN || check.status === DiagStatus.FAIL) {
        ids.push(check.id);
      }
    }
    ids.sort();
    const unique: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (unique.indexOf(ids[i]) < 0) {
        unique.push(ids[i]);
      }
    }
    return unique.join('+');
  }
}

/** `client_diag` 上报行（脱敏：只含检查 id/值/状态，不含账号、路径、URL）。 */
export class DiagReport {
  /** 把服务健康行转为可上报检查项（只保留注意/异常）。 */
  static fromHealth(rows: ServiceHealthRow[]): DiagCheck[] {
    const out: DiagCheck[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: ServiceHealthRow = rows[i];
      const status: DiagStatus = row.displayStatus();
      if (status !== DiagStatus.WARN && status !== DiagStatus.FAIL) {
        continue;
      }
      const check: DiagCheck = new DiagCheck();
      check.id = 'svc:' + row.id;
      check.label = row.name;
      check.status = status;
      check.value = row.detail;
      check.hint = row.meta;
      out.push(check);
    }
    return out;
  }

  /** 汇总本机检查 + 服务健康，生成本次上报行。 */
  static buildAll(checks: DiagCheck[], healthRows: ServiceHealthRow[], nowMillis: number): Blob | undefined {
    const merged: DiagCheck[] = checks.concat(DiagReport.fromHealth(healthRows));
    return DiagReport.build(merged, nowMillis);
  }

  static build(checks: DiagCheck[], nowMillis: number): Blob | undefined {
    const anomalies: DiagCheck[] = [];
    for (let i = 0; i < checks.length; i++) {
      if (checks[i].shouldReport()) {
        anomalies.push(checks[i]);
      }
    }
    if (anomalies.length === 0) {
      return undefined;
    }
    const level: string = anomalies.some((check: DiagCheck) => check.status === DiagStatus.FAIL)
      ? 'error' : 'warn';
    const fingerprint: string = DiagThrottle.fingerprint(checks);
    const details: Blob = {};
    const labels: string[] = [];
    for (let i = 0; i < anomalies.length; i++) {
      labels.push(anomalies[i].label);
      const item: Blob = {};
      item['status'] = anomalies[i].status;
      item['value'] = anomalies[i].value;
      item['hint'] = anomalies[i].hint;
      details[anomalies[i].id] = item;
    }
    const row: Blob = {};
    row['kind'] = 'diag';
    row['level'] = level;
    row['ts'] = nowMillis;
    row['title'] = '设备自检异常：' + labels.join('、');
    row['fingerprint'] = fingerprint;
    const detail: Blob = {};
    detail['check'] = anomalies.length === 1 ? anomalies[0].id : 'multi';
    detail['items'] = details;
    row['detail'] = detail;
    return row;
  }
}
