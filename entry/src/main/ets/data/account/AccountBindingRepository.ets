import { Services } from '../../app/Services';
import { Session } from '../session/Session';
import { ApiResult } from '../net/ApiResult';
import { Api } from '../net/Api';

/** 一条华为账号绑定记录。 */
export class BindItem {
  openId: string = '';
  device: string = '';
  createdAt: string = '';

  masked(): string {
    if (this.openId.length <= 8) {
      return '已绑定账号';
    }
    return this.openId.substring(0, 4) + '…' + this.openId.substring(this.openId.length - 4);
  }
}

export class HwLoginResult {
  session: Session | undefined = undefined;
  reason: string = '';
  /** 华为账号有效但尚未绑定学号：应引导用户完成学号认证并绑定。 */
  unbound: boolean = false;
}

interface HwActionJson {
  ok?: boolean;
  reason?: string;
  count?: number;
}

interface HwLoginJson {
  ok?: boolean;
  reason?: string;
  token?: string;
  sid?: string;
  name?: string;
  role?: string;
  badge?: string;
  is_admin?: boolean;
}

interface HwBindRowJson {
  open_id?: string;
  device?: string;
  created_at?: string;
}

/** 华为账号 ↔ 学号绑定（RPC：hw_bind / hw_bindings / hw_unbind / hw_login）。 */
export class AccountBindingRepository {
  /** 绑定当前华为账号；成功返回空串，失败返回原因。 */
  static async bind(openId: string, device: string, api: Api = Services.api): Promise<string> {
    if (openId.length === 0) {
      return '没有拿到华为账号标识';
    }
    const body: string = JSON.stringify({ p_open_id: openId, p_device: device });
    const result: ApiResult = await api.post('rpc/hw_bind', body);
    if (!result.ok) {
      return result.error !== undefined ? result.error.displayMessage() : '绑定失败';
    }
    try {
      const obj: HwActionJson = JSON.parse(result.value) as HwActionJson;
      if (obj.ok !== true) {
        return obj.reason !== undefined && obj.reason.length > 0 ? obj.reason : '绑定失败';
      }
      return '';
    } catch (e) {
      return '绑定服务返回异常';
    }
  }

  /** 当前学号已绑定的华为账号列表。 */
  static async list(api: Api = Services.api): Promise<BindItem[]> {
    const result: ApiResult = await api.post('rpc/hw_bindings', '{}');
    const out: BindItem[] = [];
    if (!result.ok) {
      return out;
    }
    if (result.value.length === 0) {
      return out;
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(result.value);
    } catch (e) {
      return out;
    }
    if (!Array.isArray(parsed)) {
      return out;
    }
    const arr: Object[] = parsed as Object[];
    for (let i = 0; i < arr.length; i++) {
      const row: HwBindRowJson = arr[i] as HwBindRowJson;
      const item: BindItem = new BindItem();
      item.openId = row.open_id !== undefined ? row.open_id : '';
      item.device = row.device !== undefined ? row.device : '';
      item.createdAt = row.created_at !== undefined ? row.created_at : '';
      if (item.openId.length > 0) {
        out.push(item);
      }
    }
    return out;
  }

  /** 解绑指定华为账号。 */
  static async unbind(openId: string, api: Api = Services.api): Promise<boolean> {
    const result: ApiResult = await api.post('rpc/hw_unbind',
      JSON.stringify({ p_open_id: openId }));
    if (!result.ok || result.value.length === 0) {
      return false;
    }
    try {
      const obj: HwActionJson = JSON.parse(result.value) as HwActionJson;
      return obj.ok === true;
    } catch (e) {
      return false;
    }
  }

  /** 用华为账号换班级会话；未绑定时 reason 说明原因。 */
  static async login(openId: string, api: Api = Services.api,
    now: () => number = () => Date.now()): Promise<HwLoginResult> {
    const out: HwLoginResult = new HwLoginResult();
    const normalized: string = openId.trim();
    if (normalized.length === 0) {
      out.reason = '没有拿到华为账号标识';
      return out;
    }
    const result: ApiResult = await api.post('rpc/hw_login',
      JSON.stringify({ p_open_id: normalized }));
    if (!result.ok) {
      out.reason = result.error !== undefined ? result.error.displayMessage() : '登录失败';
      return out;
    }
    let obj: HwLoginJson;
    try {
      obj = JSON.parse(result.value) as HwLoginJson;
    } catch (e) {
      out.reason = '登录服务返回异常';
      return out;
    }
    if (obj.ok !== true) {
      out.reason = obj.reason !== undefined ? obj.reason : '登录失败';
      out.unbound = out.reason.indexOf('绑定') >= 0;
      return out;
    }
    const sid: string = obj.sid !== undefined ? obj.sid.trim() : '';
    const token: string = obj.token !== undefined ? obj.token.trim() : '';
    if (token.length === 0) {
      out.reason = '云端未返回身份凭证，请稍后重试';
      return out;
    }
    if (sid.length === 0) {
      out.reason = '云端未返回学号信息';
      return out;
    }
    const issuedAt: number = now();
    const session: Session = new Session(sid, obj.name !== undefined ? obj.name.trim() : '', token);
    session.role = obj.role !== undefined ? obj.role : '';
    session.badge = obj.badge !== undefined ? obj.badge : '';
    session.isAdmin = obj.is_admin === true;
    session.issuedAt = issuedAt;
    session.expiresAt = 0;
    out.session = session;
    return out;
  }
}
