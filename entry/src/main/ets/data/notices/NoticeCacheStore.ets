import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';

const TAG: string = 'NoticeCacheStore';
const STORE_NAME: string = 'class_tools_notice_cache';

/** 通知完整行的本机缓存（按 sid 分桶），冷启动/离线时先渲染缓存再后台刷新。 */
export class NoticeCacheBlob {
  signature: string = '';
  savedAt: number = 0;
  rowsJson: string = '';
}

/**
 * 通知磁盘缓存：只保存服务端返回的原始行 JSON 文本 + 签名 + 时间。
 * 读取时复用 `NoticeBodyParser.parseRows`，不额外维护一套序列化格式。
 */
export class NoticeCacheStore {
  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE_NAME });
    } catch (e) {
      Log.e(TAG, '打开通知缓存失败');
      return undefined;
    }
  }

  private static key(sid: string): string {
    return 'c_' + (sid.length > 0 ? sid : 'anon');
  }

  static async load(sid: string): Promise<NoticeCacheBlob | undefined> {
    const p: preferences.Preferences | undefined = await NoticeCacheStore.store();
    if (p === undefined) {
      return undefined;
    }
    try {
      const raw: string = await p.get(NoticeCacheStore.key(sid), '') as string;
      if (raw.length === 0) {
        return undefined;
      }
      const parsed = JSON.parse(raw) as NoticeCacheBlob;
      if (parsed === undefined || parsed.rowsJson === undefined || parsed.rowsJson.length === 0) {
        return undefined;
      }
      return parsed;
    } catch (e) {
      return undefined;
    }
  }

  static async save(sid: string, blob: NoticeCacheBlob): Promise<void> {
    const p: preferences.Preferences | undefined = await NoticeCacheStore.store();
    if (p === undefined) {
      return;
    }
    try {
      await p.put(NoticeCacheStore.key(sid), JSON.stringify(blob));
      await p.flush();
    } catch (e) {
      Log.w(TAG, '保存通知缓存失败');
    }
  }

  static async clear(sid: string): Promise<void> {
    const p: preferences.Preferences | undefined = await NoticeCacheStore.store();
    if (p === undefined) {
      return;
    }
    try {
      await p.delete(NoticeCacheStore.key(sid));
      await p.flush();
    } catch (e) {
      // 忽略
    }
  }
}
