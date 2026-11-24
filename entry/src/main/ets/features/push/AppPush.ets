import { pushService } from '@kit.PushKit';
import notificationManager from '@ohos.notificationManager';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { Log } from '../../common/Log';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 系统推送（Push Kit）：
 * - 启动时先申请系统通知权限，再按用户意愿注册 token；
 * - token 写入本人 `userdata.push`（token/enabled/want/at）；
 * - 用户主动关闭后记录 want=false，后续启动不再自动开启；
 * - tokenUpdate 时自动更新。
 */
export class AppPush {
  private static listening: boolean = false;

  /** 用户是否希望接收推送（新安装默认开启；关闭后持久化 want=false）。 */
  static want(): boolean {
    const sections: Blob = Services.userdata.currentSections();
    const push: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'push'));
    if (push === undefined) {
      return true;
    }
    if (JsonBlob.has(push, 'want')) {
      return JsonBlob.asBoolean(JsonBlob.get(push, 'want'), true);
    }
    // 旧数据没有 want：默认视为希望接收，交给系统权限决定
    return true;
  }

  /** 是否已成功注册 token。 */
  static enabled(): boolean {
    const sections: Blob = Services.userdata.currentSections();
    const push: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'push'));
    return push !== undefined && JsonBlob.asBoolean(JsonBlob.get(push, 'enabled'), false);
  }

  static token(): string {
    const sections: Blob = Services.userdata.currentSections();
    const push: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'push'));
    return push === undefined ? '' : JsonBlob.asString(JsonBlob.get(push, 'token'), '');
  }

  /** 系统通知权限是否已开启。 */
  static async systemEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  /** 确保系统通知已授权：未授权时拉起系统授权弹窗，并回读真实状态。 */
  static async ensurePermission(): Promise<boolean> {
    if (await AppPush.systemEnabled()) {
      return true;
    }
    const context = AppGlobal.context;
    if (context === undefined) {
      return false;
    }
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (e) {
      Log.w('AppPush', '请求通知授权失败');
    }
    return await AppPush.systemEnabled();
  }

  /** 启动时：只续订已授权用户的 token，不在启动阶段弹系统权限（权限由用户操作触发）。 */
  static async syncOnLaunch(): Promise<void> {
    const allowed: boolean = await AppPush.systemEnabled();
    if (!allowed) {
      Log.i('AppPush', '系统通知未授权，等待用户主动开启');
      return;
    }
    if (!AppPush.want()) {
      return;
    }
    await AppPush.register();
  }

  /** 申请 token 并保存；返回是否注册成功。 */
  static async register(): Promise<boolean> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return false;
    }
    const allowed: boolean = await AppPush.ensurePermission();
    if (!allowed) {
      await AppPush.save('', false, true);
      return false;
    }
    const ability = AppGlobal.ability;
    try {
      const token: string = await pushService.getToken();
      if (token.length === 0) {
        await AppPush.save('', false, true);
        return false;
      }
      await AppPush.save(token, true, true);
      await AppPush.syncTable(token);
      if (!AppPush.listening && ability !== undefined) {
        pushService.on('tokenUpdate', ability, (newToken: string) => {
          AppPush.save(newToken, true, true);
        });
        AppPush.listening = true;
      }
      return true;
    } catch (e) {
      Log.w('AppPush', 'getToken 失败');
      await AppPush.save('', false, true);
      return false;
    }
  }

  /** 用户主动开启（先记录意愿，再注册）。 */
  static async enable(): Promise<boolean> {
    const allowed: boolean = await AppPush.ensurePermission();
    if (!allowed) {
      await AppPush.save(AppPush.token(), false, false);
      return false;
    }
    await AppPush.save(AppPush.token(), false, true);
    return await AppPush.register();
  }

  /** 关闭推送：删除 token 并记录 want=false。 */
  static async disable(): Promise<void> {
    try {
      await pushService.deleteToken();
    } catch (e) {
      // 未开通/无 token 时也允许关闭
    }
    await AppPush.save('', false, false);
    await AppPush.clearTable();
  }

  /** 同步到班级共享表 push_tokens（provider=harmony），供发送端读取。 */
  private static async syncTable(token: string): Promise<void> {
    try {
      await Services.api.delete('push_tokens?provider=eq.harmony');
      const body: Blob = {};
      body['provider'] = 'harmony';
      body['token'] = token;
      body['device'] = deviceInfo.productModel;
      body['app_version'] = '1.0.9';
      await Services.api.post('push_tokens', JSON.stringify(body), 'return=minimal');
    } catch (e) {
      Log.w('AppPush', '写 push_tokens 失败');
    }
  }

  private static async clearTable(): Promise<void> {
    try {
      await Services.api.delete('push_tokens?provider=eq.harmony');
    } catch (e) {
      // 忽略
    }
  }

  private static async save(token: string, enabled: boolean, want: boolean): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const push: Blob = {};
    const old: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'push'));
    if (old !== undefined) {
      const oldKeys: string[] = JsonBlob.keys(old);
      for (let i = 0; i < oldKeys.length; i++) {
        push[oldKeys[i]] = old[oldKeys[i]];
      }
    }
    push['token'] = token;
    push['enabled'] = enabled;
    push['want'] = want;
    push['at'] = Date.now();
    next['push'] = push;
    await Services.userdata.updateCurrent(next);
    const pushKeys: Set<string> = new Set<string>();
    pushKeys.add('push');
    await Services.userdata.push(false, pushKeys);
  }
}
