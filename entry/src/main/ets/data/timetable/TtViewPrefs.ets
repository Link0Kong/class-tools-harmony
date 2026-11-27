import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';

const TAG: string = 'TtViewPrefs';
const STORE: string = 'class_tools_tt';

/**
 * 课表周/日视图的本机偏好（按账号隔离，不参与云同步）。
 *
 * 只存 `'week' | 'day'`；key 为 `view_<sid>`，未登录兜底 `view_anon`。
 * preferences 打不开或读写失败时静默降级（与首页卡片布局同一套写法），
 * 不影响课表本身的数据加载。
 */
export class TtViewPrefs {
  static readonly WEEK: string = 'week';
  static readonly DAY: string = 'day';

  /** 只认 `'week'` / `'day'`，其它（空串、大小写不符、脏值）→ `'week'`。 */
  static normalize(raw: string): string {
    return raw === TtViewPrefs.DAY ? TtViewPrefs.DAY : TtViewPrefs.WEEK;
  }

  /** 本机视图偏好存储在哪个账号下。 */
  private static key(sid: string): string {
    return 'view_' + (sid.length > 0 ? sid : 'anon');
  }

  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE });
    } catch (e) {
      Log.w(TAG, '打开课表视图偏好存储失败');
      return undefined;
    }
  }

  /** 读取本机视图偏好；从未保存过（或读取失败）返回 undefined（调用方用周视图）。 */
  static async load(sid: string): Promise<string | undefined> {
    const store: preferences.Preferences | undefined = await TtViewPrefs.store();
    if (store === undefined) {
      return undefined;
    }
    try {
      const exists: boolean = await store.has(TtViewPrefs.key(sid));
      if (!exists) {
        return undefined;
      }
      const text: string = await store.get(TtViewPrefs.key(sid), '') as string;
      if (text.length === 0) {
        return undefined;
      }
      return TtViewPrefs.normalize(text);
    } catch (e) {
      return undefined;
    }
  }

  /** 保存视图偏好（只落 `'week' | 'day'`，写入失败只记日志）。 */
  static async save(sid: string, view: string): Promise<void> {
    const store: preferences.Preferences | undefined = await TtViewPrefs.store();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(TtViewPrefs.key(sid), TtViewPrefs.normalize(view));
      await store.flush();
    } catch (e) {
      Log.w(TAG, '保存课表视图偏好失败');
    }
  }
}
