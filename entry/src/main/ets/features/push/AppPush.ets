import { pushService } from '@kit.PushKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { Log } from '../../common/Log';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 系统推送（Push Kit）：
 * - 仅当用户开启「消息推送」时申请 token，并写入本人 `userdata.push`（token/enabled/at）；
 * - tokenUpdate 时自动更新；
 * - 关闭时删除 token 并写 enabled=false。
 *
 * 注意：token 只存在本人 userdata 行；服务端下发需要能读取 token 的权限（见 docs/M69）。
 */
export class AppPush {
  private static listening: boolean = false;

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

  /** 启动时：已开启则续订 token（失败静默，不阻塞主流程）。 */
  static async syncOnLaunch(): Promise<void> {
    if (!AppPush.enabled()) {
      return;
    }
    await AppPush.register();
  }

  /** 申请 token 并保存；返回是否成功。 */
  static async register(): Promise<boolean> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return false;
    }
    const ability = AppGlobal.ability;
    try {
      const token: string = await pushService.getToken();
      if (token.length === 0) {
        return false;
      }
      await AppPush.save(token, true);
      await AppPush.syncTable(token);
      if (!AppPush.listening && ability !== undefined) {
        pushService.on('tokenUpdate', ability, (newToken: string) => {
          AppPush.save(newToken, true);
        });
        AppPush.listening = true;
      }
      return true;
    } catch (e) {
      Log.w('AppPush', 'getToken 失败');
      return false;
    }
  }

  /** 关闭推送：删除 token 并落库。 */
  static async disable(): Promise<void> {
    try {
      await pushService.deleteToken();
    } catch (e) {
      // 忽略：未开通/无 token 时也允许关闭
    }
    await AppPush.save('', false);
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
      body['app_version'] = '1.0.5';
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

  private static async save(token: string, enabled: boolean): Promise<void> {
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
    push['at'] = Date.now();
    next['push'] = push;
    await Services.userdata.updateCurrent(next);
    const pushKeys: Set<string> = new Set<string>();
    pushKeys.add('push');
    await Services.userdata.push(false, pushKeys);
  }
}
