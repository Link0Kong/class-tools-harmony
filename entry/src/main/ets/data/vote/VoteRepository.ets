import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import {
  PollDetailResult,
  PollDraft,
  PollListResult,
  VoteResult
} from './VoteModels';
import { VoteRpc } from './VoteRpc';

/**
 * 投票仓库：所有请求 `POST {REST}/rpc/<name>`，body 具名参数；服务端统一 `{ok:...}`（HTTP 200）。
 *
 * - `poll_list` / `poll_detail` / `poll_submit` / `poll_create` / `poll_manage`；
 * - 任何响应都不含学号；指定成员范围用座号。
 */
export class VoteRepository {
  private api: Api;

  constructor(api: Api) {
    this.api = api;
  }

  async list(): Promise<PollListResult> {
    const result: ApiResult = await this.api.post('rpc/poll_list', VoteRpc.listBody(), '', true);
    if (!result.ok) {
      return new PollListResult(false, result.error !== undefined ? result.error.displayMessage() : '投票加载失败',
        VoteRpc.parseList(''));
    }
    const body: Blob | undefined = JsonBlob.parse(result.value);
    if (body === undefined) {
      return new PollListResult(false, '投票数据格式错误', VoteRpc.parseList(''));
    }
    if (!JsonBlob.asBoolean(JsonBlob.get(body, 'ok'), false)) {
      return new PollListResult(false, errorOf(body), VoteRpc.parseList(result.value));
    }
    return new PollListResult(true, '', VoteRpc.parseList(result.value));
  }

  async detail(pollId: string): Promise<PollDetailResult> {
    const result: ApiResult = await this.api.post('rpc/poll_detail', VoteRpc.detailBody(pollId), '', true);
    if (!result.ok) {
      return new PollDetailResult(false,
        result.error !== undefined ? result.error.displayMessage() : '投票详情加载失败', VoteRpc.parseDetail(''));
    }
    const body: Blob | undefined = JsonBlob.parse(result.value);
    if (body === undefined) {
      return new PollDetailResult(false, '投票数据格式错误', VoteRpc.parseDetail(''));
    }
    if (!JsonBlob.asBoolean(JsonBlob.get(body, 'ok'), false)) {
      return new PollDetailResult(false, errorOf(body), VoteRpc.parseDetail(result.value));
    }
    return new PollDetailResult(true, '', VoteRpc.parseDetail(result.value));
  }

  async submit(pollId: string, choices: string[]): Promise<VoteResult> {
    const result: ApiResult = await this.api.post('rpc/poll_submit',
      VoteRpc.submitBody(pollId, choices), '', true);
    return toVoteResult(result, pollId, '投票失败');
  }

  async create(draft: PollDraft): Promise<VoteResult> {
    const result: ApiResult = await this.api.post('rpc/poll_create', VoteRpc.createBody(draft), '', true);
    return toVoteResult(result, draft.id, '发起失败');
  }

  async manage(pollId: string, action: string, deadline: number, draft: PollDraft | undefined): Promise<VoteResult> {
    const result: ApiResult = await this.api.post('rpc/poll_manage',
      VoteRpc.manageBody(pollId, action, deadline, draft), '', true);
    return toVoteResult(result, pollId, '操作失败');
  }
}

function toVoteResult(result: ApiResult, pollId: string, fallback: string): VoteResult {
  if (!result.ok) {
    return new VoteResult(false,
      result.error !== undefined ? result.error.displayMessage() : fallback, pollId);
  }
  const body: Blob | undefined = JsonBlob.parse(result.value);
  if (body === undefined) {
    return new VoteResult(false, '响应格式错误', pollId);
  }
  if (!JsonBlob.asBoolean(JsonBlob.get(body, 'ok'), false)) {
    return new VoteResult(false, errorOf(body), pollId);
  }
  const id: string = JsonBlob.asString(JsonBlob.get(body, 'poll_id'), '');
  return new VoteResult(true, '', id.length > 0 ? id : pollId);
}

function errorOf(body: Blob): string {
  const error: string = JsonBlob.asString(JsonBlob.get(body, 'error'), '');
  if (error.length > 0) {
    return error;
  }
  const msg: string = JsonBlob.asString(JsonBlob.get(body, 'msg'), '');
  return msg.length > 0 ? msg : '操作失败';
}
