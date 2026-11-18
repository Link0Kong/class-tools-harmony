import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';

const STORE_NAME: string = 'class_tools_tool_order';
const SEP: string = ',';

/**
 * 「全部」页工具卡顺序（本机记忆，按分类分组）。
 *
 * 只存 id 的逗号串，读取时由 ToolCatalog 过滤未知/越级 id，
 * 不参与云端 userdata 契约，避免影响网页 / 安卓 / 小程序端。
 */
export class ToolOrderStore {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE_NAME });
    } catch (e) {
      return undefined;
    }
  }

  static async load(key: string): Promise<string[]> {
    const out: string[] = [];
    const p: preferences.Preferences | undefined = await ToolOrderStore.store();
    if (p === undefined) {
      return out;
    }
    try {
      const raw: string = await p.get(key, '') as string;
      if (raw.length === 0) {
        return out;
      }
      const parts: string[] = raw.split(SEP);
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].length > 0) {
          out.push(parts[i]);
        }
      }
    } catch (e) {
      // 读取失败按默认顺序展示
    }
    return out;
  }

  static async save(key: string, ids: string[]): Promise<void> {
    const p: preferences.Preferences | undefined = await ToolOrderStore.store();
    if (p === undefined) {
      return;
    }
    try {
      await p.put(key, ids.join(SEP));
      await p.flush();
    } catch (e) {
      // 写盘失败不影响当前排序
    }
  }
}
