import { Api } from '../../main/ets/data/net/Api';
import { ApiError, ApiErrorKind, ApiResult } from '../../main/ets/data/net/ApiResult';
import { Blob } from '../../main/ets/data/sync/JsonBlob';

/**
 * 假网络层：单测用（记录请求、可控失败、可控云端数据）。
 *
 * 路由：`userdata*` → userdataBlob（空串 = 云端无行）；`marks*` → marksBody；其它 → `[]`。
 */
export class FakeApi implements Api {
  /** 云端 userdata.blob 原文（'' = 无行）。 */
  userdataBlob: string = '';
  /** 云端 marks 响应数组原文。 */
  marksBody: string = '[]';
  /** 云端 class_members 响应原文。 */
  membersBody: string = '[]';
  /** 云端 class_league 响应原文。 */
  leagueBody: string = '{"ok":true,"count":0,"seats":[]}';
  /** 云端 homework 响应原文。 */
  homeworkBody: string = '[]';
  /** 云端 fitrecs 响应原文。 */
  fitrecsBody: string = '[]';
  /** 云端 notices 轻量签名响应原文。 */
  noticesSigBody: string = '[]';
  /** 云端 notices 整表响应原文。 */
  noticesBody: string = '[]';
  /** 云端 site_assets 响应原文。 */
  siteAssetsBody: string = '[]';
  /** 云端 power 当前值响应原文。 */
  powerBody: string = '[]';
  /** 云端 power_history 响应原文。 */
  powerHistoryBody: string = '[]';
  /** 云端 poll_list 响应原文。 */
  pollListBody: string = '{"ok":true,"polls":[]}';
  /** 云端 poll_detail 响应原文。 */
  pollDetailBody: string = '{"ok":true,"poll":{"id":""}}';
  /** 云端 poll_submit / poll_create / poll_manage 响应原文。 */
  pollActionResult: string = '{"ok":true}';
  /** 云端 ppt_decks 列表响应原文。 */
  pptListBody: string = '[]';
  /** 云端 ppt_decks 详情响应原文。 */
  pptDetailBody: string = '[]';
  /** 云端 site_assets id=ppt_agent 响应原文。 */
  pptAgentBody: string = '[]';
  /** 教务登录 enqueue/status 响应原文。 */
  ttLoginEnqueueBody: string = '{"ok":true,"job_id":"job1"}';
  ttLoginStatusBody: string = '{"ok":true,"status":"running","finished":false}';
  /** 云端 service_health 响应原文。 */
  diagHealthBody: string = '[]';
  /** 云端 diag_analysis 响应原文。 */
  diagAnalysisBody: string = '[]';
  /** 云端 repair_tasks 响应原文。 */
  diagRepairBody: string = '[]';
  failGets: boolean = false;
  failPosts: boolean = false;
  hwActionBody: string = '{"ok":true,"count":1}';
  hwLoginBody: string = '{"ok":true,"token":"t0","sid":"3260799999","name":"测试账号","role":"","badge":"","is_admin":false}';
  hwListBody: string = '[]';

  getPaths: string[] = [];
  postPaths: string[] = [];
  postBodies: string[] = [];
  patchPaths: string[] = [];
  patchBodies: string[] = [];
  deletePaths: string[] = [];

  async get(path: string, authenticated: boolean = true): Promise<ApiResult> {
    this.getPaths.push(path);
    if (this.failGets) {
      return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, 'network', 'fake get failure'));
    }
    if (path.startsWith('userdata')) {
      if (this.userdataBlob.length === 0) {
        return ApiResult.success('[]');
      }
      const row: Blob = { 'id': 'test-sid', 'blob': this.userdataBlob, 'ts': 1 };
      const rows: Object[] = [row];
      return ApiResult.success(JSON.stringify(rows));
    }
    if (path.startsWith('marks')) {
      return ApiResult.success(this.marksBody);
    }
    if (path.startsWith('homework')) {
      return ApiResult.success(this.homeworkBody);
    }
    if (path.startsWith('fitrecs')) {
      return ApiResult.success(this.fitrecsBody);
    }
    if (path.startsWith('power_history')) {
      return ApiResult.success(this.powerHistoryBody);
    }
    if (path.startsWith('power')) {
      return ApiResult.success(this.powerBody);
    }
    if (path.startsWith('site_assets')) {
      if (path.indexOf('id=eq.ppt_agent') >= 0) {
        return ApiResult.success(this.pptAgentBody);
      }
      return ApiResult.success(this.siteAssetsBody);
    }
    if (path.startsWith('notices')) {
      if (path.indexOf('select=id,ts,hidden,edited_at') >= 0) {
        return ApiResult.success(this.noticesSigBody);
      }
      return ApiResult.success(this.noticesBody);
    }
    if (path.startsWith('ppt_decks')) {
      if (path.indexOf('manifest') >= 0 && path.indexOf('id=eq.') >= 0) {
        return ApiResult.success(this.pptDetailBody);
      }
      return ApiResult.success(this.pptListBody);
    }
    if (path.startsWith('service_health')) {
      if (path.indexOf('select=id&limit=1') >= 0) {
        return ApiResult.success('[]');
      }
      return ApiResult.success(this.diagHealthBody);
    }
    if (path.startsWith('diag_analysis')) {
      return ApiResult.success(this.diagAnalysisBody);
    }
    if (path.startsWith('repair_tasks')) {
      return ApiResult.success(this.diagRepairBody);
    }
    return ApiResult.success('[]');
  }

  async post(path: string, body: string, prefer: string = '', authenticated: boolean = true): Promise<ApiResult> {
    this.postPaths.push(path);
    this.postBodies.push(body);
    if (this.failPosts) {
      return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, 'network', 'fake post failure'));
    }
    if (path === 'rpc/tt_login_enqueue') {
      return ApiResult.success(this.ttLoginEnqueueBody);
    }
    if (path === 'rpc/tt_login_status') {
      return ApiResult.success(this.ttLoginStatusBody);
    }
    if (path.startsWith('rpc/class_members')) {
      return ApiResult.success(this.membersBody);
    }
    if (path.startsWith('rpc/class_league')) {
      return ApiResult.success(this.leagueBody);
    }
    if (path === 'rpc/poll_list') {
      return ApiResult.success(this.pollListBody);
    }
    if (path === 'rpc/poll_detail') {
      return ApiResult.success(this.pollDetailBody);
    }
    if (path.startsWith('rpc/poll_')) {
      return ApiResult.success(this.pollActionResult);
    }
    if (path === 'rpc/hw_bind' || path === 'rpc/hw_unbind') {
      return ApiResult.success(this.hwActionBody);
    }
    if (path === 'rpc/hw_login') {
      return ApiResult.success(this.hwLoginBody);
    }
    if (path === 'rpc/hw_bindings') {
      return ApiResult.success(this.hwListBody);
    }
    return ApiResult.success('[]');
  }

  async patch(path: string, body: string, prefer: string = '', authenticated: boolean = true): Promise<ApiResult> {
    this.patchPaths.push(path);
    this.patchBodies.push(body);
    if (this.failPosts) {
      return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, 'network', 'fake patch failure'));
    }
    return ApiResult.success('[]');
  }

  async delete(path: string, authenticated: boolean = true): Promise<ApiResult> {
    this.deletePaths.push(path);
    if (this.failPosts) {
      return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, 'network', 'fake delete failure'));
    }
    return ApiResult.success('[]');
  }

  lastPostBody(): string {
    return this.postBodies.length > 0 ? this.postBodies[this.postBodies.length - 1] : '';
  }
}
