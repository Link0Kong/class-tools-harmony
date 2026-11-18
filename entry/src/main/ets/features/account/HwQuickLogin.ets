import { Session } from '../../data/session/Session';
import { HwLoginResult } from '../../data/account/AccountBindingRepository';

/** 华为账号快捷登录结果（UI 只依赖该结果，便于单测）。 */
export class HwQuickLoginResult {
  ok: boolean = false;
  cancelled: boolean = false;
  fallbackManual: boolean = false;
  session: Session | undefined = undefined;
  message: string = '';
}

/** 可注入依赖：授权取 openID / 云端换会话 / 本机保存会话 / 错误文案。 */
export class HwQuickLoginDeps {
  openId: () => Promise<string> = () => Promise.resolve('');
  login: (openId: string) => Promise<HwLoginResult> = () => Promise.resolve(new HwLoginResult());
  save: (session: Session) => Promise<void> = () => Promise.resolve();
  describeError: (error: Object) => string = () => '华为账号登录失败';
}

/**
 * 华为账号快捷登录流程（纯逻辑，可单测）：
 * 1. 调 Account Kit 取 openID；
 * 2. 用 openID 换班级会话；
 * 3. 校验会话完整性后写入本机；
 * 4. 未绑定/取消/网络失败给出可操作提示，并回退学号+姓名登录。
 */
export class HwQuickLoginFlow {
  static async run(deps: HwQuickLoginDeps): Promise<HwQuickLoginResult> {
    const out: HwQuickLoginResult = new HwQuickLoginResult();
    let openId: string = '';
    try {
      openId = (await deps.openId()).trim();
    } catch (e) {
      out.message = deps.describeError(e as Object);
      out.cancelled = out.message.indexOf('取消') >= 0;
      out.fallbackManual = !out.cancelled;
      return out;
    }
    if (openId.length === 0) {
      out.message = '未获取到华为账号标识，请改用学号 + 姓名登录';
      out.fallbackManual = true;
      return out;
    }
    let login: HwLoginResult = new HwLoginResult();
    try {
      login = await deps.login(openId);
    } catch (e) {
      out.message = '登录请求失败，请稍后重试';
      out.fallbackManual = true;
      return out;
    }
    if (login.session === undefined) {
      out.message = login.reason.length > 0 ? login.reason : '该华为账号尚未绑定学号';
      out.fallbackManual = true;
      return out;
    }
    const session: Session = login.session;
    if (session.token.trim().length === 0) {
      out.message = '云端未返回有效身份凭证，请稍后重试';
      out.fallbackManual = true;
      return out;
    }
    if (session.sid.trim().length === 0) {
      out.message = '云端未返回学号信息，请改用学号 + 姓名登录';
      out.fallbackManual = true;
      return out;
    }
    try {
      await deps.save(session);
    } catch (e) {
      out.message = '登录成功，但保存本机会话失败，请重试';
      return out;
    }
    out.ok = true;
    out.session = session;
    return out;
  }
}
