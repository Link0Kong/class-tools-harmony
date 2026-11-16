import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';

/**
 * 华为账号（Account Kit）：只取 openID（scope = openid）。
 *
 * 说明：授权接口在手机 / 平板 / PC / 手表（5.1.0+）可用；
 * 需要 AGC 已开通 Account Kit，并且应用证件与 client_id 配置正确。
 */
export class HuaweiAccount {
  /** 拉起华为账号授权并返回 openID；用户取消或失败时抛错。 */
  static async openId(context: common.Context): Promise<string> {
    const provider = new authentication.HuaweiIDProvider();
    const request = provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['openid'];
    const controller = new authentication.AuthenticationController(context);
    const response = await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    const openId: string = response.data !== undefined && response.data.openID !== undefined ? response.data.openID : '';
    return openId;
  }

  /** 把 Account Kit 错误码翻成用户能懂的文案（不泄露内部细节）。 */
  static message(err: Object): string {
    const text: string = JSON.stringify(err);
    if (text.indexOf('1001502001') >= 0 || text.indexOf('1001500001') >= 0) {
      return '未登录华为账号，请先在系统设置登录';
    }
    if (text.indexOf('1001502012') >= 0) {
      return '已取消华为账号授权';
    }
    if (text.indexOf('1001502003') >= 0) {
      return '应用未开通华为账号服务';
    }
    return '华为账号登录失败，请稍后重试';
  }
}
