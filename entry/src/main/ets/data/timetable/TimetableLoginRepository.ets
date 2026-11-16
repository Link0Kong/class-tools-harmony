import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { TtParser, TtSnapshot } from './TimetableModels';

const ENQUEUE_PATH: string = 'rpc/tt_login_enqueue';
const STATUS_PATH: string = 'rpc/tt_login_status';

export class TtLoginEnqueue {
  ok: boolean = false;
  jobId: string = '';
  reused: boolean = false;
  message: string = '';
}

export class TtLoginStatus {
  ok: boolean = false;
  status: string = '';
  finished: boolean = false;
  error: string = '';
  snapshot: TtSnapshot | undefined = undefined;
  raw: Blob | undefined = undefined;
  message: string = '';
}

/**
 * 教务登录任务（契约 §1：enqueue/status 是客户端唯一入口；密码只出现在 enqueue 的 POST body 里，
 * 不落盘、不打印、不进入任何返回值）。登录成功后由调用方写 `userdata.tt.ttLocal`。
 */
export class TimetableLoginRepository {
  private api: Api;

  constructor(api: Api) {
    this.api = api;
  }

  async enqueue(password: string): Promise<TtLoginEnqueue> {
    const result: TtLoginEnqueue = new TtLoginEnqueue();
    if (password.length === 0) {
      result.message = '请输入教务密码';
      return result;
    }
    const body: Blob = {};
    body['p_pwd'] = password;
    body['p_platform'] = 'android';
    const response: ApiResult = await this.api.post(ENQUEUE_PATH, JSON.stringify(body), '', true);
    if (!response.ok) {
      result.message = response.error !== undefined ? response.error.displayMessage() : '登录任务提交失败';
      return result;
    }
    const parsed: Blob | undefined = JsonBlob.parse(response.value);
    if (parsed === undefined) {
      result.message = '响应无法解析';
      return result;
    }
    result.ok = JsonBlob.asBoolean(JsonBlob.get(parsed, 'ok'), false);
    result.jobId = JsonBlob.asString(JsonBlob.get(parsed, 'job_id'), '');
    result.reused = JsonBlob.asBoolean(JsonBlob.get(parsed, 'reused'), false);
    if (!result.ok || result.jobId.length === 0) {
      result.message = JsonBlob.asString(JsonBlob.get(parsed, 'reason'), '登录任务被拒绝');
    }
    return result;
  }

  async status(jobId: string): Promise<TtLoginStatus> {
    const result: TtLoginStatus = new TtLoginStatus();
    const body: Blob = {};
    body['p_id'] = jobId;
    const response: ApiResult = await this.api.post(STATUS_PATH, JSON.stringify(body), '', true);
    if (!response.ok) {
      result.message = response.error !== undefined ? response.error.displayMessage() : '状态查询失败';
      return result;
    }
    const raw: Blob | undefined = JsonBlob.parse(response.value);
    if (raw === undefined) {
      result.message = '响应无法解析';
      return result;
    }
    result.ok = JsonBlob.asBoolean(JsonBlob.get(raw, 'ok'), false);
    result.status = JsonBlob.asString(JsonBlob.get(raw, 'status'), '');
    result.finished = JsonBlob.asBoolean(JsonBlob.get(raw, 'finished'), false);
    result.error = JsonBlob.asString(JsonBlob.get(raw, 'error'), '');
    const tt: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(raw, 'result'));
    if (tt !== undefined) {
      result.snapshot = TtParser.parseSnapshot(JSON.stringify(tt));
      result.raw = tt;
    }
    if (!result.ok) {
      result.message = JsonBlob.asString(JsonBlob.get(raw, 'reason'), '状态查询被拒绝');
    }
    return result;
  }
}
