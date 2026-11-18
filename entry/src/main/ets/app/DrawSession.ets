import { DrawResult } from '../features/draw/DrawModels';

/**
 * 本次会话的抽签结果（内存单例，不落盘）。
 *
 * 用途：分组工具的「上一步抽签序号」来源——与网页的「抽签 → 分组」工作流一致。
 * 进程被杀后清空（分组会提示先抽签）。
 */
export class DrawSession {
  static lastResult: DrawResult | undefined = undefined;

  static set(result: DrawResult | undefined): void {
    DrawSession.lastResult = result;
  }

  static clear(): void {
    DrawSession.lastResult = undefined;
  }
}
