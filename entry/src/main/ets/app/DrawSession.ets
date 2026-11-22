import { DrawResult } from '../features/draw/DrawModels';
import { DrawLast } from '../features/draw/DrawLastCodec';
import { DrawLastStore } from '../data/draw/DrawLastStore';
import { Services } from './Services';

/**
 * 最近一次抽签结果（内存缓存 + 本机持久化）。
 *
 * - `set()`：抽签成功/重抽/剔除补抽/排序后更新当前结果，并写入本机（按 sid 隔离）；
 * - `load()`：分组页进入时读取；内存命中优先，未命中回落本机文件（跨进程重启仍可用）；
 * - `clear()`：只清内存（契约 §3：重置抽签保留上一次成功结果供分组沿用）。
 *
 * 抽签与分组是两个独立工具：抽签页不再向分组页传递/跳转，分组页自己读本机快照。
 */
export class DrawSession {
  static lastResult: DrawResult | undefined = undefined;
  static lastAt: number = 0;

  /** 最近一次从本机读取所用的 sid（登录身份切换后需要重新读）。 */
  private static loadedSid: string = '';

  /** 内存结果所属 sid（避免切换账号后串用上一个账号的抽签结果）。 */
  private static resultSid: string = '';

  static set(result: DrawResult | undefined): void {
    DrawSession.lastResult = result;
    if (result === undefined) {
      DrawSession.resultSid = '';
      DrawSession.loadedSid = '';
      return;
    }
    const at: number = Date.now();
    DrawSession.lastAt = at;
    DrawSession.resultSid = Services.currentSid.trim();
    DrawLastStore.save(Services.currentSid, result, at);
  }

  static async load(): Promise<DrawResult | undefined> {
    const sid: string = Services.currentSid.trim();
    if (DrawSession.lastResult !== undefined && DrawSession.resultSid === sid) {
      return DrawSession.lastResult;
    }
    if (DrawSession.lastResult !== undefined && DrawSession.resultSid !== sid) {
      // 账号已切换：丢弃上一个账号的内存结果，改为读当前账号的本机快照。
      DrawSession.lastResult = undefined;
      DrawSession.lastAt = 0;
      DrawSession.resultSid = '';
      DrawSession.loadedSid = '';
    }
    if (DrawSession.loadedSid === sid) {
      return DrawSession.lastResult;
    }
    const last: DrawLast | undefined = DrawLastStore.load(sid);
    DrawSession.loadedSid = sid;
    if (last !== undefined) {
      DrawSession.lastResult = last.result;
      DrawSession.lastAt = last.at;
      DrawSession.resultSid = sid;
    }
    return DrawSession.lastResult;
  }

  /** 仅清空内存缓存；本机快照保留，下次 `load()` 仍可读到。 */
  static clear(): void {
    DrawSession.lastResult = undefined;
    DrawSession.lastAt = 0;
    DrawSession.resultSid = '';
    DrawSession.loadedSid = '';
  }
}
