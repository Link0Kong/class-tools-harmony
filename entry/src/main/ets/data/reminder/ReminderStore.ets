import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { ReminderPrefs } from '../../features/reminder/ReminderModels';

const TAG: string = 'ReminderStore';
const STORE_NAME: string = 'class_tools_reminders';

/** 本机提醒状态：提前分钟数 + homeworkId → 系统提醒 id。 */
export class ReminderRecord {
  advance: number = 30;
  ids: Map<string, number> = new Map<string, number>();
}

/** 作业提醒本机持久化（preferences：`<sid>_advance` 数字 + `<sid>_ids` 字符串）。 */
export class ReminderStore {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE_NAME });
    } catch (e) {
      Log.e(TAG, '打开提醒偏好失败');
      return undefined;
    }
  }

  private static prefix(sid: string): string {
    return 'hw_' + (sid.length > 0 ? sid : 'anon');
  }

  static async load(sid: string): Promise<ReminderRecord> {
    const record: ReminderRecord = new ReminderRecord();
    const store: preferences.Preferences | undefined = await ReminderStore.store();
    if (store === undefined) {
      return record;
    }
    try {
      const advance: number = await store.get(ReminderStore.prefix(sid) + '_advance', 30) as number;
      record.advance = advance;
      const raw: string = await store.get(ReminderStore.prefix(sid) + '_ids', '') as string;
      record.ids = ReminderStore.decodeIds(raw);
    } catch (e) {
      Log.e(TAG, '读取提醒偏好失败');
    }
    return record;
  }

  static async save(sid: string, record: ReminderRecord): Promise<void> {
    const store: preferences.Preferences | undefined = await ReminderStore.store();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(ReminderStore.prefix(sid) + '_advance', record.advance);
      await store.put(ReminderStore.prefix(sid) + '_ids', ReminderStore.encodeIds(record.ids));
      await store.flush();
    } catch (e) {
      Log.e(TAG, '保存提醒偏好失败');
    }
  }

  /** 序列化 hwId:reminderId;…（纯函数，便于单测）。 */
  static encodeIds(ids: Map<string, number>): string {
    const parts: string[] = [];
    ids.forEach((value: number, key: string) => {
      if (key.indexOf(';') < 0 && key.indexOf(':') < 0 && value >= 0) {
        parts.push(key + ':' + value);
      }
    });
    return parts.join(';');
  }

  static decodeIds(raw: string): Map<string, number> {
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

  static prefsOf(record: ReminderRecord): ReminderPrefs {
    const prefs: ReminderPrefs = new ReminderPrefs();
    prefs.advanceMinutes = record.advance;
    prefs.enabled = true;
    return prefs;
  }
}
