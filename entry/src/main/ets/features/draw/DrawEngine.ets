import { DrawConfig, DrawEntry, DrawError, DrawErrorCode, DrawRemoveLog, DrawResult, DrawSortMode } from './DrawModels';
import { DrawRandom, shuffled, shuffledInts } from './DrawRandom';
import { DrawValidation, DrawValidator } from './DrawValidator';

/** 抽签执行结果。 */
export class DrawOutcome {
  ok: boolean;
  result: DrawResult | undefined;
  error: DrawError | undefined;

  constructor(ok: boolean, result: DrawResult | undefined, error: DrawError | undefined) {
    this.ok = ok;
    this.result = result;
    this.error = error;
  }

  static success(result: DrawResult): DrawOutcome {
    return new DrawOutcome(true, result, undefined);
  }

  static failure(error: DrawError): DrawOutcome {
    return new DrawOutcome(false, undefined, error);
  }
}

/**
 * 抽签引擎（纯函数 + 注入随机源，可复现）。
 *
 * 算法对齐网页 doDraw()：
 * - 池 = 范围 − 排除号（名单来源再∩名单）；
 * - 不重复：Fisher-Yates 洗牌后取前 count 个；允许重复：count 次独立随机；
 * - 排序：按抽取顺序 / 从小到大 / 从大到小 / 随机重排；
 * - 剔除重抽：移除指定项后，从「池 − 当前结果」补抽一个（允许重复时从全池补），追加 log。
 */
export class DrawEngine {
  /** 候选号码 → 带姓名条目。 */
  static entriesFor(numbers: number[], nameOf: (n: number) => string): DrawEntry[] {
    const out: DrawEntry[] = [];
    for (let i = 0; i < numbers.length; i++) {
      const name: string = nameOf(numbers[i]).trim();
      out.push(new DrawEntry(numbers[i], name));
    }
    return out;
  }

  /** 校验 + 抽签（首抽入口）。 */
  static draw(config: DrawConfig, rosterSeats: number[], nameOf: (n: number) => string,
    random: DrawRandom): DrawOutcome {
    const validation: DrawValidation = DrawValidator.validate(config, rosterSeats);
    if (!validation.ok) {
      const error: DrawError = validation.error !== undefined
        ? validation.error
        : new DrawError(DrawErrorCode.RANGE_INVALID, '参数不合法');
      return DrawOutcome.failure(error);
    }
    const candidates: DrawEntry[] = DrawEngine.entriesFor(validation.numbers, nameOf);
    return DrawEngine.drawFromCandidates(config, candidates, random);
  }

  /** 从已确定的候选池抽签（STEP2 预览后调用，保证候选与预览一致）。 */
  static drawFromCandidates(config: DrawConfig, candidates: DrawEntry[], random: DrawRandom): DrawOutcome {
    if (candidates.length === 0) {
      return DrawOutcome.failure(new DrawError(DrawErrorCode.POOL_EMPTY, '候选为空，请返回上一步调整参数'));
    }
    if (config.count < DrawConfig.MIN_COUNT || config.count > DrawConfig.MAX_COUNT) {
      return DrawOutcome.failure(new DrawError(DrawErrorCode.COUNT_INVALID,
        '抽取个数需在 ' + DrawConfig.MIN_COUNT + '–' + DrawConfig.MAX_COUNT + ' 之间'));
    }
    if (!config.allowDuplicates && config.count > candidates.length) {
      return DrawOutcome.failure(new DrawError(DrawErrorCode.COUNT_EXCEEDS_POOL,
        '最多可抽 ' + candidates.length + ' 个（可用池 ' + candidates.length + '）'));
    }
    const picked: DrawEntry[] = DrawEngine.pick(config, candidates, random);
    const ordered: DrawEntry[] = DrawEngine.sortEntries(picked, config.sort, random);
    const result: DrawResult = new DrawResult();
    result.entries = ordered;
    result.pool = candidates.slice(0);
    result.config = config.copy();
    result.log = [];
    return DrawOutcome.success(result);
  }

  /** 剔除指定下标并（可选）自动补抽；返回新结果（不可变）。 */
  static removeAndRedraw(result: DrawResult, index: number, autoRedraw: boolean,
    random: DrawRandom): DrawOutcome {
    if (index < 0 || index >= result.entries.length) {
      return DrawOutcome.failure(new DrawError(DrawErrorCode.INVALID_INDEX, '要剔除的项不存在'));
    }
    const removed: DrawEntry = result.entries[index];
    const remaining: DrawEntry[] = [];
    for (let i = 0; i < result.entries.length; i++) {
      if (i !== index) {
        remaining.push(result.entries[i]);
      }
    }
    const next: DrawResult = result.copy();
    next.log = result.log.slice(0);
    if (!autoRedraw) {
      next.entries = remaining;
      next.log.push(new DrawRemoveLog(removed, undefined));
      return DrawOutcome.success(next);
    }
    const used: Set<number> = new Set<number>();
    if (!result.config.allowDuplicates) {
      for (let i = 0; i < remaining.length; i++) {
        used.add(remaining[i].number);
      }
    }
    const available: DrawEntry[] = [];
    for (let i = 0; i < result.pool.length; i++) {
      if (!used.has(result.pool[i].number)) {
        available.push(result.pool[i]);
      }
    }
    let added: DrawEntry | undefined = undefined;
    if (available.length > 0) {
      added = available[random.nextInt(available.length)];
      remaining.push(added);
    }
    next.entries = remaining;
    next.log.push(new DrawRemoveLog(removed, added));
    return DrawOutcome.success(next);
  }

  /** 同参数重新抽一次（结果集合会变，保留原参数）。 */
  static reroll(result: DrawResult, random: DrawRandom): DrawOutcome {
    const outcome: DrawOutcome = DrawEngine.drawFromCandidates(result.config, result.pool, random);
    if (outcome.ok && outcome.result !== undefined) {
      outcome.result.config = result.config.copy();
    }
    return outcome;
  }

  /** 对已有结果应用排序模式（返回新数组，不改变集合）。 */
  static sortEntries(entries: DrawEntry[], mode: DrawSortMode, random: DrawRandom): DrawEntry[] {
    if (mode === DrawSortMode.ASCENDING) {
      const list: DrawEntry[] = entries.slice(0);
      list.sort((a: DrawEntry, b: DrawEntry) => a.number - b.number);
      return list;
    }
    if (mode === DrawSortMode.DESCENDING) {
      const list: DrawEntry[] = entries.slice(0);
      list.sort((a: DrawEntry, b: DrawEntry) => b.number - a.number);
      return list;
    }
    if (mode === DrawSortMode.RANDOM) {
      return shuffled<DrawEntry>(entries, random);
    }
    return entries;
  }

  private static pick(config: DrawConfig, candidates: DrawEntry[], random: DrawRandom): DrawEntry[] {
    const out: DrawEntry[] = [];
    if (config.allowDuplicates) {
      for (let i = 0; i < config.count; i++) {
        out.push(candidates[random.nextInt(candidates.length)]);
      }
      return out;
    }
    const order: number[] = shuffledInts(candidates.length, random);
    for (let i = 0; i < config.count; i++) {
      out.push(candidates[order[i]]);
    }
    return out;
  }
}
