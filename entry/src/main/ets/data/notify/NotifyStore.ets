import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { NotifySnapshot } from '../../features/notify/NotifyModels';

const TAG: string = 'NotifyStore';
const STORE_NAME: string = 'class_tools_notify';

/** 通知设置 / 快照 / 已排程提醒 id 的本机持久化（按 sid 分桶）。 */
export class NotifyStore {
  private static async store(context?: common.Context): Promise<preferences.Preferences | undefined> {
    const ctx = context || AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE_NAME });
    } catch (e) {
      Log.e(TAG, '打开通知设置失败');
      return undefined;
    }
  }

  /** 串行写入事务开始时丢弃另一进程可能已更新的内存副本。 */
  static async refresh(context: common.Context): Promise<void> {
    await preferences.removePreferencesFromCache(context, STORE_NAME);
  }

  private static prefix(sid: string): string {
    return 'nt_' + (sid.length > 0 ? sid : 'anon');
  }

  static async loadSettings(sid: string, context?: common.Context): Promise<NotifySettings> {
    if (context) await NotifyStore.refresh(context);
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return new NotifySettings();
    }
    try {
      const raw: string = await p.get(NotifyStore.prefix(sid) + '_settings', '') as string;
      return NotifySettings.fromJson(raw);
    } catch (e) {
      return new NotifySettings();
    }
  }

  static async saveSettings(sid: string, settings: NotifySettings, context?: common.Context): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NotifyStore.prefix(sid) + '_settings', settings.toJson());
      await p.flush();
    } catch (e) {
      Log.e(TAG, '保存通知设置失败');
    }
  }

  static async loadSnapshot(sid: string, context?: common.Context): Promise<NotifySnapshot> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return new NotifySnapshot();
    }
    try {
      const raw: string = await p.get(NotifyStore.prefix(sid) + '_snapshot', '') as string;
      return NotifySnapshot.fromJson(raw);
    } catch (e) {
      return new NotifySnapshot();
    }
  }

  static async saveSnapshot(sid: string, snapshot: NotifySnapshot, context?: common.Context): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NotifyStore.prefix(sid) + '_snapshot', snapshot.toJson());
      await p.flush();
    } catch (e) {
      Log.e(TAG, '保存通知快照失败');
    }
  }

  /** 已排程事件：key → reminderId（字符串编码）。 */
  static async loadScheduled(sid: string, bucket: string = '_sched', context?: common.Context): Promise<Map<string, number>> {
    const out: Map<string, number> = new Map<string, number>();
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return out;
    }
    try {
      const raw: string = await p.get(NotifyStore.prefix(sid) + bucket, '') as string;
      return NotifyStore.decode(raw);
    } catch (e) {
      return out;
    }
  }

  static async saveScheduled(sid: string, map: Map<string, number>, bucket: string = '_sched', context?: common.Context): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NotifyStore.prefix(sid) + bucket, NotifyStore.encode(map));
      await p.flush();
    } catch (e) {
      Log.e(TAG, '保存排程失败');
    }
  }

  static async lastRun(sid: string, context?: common.Context): Promise<number> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return 0;
    }
    try {
      return await p.get(NotifyStore.prefix(sid) + '_last', 0) as number;
    } catch (e) {
      return 0;
    }
  }

  static async setLastRun(sid: string, at: number, context?: common.Context): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store(context);
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NotifyStore.prefix(sid) + '_last', at);
      await p.flush();
    } catch (e) {
      // 忽略
    }
  }

  static encode(map: Map<string, number>): string {
    const rows: Record<string, number> = {};
    map.forEach((id: number, key: string) => {
      rows[key] = id;
    });
    return JSON.stringify(rows);
  }

  static decode(raw: string): Map<string, number> {
    const out: Map<string, number> = new Map<string, number>();
    if (raw.startsWith('{')) {
      try {
        const rows: Record<string, number> = JSON.parse(raw) as Record<string, number>;
        Object.keys(rows).forEach((key: string) => {
          if (Number.isInteger(rows[key]) && rows[key] >= -1) {
            out.set(key, rows[key]);
          }
        });
      } catch (e) {
        Log.w(TAG, '排程记录格式错误');
      }
      return out;
    }
    // 1.0.10 及以前为以分号分隔的 key:id。
    raw.split(';').forEach((pair: string) => {
      const at: number = pair.lastIndexOf(':');
      const id: number = Number(pair.substring(at + 1));
      if (at > 0 && at < pair.length - 1 && Number.isInteger(id) && id >= 0) {
        out.set(pair.substring(0, at), id);
      }
    });
    return out;
  }
}
