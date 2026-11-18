import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import {
  DiagAnalysis,
  DiagAnalysisResult,
  DiagHealthResult,
  RepairTask,
  ServiceHealthRow
} from './DiagModels';

const HEALTH_PATH: string = 'service_health?select=id,name,kind,status,detail,meta,checked_at&order=id.asc';
const ANALYSIS_PATH: string = 'diag_analysis?select=*&order=ts.desc&limit=20';
const REPAIRS_PATH: string = 'repair_tasks?select=*&order=created_at.desc&limit=20';
const PROBE_PATH: string = 'service_health?select=id&limit=1';

/** 网关延迟测量结果。 */
export class GatewayProbe {
  ok: boolean = false;
  latencyMs: number = 0;
  message: string = '';
}

/** 诊断仓库（只读）：服务健康 / AI 分析 / 修复任务 / 网关延迟。 */
export class DiagRepository {
  private api: Api;
  private clock: () => number;

  constructor(api: Api, clock: () => number = () => Date.now()) {
    this.api = api;
    this.clock = clock;
  }

  async health(): Promise<DiagHealthResult> {
    const result: ApiResult = await this.api.get(HEALTH_PATH, true);
    if (!result.ok) {
      return new DiagHealthResult(false,
        result.error !== undefined ? result.error.displayMessage() : '服务健康加载失败', []);
    }
    return new DiagHealthResult(true, '', DiagRepository.parseHealth(result.value));
  }

  async analyses(): Promise<DiagAnalysisResult> {
    const analysisResult: ApiResult = await this.api.get(ANALYSIS_PATH, true);
    if (!analysisResult.ok) {
      return new DiagAnalysisResult(false,
        analysisResult.error !== undefined ? analysisResult.error.displayMessage() : 'AI 分析加载失败', [], []);
    }
    const repairResult: ApiResult = await this.api.get(REPAIRS_PATH, true);
    const repairs: RepairTask[] = repairResult.ok ? DiagRepository.parseRepairs(repairResult.value) : [];
    return new DiagAnalysisResult(true, '', DiagRepository.parseAnalyses(analysisResult.value), repairs);
  }

  /** 上报设备自检异常（client_diag，RLS 按 token 归属）。 */
  async report(row: Blob): Promise<boolean> {
    const result: ApiResult = await this.api.post('client_diag', JSON.stringify(row), 'return=minimal', true);
    return result.ok;
  }

  /** 网关延迟（同一接口往返耗时）。 */
  async probe(): Promise<GatewayProbe> {
    const probe: GatewayProbe = new GatewayProbe();
    const started: number = this.clock();
    const result: ApiResult = await this.api.get(PROBE_PATH, true);
    probe.latencyMs = Math.max(1, this.clock() - started);
    probe.ok = result.ok;
    if (!result.ok) {
      probe.message = result.error !== undefined ? result.error.displayMessage() : '网关不可达';
    }
    return probe;
  }

  static parseHealth(raw: string): ServiceHealthRow[] {
    const rows: Blob[] = rowsOf(raw);
    const out: ServiceHealthRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: ServiceHealthRow = new ServiceHealthRow();
      row.id = JsonBlob.asString(JsonBlob.get(rows[i], 'id'), '');
      if (row.id.length === 0) {
        continue;
      }
      row.name = JsonBlob.asString(JsonBlob.get(rows[i], 'name'), '');
      row.kind = JsonBlob.asString(JsonBlob.get(rows[i], 'kind'), '');
      row.status = JsonBlob.asString(JsonBlob.get(rows[i], 'status'), '');
      row.detail = JsonBlob.asString(JsonBlob.get(rows[i], 'detail'), '');
      row.meta = JsonBlob.asString(JsonBlob.get(rows[i], 'meta'), '');
      row.checkedAt = JsonBlob.asString(JsonBlob.get(rows[i], 'checked_at'), '');
      out.push(row);
    }
    return out;
  }

  static parseAnalyses(raw: string): DiagAnalysis[] {
    const rows: Blob[] = rowsOf(raw);
    const out: DiagAnalysis[] = [];
    for (let i = 0; i < rows.length; i++) {
      const item: DiagAnalysis = new DiagAnalysis();
      item.id = JsonBlob.asString(JsonBlob.get(rows[i], 'id'), '');
      item.severity = JsonBlob.asString(JsonBlob.get(rows[i], 'severity'), '');
      item.title = JsonBlob.asString(JsonBlob.get(rows[i], 'title'), '');
      item.status = JsonBlob.asString(JsonBlob.get(rows[i], 'status'), '');
      item.cause = JsonBlob.asString(JsonBlob.get(rows[i], 'cause'), '');
      item.fix = JsonBlob.asString(JsonBlob.get(rows[i], 'fix'), '');
      item.ts = JsonBlob.asNumber(JsonBlob.get(rows[i], 'ts'), 0);
      const related = JsonBlob.get(rows[i], 'related');
      item.related = typeof related === 'string' ? related as string : '';
      out.push(item);
    }
    return out;
  }

  static parseRepairs(raw: string): RepairTask[] {
    const rows: Blob[] = rowsOf(raw);
    const out: RepairTask[] = [];
    for (let i = 0; i < rows.length; i++) {
      const task: RepairTask = new RepairTask();
      task.id = JsonBlob.asString(JsonBlob.get(rows[i], 'id'), '');
      task.action = JsonBlob.asString(JsonBlob.get(rows[i], 'action'), '');
      task.status = JsonBlob.asString(JsonBlob.get(rows[i], 'status'), '');
      task.error = JsonBlob.asString(JsonBlob.get(rows[i], 'error'), '');
      task.createdAt = JsonBlob.asNumber(JsonBlob.get(rows[i], 'created_at'), 0);
      out.push(task);
    }
    return out;
  }
}

function rowsOf(raw: string): Blob[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  const array: Object[] | undefined = JsonBlob.asArray(parsed);
  if (array === undefined) {
    return [];
  }
  const out: Blob[] = [];
  for (let i = 0; i < array.length; i++) {
    const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
    if (obj !== undefined) {
      out.push(obj);
    }
  }
  return out;
}
