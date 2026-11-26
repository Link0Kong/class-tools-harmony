import { preferences } from '@kit.ArkData';
import { AsyncLock } from '../../common/AsyncLock';
import { CloudConfig } from '../../config/CloudConfig';
import { pushService } from '@kit.PushKit';
import notificationManager from '@ohos.notificationManager';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { UserdataRepository } from '../../data/sync/UserdataRepository';
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
  private static sequence: number = 0;
  private static queue = new AsyncLock();
  private static detached: boolean = false;

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
    const userdata = Services.userdata;
    AppPush.detached = false;
    const allowed: boolean = await AppPush.systemEnabled();
    if (userdata !== Services.userdata) return;
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
    const sid = Services.currentSid;
    const userdata = Services.userdata;
    const seq = AppPush.sequence;
    if (!sid || !AppPush.want() || !await AppPush.systemEnabled()) return false;
    return AppPush.queue.run<boolean>(async () => {
      if (!AppPush.current(userdata, seq)) return false;
      try {
        const token = await pushService.getToken();
        const ok = await AppPush.install(token, sid, seq, userdata);
        const ability = AppGlobal.ability;
        if (!AppPush.listening && ability) {
          pushService.on('tokenUpdate', ability, (updated: string) => {
            const owner = Services.currentSid;
            const generation = AppPush.sequence;
            const active = Services.userdata;
            AppPush.queue.run<boolean>(() => AppPush.install(updated, owner, generation, active));
          });
          AppPush.listening = true;
        }
        return ok;
      } catch (_) {
        if (AppPush.current(userdata, seq)) await AppPush.save('', false, true);
        return false;
      }
    });
  }

  private static current(userdata: UserdataRepository, seq: number): boolean {
    return userdata === Services.userdata && !AppPush.detached && AppPush.sequence === seq && AppPush.want();
  }

  private static async install(token: string, sid: string, seq: number, userdata: UserdataRepository): Promise<boolean> {
    const ctx = AppGlobal.context;
    if (!ctx || !token || !sid || !AppPush.current(userdata, seq)) return false;
    const store = preferences.getPreferencesSync(ctx, { name: 'push_device_registration' });
    const old = store.getSync(sid, '') as string;
    const body: Blob = { 'sid': sid, 'provider': 'harmony', 'token': token, 'device': deviceInfo.productModel,
      'app_version': CloudConfig.APP_VERSION, 'updated_at': new Date().toISOString() };
    const result = await Services.api.post('push_tokens?on_conflict=provider,token', JSON.stringify(body),
      'resolution=merge-duplicates,return=minimal');
    if (result.ok) {
      store.putSync(sid, token);
      await store.flush();
      if (old && old !== token && AppPush.current(userdata, seq)) await AppPush.removeRegistration(sid, old);
    }
    if (!AppPush.current(userdata, seq)) return false;
    await AppPush.save(result.ok ? token : '', result.ok, true);
    return result.ok;
  }

  static async enable(): Promise<boolean> {
    const userdata = Services.userdata;
    if (!Services.currentSid || !await AppPush.ensurePermission() || userdata !== Services.userdata) return false;
    AppPush.detached = false;
    await AppPush.save('', false, true);
    return userdata === Services.userdata && await AppPush.register();
  }

  private static async removeRegistration(sid: string, token: string): Promise<boolean> {
    if (!token || !sid) return true;
    const result = await Services.api.delete('push_tokens?provider=eq.harmony&sid=eq.' + encodeURIComponent(sid)
      + '&token=eq.' + encodeURIComponent(token));
    return result.ok;
  }

  static async endSession(clearRemote: boolean): Promise<void> {
    AppPush.sequence++;
    AppPush.detached = true;
    const sid = Services.currentSid;
    const ctx = AppGlobal.context;
    if (!sid || !ctx) return;
    await AppPush.queue.run<void>(async () => {
      try {
        const store = preferences.getPreferencesSync(ctx, { name: 'push_device_registration' });
        const token = store.getSync(sid, '') as string;
        if (clearRemote && Services.currentSid === sid && await AppPush.removeRegistration(sid, token)) {
          store.deleteSync(sid);
          await store.flush();
        }
        await pushService.deleteToken();
      } catch (_) {
        Log.w('AppPush', '设备推送注销未完成');
      }
    });
  }

  static async disable(): Promise<void> {
    const userdata = Services.userdata;
    await AppPush.endSession(true);
    if (Services.currentSid && userdata === Services.userdata) await AppPush.save('', false, false);
  }

  private static async save(token: string, enabled: boolean, want: boolean): Promise<void> {
    const userdata = Services.userdata;
    const current: Blob = userdata.currentSections();
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
    await userdata.saveAndPush(next, 'push');
  }
}
