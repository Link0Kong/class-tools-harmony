import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 华为账号授权结果：openID 必得；匿名手机号需要一键登录权限，拿不到时为空串。 */
export class HwAuthInfo {
  openId: string = '';
  unionId: string = '';
  anonymousPhone: string = '';
}

/** 登录页预取结果：打开页面即展示账号信息，便于用户确认账号是否正确。 */
export class HwPrefetchResult {
  info: HwAuthInfo | undefined = undefined;
  /** 预取失败时给用户看的原因（超时/未登录华为账号等）。 */
  message: string = '';
  /** 系统未登录华为账号。 */
  notSignedIn: boolean = false;
}

/** 未申请 quickLoginAnonymousPhone 权限 / 设备不支持时回退到仅 openid。 */
const SCOPE_UNAVAILABLE: number = 1001502014;
const SCOPE_UNSUPPORTED: number = 1001500003;

/** 可抛出的账号错误：保留 Account Kit 错误码，满足 ArkTS 只允许抛 Error 的约束。 */
class HwAuthError extends Error {
  code: number = 0;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * 华为账号（Account Kit）。
 *
 * - `authorize`：一键登录优先（openid + 匿名手机号），权限未开通时自动回退为仅 openid；
 * - `openId`：兼容旧调用，只取 openID。
 *
 * 需要 AGC 已开通 Account Kit，并且应用证件与 client_id 配置正确。
 */
export class HuaweiAccount {
  /** 拉起华为账号授权，返回 openID / UnionID / 匿名手机号；取消或失败时抛错。 */
  static async authorize(context: common.Context): Promise<HwAuthInfo> {
    try {
      return await HuaweiAccount.request(context, true);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === SCOPE_UNAVAILABLE || err.code === SCOPE_UNSUPPORTED) {
        return await HuaweiAccount.request(context, false);
      }
      throw new HwAuthError(err.code, err.message);
    }
  }

  /** 兼容旧调用：只取 openID。 */
  static async openId(context: common.Context): Promise<string> {
    const info: HwAuthInfo = await HuaweiAccount.authorize(context);
    return info.openId;
  }

  /**
   * 登录页预取号（官方推荐流程）：打开页面即拉取匿名手机号，
   * 便于在点击登录前展示当前华为账号；5 秒超时，失败不阻塞页面。
   */
  static async prefetch(context: common.Context): Promise<HwPrefetchResult> {
    const out: HwPrefetchResult = new HwPrefetchResult();
    const timer: Promise<HwAuthInfo | undefined> = new Promise<HwAuthInfo | undefined>(
      (resolve: (value: HwAuthInfo | undefined) => void) => {
        setTimeout(() => {
          resolve(undefined);
        }, 5000);
      });
    const auth: Promise<HwAuthInfo | undefined> =
      HuaweiAccount.authorize(context).then((value: HwAuthInfo): HwAuthInfo | undefined => value);
    let winner: HwAuthInfo | undefined = undefined;
    try {
      winner = await Promise.race([auth, timer]);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      out.message = HuaweiAccount.message(err);
      out.notSignedIn = err.code === 1001502001;
      return out;
    }
    if (winner === undefined) {
      out.message = '获取华为账号信息超时，可重试或使用学号登录';
      return out;
    }
    out.info = winner;
    if (winner.openId.trim().length === 0) {
      out.message = '未获取到华为账号信息，请使用学号登录';
    }
    return out;
  }

  private static async request(context: common.Context, withPhone: boolean): Promise<HwAuthInfo> {
    const provider = new authentication.HuaweiIDProvider();
    const request = provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = withPhone ? ['openid', 'quickLoginAnonymousPhone'] : ['openid'];
    request.forceAuthorization = false;
    const controller = new authentication.AuthenticationController(context);
    const response = await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    const info: HwAuthInfo = new HwAuthInfo();
    const data: authentication.AuthorizationWithHuaweiIDCredential | undefined = response.data;
    if (data === undefined) {
      return info;
    }
    info.openId = data.openID !== undefined ? data.openID : '';
    info.unionId = data.unionID !== undefined ? data.unionID : '';
    const extra: Record<string, Object> | undefined = data.extraInfo;
    if (extra !== undefined) {
      const phone: Object | undefined = extra['quickLoginAnonymousPhone'];
      if (typeof phone === 'string') {
        info.anonymousPhone = String(phone);
      }
    }
    return info;
  }

  /** 把 Account Kit 错误码翻成用户能懂的文案（不泄露内部细节）。 */
  static message(err: Object): string {
    const be: BusinessError = err as BusinessError;
    if (be.code === 1001502001) {
      return '未登录华为账号，请先在系统设置登录';
    }
    if (be.code === 1001502012) {
      return '已取消华为账号授权';
    }
    if (be.code === 1001502003 || be.code === 1001502014) {
      return '应用未开通华为账号服务';
    }
    if (be.code === 1001502005) {
      return '网络异常，请检查网络后重试';
    }
    const text: string = JSON.stringify(err);
    if (text.indexOf('1001502001') >= 0 || text.indexOf('1001500001') >= 0) {
      return '未登录华为账号，请先在系统设置登录';
    }
    if (text.indexOf('1001502012') >= 0) {
      return '已取消华为账号授权';
    }
    if (text.indexOf('1001502014') >= 0 || text.indexOf('1001502003') >= 0) {
      return '应用未开通华为账号服务';
    }
    return '华为账号登录失败，请稍后重试';
  }
}
