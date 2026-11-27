import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { ToolLaunch } from '../../app/ToolLaunch';
import { Log } from '../../common/Log';

export class LiveRecord {
  id: number = 0;
  noticeId: number = 0;
  owner: string = '';
  kind: string = '';
  title: string = '';
  text: string = '';
  until: number = 0;
  hidden: boolean = false;
  endedAt: number = 0;
  surface: string = '';
  parameters: Record<string, Object> = {};
  conversion: boolean = false;
  updated: number = 0;

  launch(): ToolLaunch | undefined {
    return ToolLaunch.parse(this.parameters);
  }
}

/** Run only in the UI process. System-managed expiry also applies while this process is suspended. */
export class LiveRecords {
  private static owner: string = '';
  private static values: LiveRecord[] = [];

  static all(sid: string): LiveRecord[] {
    if (sid !== LiveRecords.owner) {
      LiveRecords.owner = sid;
      LiveRecords.values = [];
      const ctx = AppGlobal.context;
      if (ctx && sid) {
        try {
          const prefs = preferences.getPreferencesSync(ctx, { name: 'activity_records' });
          const raw = prefs.getSync(sid, '[]') as string;
          const rows = JSON.parse(raw) as LiveRecord[];
          if (Array.isArray(rows)) {
            for (const row of rows) {
              if (!row || row.owner !== sid || !Number.isInteger(row.id) || !row.parameters) continue;
              const item = new LiveRecord();
              item.id = row.id;
              item.noticeId = row.noticeId || row.id;
              item.owner = sid;
              item.kind = row.kind;
              item.title = row.title;
              item.text = row.text;
              item.until = row.until;
              item.hidden = row.hidden;
              item.endedAt = row.endedAt || 0;
              item.surface = row.surface;
              item.parameters = row.parameters;
              item.conversion = row.conversion;
              item.updated = row.updated;
              LiveRecords.values.push(item);
            }
          }
        } catch (_) { Log.w('LiveRecords', '无法读取当前活动'); }
      }
    }
    return LiveRecords.values;
  }

  static async refreshBackground(context: common.Context): Promise<void> {
    await preferences.removePreferencesFromCache(context, 'activity_records');
  }

  static presentInBackground(sid: string, id: number, context: common.Context): boolean {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'activity_records' });
      const rows = JSON.parse(store.getSync(sid, '[]') as string) as LiveRecord[];
      return rows.some((row: LiveRecord) => row.owner === sid && row.id === id && row.until > Date.now() &&
        (row.hidden || row.endedAt > 0 || row.surface === 'native'));
    } catch (_) { return false; }
  }

  static save(item: LiveRecord): void {
    if (item.owner !== LiveRecords.owner) return;
    const rows = LiveRecords.values;
    const at = rows.findIndex((row: LiveRecord) => row.id === item.id);
    if (at < 0) rows.push(item);
    else rows[at] = item;
    LiveRecords.flush();
  }

  static remove(item: LiveRecord): void {
    if (item.owner !== LiveRecords.owner) return;
    LiveRecords.values = LiveRecords.values.filter((row: LiveRecord) => row.id !== item.id);
    LiveRecords.flush();
  }

  private static flush(): void {
    const ctx = AppGlobal.context;
    if (ctx && LiveRecords.owner) {
      try {
        const prefs = preferences.getPreferencesSync(ctx, { name: 'activity_records' });
        prefs.putSync(LiveRecords.owner, JSON.stringify(LiveRecords.values));
        prefs.flushSync();
      } catch (_) { Log.w('LiveRecords', '无法保存当前活动'); }
    }
    AppStorage.setOrCreate<number>('activityRevision', (AppStorage.get<number>('activityRevision') ?? 0) + 1);
  }
}
