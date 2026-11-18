import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';

const TAG: string = 'HomeNtBadge';
const STORE: string = 'class_tools_home_badge';

/**
 * 工作台「新通知」角标（对齐小程序 newNtAt）：
 * 通知签名变化 → 记为“有新通知”；打开通知页 → 清零。
 * 首次使用（无历史签名）不提示，避免首次登录误报。
 */
export class HomeNtBadge {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE });
    } catch (e) {
      Log.w(TAG, '打开角标存储失败');
      return undefined;
    }
  }

  private static sigKey(sid: string): string {
    return 'sig_' + (sid.length > 0 ? sid : 'anon');
  }

  private static newKey(sid: string): string {
    return 'new_' + (sid.length > 0 ? sid : 'anon');
  }

  /** 用最新签名更新状态，返回当前是否显示角标。 */
  static async update(sid: string, signature: string): Promise<boolean> {
    if (signature.length === 0) {
      return false;
    }
    const store: preferences.Preferences | undefined = await HomeNtBadge.store();
    if (store === undefined) {
      return false;
    }
    try {
      const prevSig: string = await store.get(HomeNtBadge.sigKey(sid), '') as string;
      let isNew: boolean = await store.get(HomeNtBadge.newKey(sid), false) as boolean;
      if (prevSig.length > 0 && prevSig !== signature) {
        isNew = true;
      }
      await store.put(HomeNtBadge.sigKey(sid), signature);
      await store.put(HomeNtBadge.newKey(sid), isNew);
      await store.flush();
      return isNew;
    } catch (e) {
      return false;
    }
  }

  static async markOpened(sid: string): Promise<void> {
    const store: preferences.Preferences | undefined = await HomeNtBadge.store();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(HomeNtBadge.newKey(sid), false);
      await store.flush();
    } catch (e) {
      // 忽略
    }
  }
}
