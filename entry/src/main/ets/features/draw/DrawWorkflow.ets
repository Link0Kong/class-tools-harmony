import { DrawConfig, DrawEntry, DrawError, DrawErrorCode, DrawResult, DrawSortMode } from './DrawModels';
import { DrawEngine, DrawOutcome } from './DrawEngine';
import { DrawRandom } from './DrawRandom';
import { DrawValidation, DrawValidator } from './DrawValidator';

/** 三步工作流：STEP1 配置 → STEP2 候选预览 → STEP3 结果。 */
export enum DrawStep {
  CONFIG = 1,
  PREVIEW = 2,
  RESULT = 3
}

export function drawStepTitle(step: DrawStep): string {
  if (step === DrawStep.PREVIEW) {
    return '候选';
  }
  if (step === DrawStep.RESULT) {
    return '结果';
  }
  return '配置';
}

/** 工作流状态（UI 持有，由 DrawWorkflow 纯函数迁移）。 */
export class DrawWorkflowState {
  step: DrawStep = DrawStep.CONFIG;
  config: DrawConfig = new DrawConfig();
  /** STEP2 预览的候选池（含姓名映射快照）。 */
  candidates: DrawEntry[] = [];
  /** STEP3 结果；未抽签为 undefined。 */
  result: DrawResult | undefined = undefined;

  copy(): DrawWorkflowState {
    const next: DrawWorkflowState = new DrawWorkflowState();
    next.step = this.step;
    next.config = this.config.copy();
    next.candidates = this.candidates.slice(0);
    next.result = this.result !== undefined ? this.result.copy() : undefined;
    return next;
  }
}

/** 状态迁移结果：成功给新状态，失败给可展示错误（不抛异常）。 */
export class DrawTransition {
  ok: boolean;
  state: DrawWorkflowState | undefined;
  error: DrawError | undefined;

  constructor(ok: boolean, state: DrawWorkflowState | undefined, error: DrawError | undefined) {
    this.ok = ok;
    this.state = state;
    this.error = error;
  }

  static next(state: DrawWorkflowState): DrawTransition {
    return new DrawTransition(true, state, undefined);
  }

  static rejected(error: DrawError): DrawTransition {
    return new DrawTransition(false, undefined, error);
  }
}

/**
 * 抽签工作流状态机（纯函数，无副作用）。
 *
 * 约束：
 * - 参数只在 STEP1 修改；进入 STEP2 后固化候选池，保证「预览的候选 = 实际抽签池」；
 * - 返回：STEP3→STEP2→STEP1；STEP2→STEP1 丢弃候选；STEP3→STEP2 丢弃结果；
 * - 剔除/重抽/排序只允许在 STEP3；排序写回 config.sort（随 userdata.draw 同步）。
 */
export class DrawWorkflow {
  static updateConfig(state: DrawWorkflowState, config: DrawConfig): DrawWorkflowState {
    if (state.step !== DrawStep.CONFIG) {
      return state;
    }
    const next: DrawWorkflowState = state.copy();
    next.config = config.copy();
    return next;
  }

  /** STEP1 → STEP2：校验参数并生成候选（失败行内报错，不进入下一步）。 */
  static toPreview(state: DrawWorkflowState, rosterSeats: number[],
    nameOf: (n: number) => string): DrawTransition {
    if (state.step !== DrawStep.CONFIG) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_STEP, '当前步骤不能重新生成候选'));
    }
    const validation: DrawValidation = DrawValidator.validate(state.config, rosterSeats);
    if (!validation.ok) {
      const error: DrawError = validation.error !== undefined
        ? validation.error
        : new DrawError(DrawErrorCode.RANGE_INVALID, '参数不合法');
      return DrawTransition.rejected(error);
    }
    const next: DrawWorkflowState = state.copy();
    next.step = DrawStep.PREVIEW;
    next.candidates = DrawEngine.entriesFor(validation.numbers, nameOf);
    next.result = undefined;
    return DrawTransition.next(next);
  }

  /** STEP2 → STEP3：从固化的候选池抽签。 */
  static startDraw(state: DrawWorkflowState, random: DrawRandom): DrawTransition {
    if (state.step !== DrawStep.PREVIEW) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_STEP, '请先预览候选再开始抽签'));
    }
    const outcome: DrawOutcome = DrawEngine.drawFromCandidates(state.config, state.candidates, random);
    if (!outcome.ok || outcome.result === undefined) {
      const error: DrawError = outcome.error !== undefined
        ? outcome.error
        : new DrawError(DrawErrorCode.POOL_EMPTY, '抽签失败');
      return DrawTransition.rejected(error);
    }
    const next: DrawWorkflowState = state.copy();
    next.step = DrawStep.RESULT;
    next.result = outcome.result;
    return DrawTransition.next(next);
  }

  /** 返回上一步；STEP1 返回原状态（由调用方决定是否退出页面）。 */
  static back(state: DrawWorkflowState): DrawWorkflowState {
    const next: DrawWorkflowState = state.copy();
    if (state.step === DrawStep.PREVIEW) {
      next.step = DrawStep.CONFIG;
      next.candidates = [];
    } else if (state.step === DrawStep.RESULT) {
      next.step = DrawStep.PREVIEW;
      next.result = undefined;
    }
    return next;
  }

  /** STEP3：剔除第 index 项并按 autoRedraw 决定是否补抽。 */
  static removeAndRedraw(state: DrawWorkflowState, index: number, autoRedraw: boolean,
    random: DrawRandom): DrawTransition {
    if (state.step !== DrawStep.RESULT) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_STEP, '只有结果页可以剔除重抽'));
    }
    if (state.result === undefined) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_INDEX, '还没有抽签结果'));
    }
    const outcome: DrawOutcome = DrawEngine.removeAndRedraw(state.result, index, autoRedraw, random);
    if (!outcome.ok || outcome.result === undefined) {
      const error: DrawError = outcome.error !== undefined
        ? outcome.error
        : new DrawError(DrawErrorCode.INVALID_INDEX, '剔除失败');
      return DrawTransition.rejected(error);
    }
    const next: DrawWorkflowState = state.copy();
    next.result = outcome.result;
    return DrawTransition.next(next);
  }

  /** STEP3：切换排序模式（同步写回 config.sort）。 */
  static changeSort(state: DrawWorkflowState, mode: DrawSortMode, random: DrawRandom): DrawTransition {
    if (state.step !== DrawStep.RESULT) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_STEP, '只有结果页可以调整排序'));
    }
    if (state.result === undefined) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_INDEX, '还没有抽签结果'));
    }
    const next: DrawWorkflowState = state.copy();
    next.config.sort = mode;
    const sorted: DrawEntry[] = DrawEngine.sortEntries(state.result.entries, mode, random);
    const result: DrawResult = state.result.copy();
    result.entries = sorted;
    result.config = next.config.copy();
    next.result = result;
    return DrawTransition.next(next);
  }

  /** STEP3：同参数重新抽一次（结果集合变化，log 清空）。 */
  static reroll(state: DrawWorkflowState, random: DrawRandom): DrawTransition {
    if (state.step !== DrawStep.RESULT) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_STEP, '只有结果页可以重新抽签'));
    }
    if (state.result === undefined) {
      return DrawTransition.rejected(new DrawError(DrawErrorCode.INVALID_INDEX, '还没有抽签结果'));
    }
    const outcome: DrawOutcome = DrawEngine.reroll(state.result, random);
    if (!outcome.ok || outcome.result === undefined) {
      const error: DrawError = outcome.error !== undefined
        ? outcome.error
        : new DrawError(DrawErrorCode.POOL_EMPTY, '重抽失败');
      return DrawTransition.rejected(error);
    }
    const next: DrawWorkflowState = state.copy();
    next.result = outcome.result;
    return DrawTransition.next(next);
  }

  /** 重置回 STEP1（保留参数，清空候选与结果）。 */
  static reset(state: DrawWorkflowState): DrawWorkflowState {
    const next: DrawWorkflowState = state.copy();
    next.step = DrawStep.CONFIG;
    next.candidates = [];
    next.result = undefined;
    return next;
  }
}
