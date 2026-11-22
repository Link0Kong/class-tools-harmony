import { fileIo as fs } from '@kit.CoreFileKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { DrawResult } from '../../features/draw/DrawModels';
import { DrawLast, DrawLastCodec } from '../../features/draw/DrawLastCodec';
import { JsonBlob } from '../sync/JsonBlob';

const TAG: string = 'DrawLastStore';
const STORE_DIR: string = 'draw';

/**
 * 「最近一次抽签结果」本机持久层（按 sid 隔离，跨进程重启可用）。
 *
 * 与 `FileUserdataLocalStore` 同风格：落 `<filesDir>/draw/draw_last_<sid>.json`。
 * 不放进 userdata / preferences：
 * - 抽签结果**不同步**（契约 §3：换端不跟随，不进 UD）；
 * - 结果最多 999 项且带名称，preferences 单值上限不够稳。
 *
 * 读写失败均静默（本机缓存语义：失败不影响当前抽签，下一次再写）。
 */
export class DrawLastStore {
  private static dir(): string {
    const ctx = AppGlobal.context;
    return ctx === undefined ? '' : ctx.filesDir + '/' + STORE_DIR;
  }

  private static pathFor(sid: string): string {
    const safe: string = sid.trim().replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '');
    return DrawLastStore.dir() + '/draw_last_' + (safe.length > 0 ? safe : 'anon') + '.json';
  }

  static load(sid: string): DrawLast | undefined {
    if (DrawLastStore.dir().length === 0) {
      return undefined;
    }
    try {
      const path: string = DrawLastStore.pathFor(sid);
      if (!fs.accessSync(path)) {
        return undefined;
      }
      const text: string = fs.readTextSync(path);
      return DrawLastCodec.decode(JsonBlob.parse(text));
    } catch (e) {
      Log.w(TAG, '读取最近抽签失败');
      return undefined;
    }
  }

  static save(sid: string, result: DrawResult, at: number): void {
    const dir: string = DrawLastStore.dir();
    if (dir.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const text: string = JsonBlob.encode(DrawLastCodec.encode(result, at));
      const file = fs.openSync(DrawLastStore.pathFor(sid),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      Log.w(TAG, '写入最近抽签失败');
    }
  }
}
