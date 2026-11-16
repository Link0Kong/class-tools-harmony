import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { Session } from './Session';

const STORE_NAME: string = 'class_tools_session';
const KEY_SESSION: string = 'session_v1';
const TAG: string = 'SessionStore';

/**
 * 会话持久化（HarmonyOS preferences，按应用沙箱存储）。
 *
 * 只存身份会话；班级名单/课表等缓存后续按 sid 分桶，退出登录时一并清除。
 */
export class SessionStore {
  private store: preferences.Preferences | undefined = undefined;

  private async ensure(): Promise<preferences.Preferences | undefined> {
    if (this.store !== undefined) {
      return this.store;
    }
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      Log.e(TAG, 'context 未注入，无法打开 preferences');
      return undefined;
    }
    try {
      this.store = await preferences.getPreferences(ctx, { name: STORE_NAME });
      return this.store;
    } catch (e) {
      Log.e(TAG, '打开 preferences 失败');
      return undefined;
    }
  }

  async load(): Promise<Session | undefined> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return undefined;
    }
    try {
      const raw: string = store.getSync(KEY_SESSION, '') as string;
      if (raw.length === 0) {
        return undefined;
      }
      return Session.fromJson(raw);
    } catch (e) {
      Log.e(TAG, '读取会话失败');
      return undefined;
    }
  }

  async save(session: Session): Promise<void> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return;
    }
    try {
      store.putSync(KEY_SESSION, session.toJson());
      await store.flush();
    } catch (e) {
      Log.e(TAG, '写入会话失败');
    }
  }

  async clear(): Promise<void> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return;
    }
    try {
      store.deleteSync(KEY_SESSION);
      await store.flush();
    } catch (e) {
      Log.e(TAG, '清除会话失败');
    }
  }
}
