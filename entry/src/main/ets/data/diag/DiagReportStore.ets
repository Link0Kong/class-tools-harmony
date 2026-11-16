import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';

/** 上报节流时间戳持久化（preferences，键 `last_report`）。 */
export class DiagReportStore {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: 'class_tools_diag' });
    } catch (e) {
      return undefined;
    }
  }

  static async lastReportAt(): Promise<number> {
    const store: preferences.Preferences | undefined = await DiagReportStore.store();
    if (store === undefined) {
      return 0;
    }
    try {
      return await store.get('last_report', 0) as number;
    } catch (e) {
      return 0;
    }
  }

  static async markReported(nowMillis: number): Promise<void> {
    const store: preferences.Preferences | undefined = await DiagReportStore.store();
    if (store === undefined) {
      return;
    }
    try {
      await store.put('last_report', nowMillis);
      await store.flush();
    } catch (e) {
      // 忽略持久化失败，不阻塞上报
    }
  }
}
