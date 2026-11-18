import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { NotifySnapshot } from '../../features/notify/NotifyModels';

const TAG: string = 'NotifyStore';
const STORE_NAME: string = 'class_tools_notify';

/** 通知设置 / 快照 / 已排程提醒 id 的本机持久化（按 sid 分桶）。 */
export class NotifyStore {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
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

  private static prefix(sid: string): string {
    return 'nt_' + (sid.length > 0 ? sid : 'anon');
  }

  static async loadSettings(sid: string): Promise<NotifySettings> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
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

  static async saveSettings(sid: string, settings: NotifySettings): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
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

  static async loadSnapshot(sid: string): Promise<NotifySnapshot> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
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

  static async saveSnapshot(sid: string, snapshot: NotifySnapshot): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
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
  static async loadScheduled(sid: string): Promise<Map<string, number>> {
    const out: Map<string, number> = new Map<string, number>();
    const p: preferences.Preferences | undefined = await NotifyStore.store();
    if (p === undefined) {
      return out;
    }
    try {
      const raw: string = await p.get(NotifyStore.prefix(sid) + '_sched', '') as string;
      return NotifyStore.decode(raw);
    } catch (e) {
      return out;
    }
  }

  static async saveScheduled(sid: string, map: Map<string, number>): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NotifyStore.prefix(sid) + '_sched', NotifyStore.encode(map));
      await p.flush();
    } catch (e) {
      Log.e(TAG, '保存排程失败');
    }
  }

  static async lastRun(sid: string): Promise<number> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
    if (p === undefined) {
      return 0;
    }
    try {
      return await p.get(NotifyStore.prefix(sid) + '_last', 0) as number;
    } catch (e) {
      return 0;
    }
  }

  static async setLastRun(sid: string, at: number): Promise<void> {
    const p: preferences.Preferences | undefined = await NotifyStore.store();
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
    const parts: string[] = [];
    map.forEach((id: number, key: string) => {
      if (key.indexOf(';') < 0 && key.indexOf(':') < 0 && id >= 0) {
        parts.push(key + ':' + id);
      }
    });
    return parts.join(';');
  }

  static decode(raw: string): Map<string, number> {
    const out: Map<string, number> = new Map<string, number>();
    if (raw.length === 0) {
      return out;
    }
    const parts: string[] = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      const pair: string[] = parts[i].split(':');
      if (pair.length === 2) {
        const id: number = Number(pair[1]);
        if (pair[0].length > 0 && Number.isFinite(id) && id >= 0) {
          out.set(pair[0], Math.round(id));
        }
      }
    }
    return out;
  }
}
