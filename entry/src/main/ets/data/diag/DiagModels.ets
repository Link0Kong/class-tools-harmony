export enum DiagStatus {
  PASS = 'pass',
  WARN = 'warn',
  FAIL = 'fail',
  INFO = 'info'
}

export function diagStatusLabel(status: DiagStatus): string {
  if (status === DiagStatus.PASS) {
    return '正常';
  }
  if (status === DiagStatus.WARN) {
    return '注意';
  }
  if (status === DiagStatus.FAIL) {
    return '异常';
  }
  return '信息';
}

export function diagStatusColor(status: DiagStatus): string {
  if (status === DiagStatus.PASS) {
    return '#4E9082';
  }
  if (status === DiagStatus.WARN) {
    return '#B98F63';
  }
  if (status === DiagStatus.FAIL) {
    return '#B4543F';
  }
  return '#6E8CA8';
}

/** `service_health` 行。 */
export class ServiceHealthRow {
  id: string = '';
  name: string = '';
  kind: string = '';
  status: string = '';
  detail: string = '';
  meta: string = '';
  checkedAt: string = '';

  displayStatus(): DiagStatus {
    const value: string = this.status.trim().toLowerCase();
    if (value === 'ok' || value === 'up' || value === 'pass') {
      return DiagStatus.PASS;
    }
    if (value === 'warn') {
      return DiagStatus.WARN;
    }
    if (value === 'down' || value === 'fail' || value === 'error') {
      return DiagStatus.FAIL;
    }
    return DiagStatus.INFO;
  }
}

/** 本机设备检查项。 */
export class DiagCheck {
  id: string = '';
  label: string = '';
  status: DiagStatus = DiagStatus.INFO;
  value: string = '';
  hint: string = '';

  shouldReport(): boolean {
    return this.status === DiagStatus.WARN || this.status === DiagStatus.FAIL;
  }
}

export class DiagSummary {
  checks: DiagCheck[] = [];
  ranAt: number = 0;

  passCount(): number {
    return this.countOf(DiagStatus.PASS);
  }

  warnCount(): number {
    return this.countOf(DiagStatus.WARN);
  }

  failCount(): number {
    return this.countOf(DiagStatus.FAIL);
  }

  private countOf(status: DiagStatus): number {
    let count: number = 0;
    for (let i = 0; i < this.checks.length; i++) {
      if (this.checks[i].status === status) {
        count += 1;
      }
    }
    return count;
  }

  overall(): DiagStatus {
    if (this.failCount() > 0) {
      return DiagStatus.FAIL;
    }
    if (this.warnCount() > 0) {
      return DiagStatus.WARN;
    }
    return DiagStatus.PASS;
  }
}

/** AI 分析（`diag_analysis` 行，只读展示）。 */
export class DiagAnalysis {
  id: string = '';
  severity: string = '';
  title: string = '';
  status: string = '';
  cause: string = '';
  fix: string = '';
  ts: number = 0;
  related: string = '';
}

/** 修复任务（`repair_tasks` 行，只读展示）。 */
export class RepairTask {
  id: string = '';
  action: string = '';
  status: string = '';
  error: string = '';
  createdAt: number = 0;
}

export class DiagHealthResult {
  ok: boolean = false;
  message: string = '';
  rows: ServiceHealthRow[] = [];

  constructor(ok: boolean, message: string, rows: ServiceHealthRow[]) {
    this.ok = ok;
    this.message = message;
    this.rows = rows;
  }
}

export class DiagAnalysisResult {
  ok: boolean = false;
  message: string = '';
  analyses: DiagAnalysis[] = [];
  repairs: RepairTask[] = [];

  constructor(ok: boolean, message: string, analyses: DiagAnalysis[], repairs: RepairTask[]) {
    this.ok = ok;
    this.message = message;
    this.analyses = analyses;
    this.repairs = repairs;
  }
}
