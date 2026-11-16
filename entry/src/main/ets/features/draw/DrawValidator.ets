import { DrawConfig, DrawError, DrawErrorCode, DrawPoolSource } from './DrawModels';

/** 排除序号解析结果。 */
export class ExcludedParse {
  numbers: Set<number> = new Set<number>();
  /** 无法解析的片段（最多保留前 3 个，避免提示过长）。 */
  invalidTokens: string[] = [];

  isValid(): boolean {
    return this.invalidTokens.length === 0;
  }
}

/** 参数校验结果：合法时给出候选号码（升序），非法时给出可展示错误。 */
export class DrawValidation {
  ok: boolean;
  numbers: number[];
  error: DrawError | undefined;

  constructor(ok: boolean, numbers: number[], error: DrawError | undefined) {
    this.ok = ok;
    this.numbers = numbers;
    this.error = error;
  }

  static valid(numbers: number[]): DrawValidation {
    return new DrawValidation(true, numbers, undefined);
  }

  static invalid(error: DrawError): DrawValidation {
    return new DrawValidation(false, [], error);
  }
}

/**
 * 抽签参数校验（纯函数）。
 *
 * 规则（与网页 doDraw() 对齐，个别处更严格）：
 * - 范围 1..999 且 start ≤ end；
 * - 个数 1..999；
 * - 排除序号支持 `3,7,10-12`（逗号/顿号/空白分隔，区间 `-`/`~`/`—`）；
 * - 候选池 = 范围 − 排除号；名单来源时再与名单座号取交集；
 * - 不重复时 个数 ≤ 池大小。
 */
export class DrawValidator {
  /** 解析排除序号文本；空文本 = 无排除。 */
  static parseExcluded(text: string): ExcludedParse {
    const result: ExcludedParse = new ExcludedParse();
    const tokens: string[] = text.split(new RegExp('[,，、;；\\s]+'));
    for (let i = 0; i < tokens.length; i++) {
      const token: string = tokens[i].trim();
      if (token.length === 0) {
        continue;
      }
      const rangeMatch: RegExpMatchArray | null = token.match(new RegExp('^(\\d+)\\s*[-~—]\\s*(\\d+)$'));
      if (rangeMatch !== null) {
        const from: number = Number(rangeMatch[1]);
        const to: number = Number(rangeMatch[2]);
        if (!Number.isFinite(from) || !Number.isFinite(to) || from > to
          || from < DrawConfig.MIN_NUMBER || to > DrawConfig.MAX_NUMBER) {
          if (result.invalidTokens.length < 3) {
            result.invalidTokens.push(token);
          }
        } else {
          for (let n = from; n <= to; n++) {
            result.numbers.add(n);
          }
        }
        continue;
      }
      if (new RegExp('^\\d+$').test(token)) {
        const n: number = Number(token);
        if (!Number.isFinite(n) || n < DrawConfig.MIN_NUMBER || n > DrawConfig.MAX_NUMBER) {
          if (result.invalidTokens.length < 3) {
            result.invalidTokens.push(token);
          }
        } else {
          result.numbers.add(n);
        }
      } else if (result.invalidTokens.length < 3) {
        result.invalidTokens.push(token);
      }
    }
    return result;
  }

  /** 校验并给出候选号码（升序）。`rosterSeats` 为空表示未提供班级名单。 */
  static validate(config: DrawConfig, rosterSeats: number[]): DrawValidation {
    if (config.start < DrawConfig.MIN_NUMBER || config.start > DrawConfig.MAX_NUMBER
      || config.end < DrawConfig.MIN_NUMBER || config.end > DrawConfig.MAX_NUMBER) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.RANGE_INVALID,
        '范围需在 ' + DrawConfig.MIN_NUMBER + '–' + DrawConfig.MAX_NUMBER + ' 之间'));
    }
    if (config.start > config.end) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.RANGE_INVALID, '起始值不能大于结束值'));
    }
    if (config.count < DrawConfig.MIN_COUNT || config.count > DrawConfig.MAX_COUNT) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.COUNT_INVALID,
        '抽取个数需在 ' + DrawConfig.MIN_COUNT + '–' + DrawConfig.MAX_COUNT + ' 之间'));
    }
    const excluded: ExcludedParse = DrawValidator.parseExcluded(config.excludedText);
    if (!excluded.isValid()) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.EXCLUSION_INVALID, '排除格式示例：3,7,10-12'));
    }

    let numbers: number[] = [];
    for (let n = config.start; n <= config.end; n++) {
      if (!excluded.numbers.has(n)) {
        numbers.push(n);
      }
    }
    if (config.poolSource === DrawPoolSource.ROSTER) {
      const seats: Set<number> = new Set<number>();
      for (let i = 0; i < rosterSeats.length; i++) {
        const seat: number = rosterSeats[i];
        if (seat >= DrawConfig.MIN_NUMBER && seat <= DrawConfig.MAX_NUMBER) {
          seats.add(seat);
        }
      }
      if (seats.size === 0) {
        return DrawValidation.invalid(new DrawError(DrawErrorCode.ROSTER_REQUIRED, '名单为空，请先选择班级名单'));
      }
      const filtered: number[] = [];
      for (let i = 0; i < numbers.length; i++) {
        if (seats.has(numbers[i])) {
          filtered.push(numbers[i]);
        }
      }
      numbers = filtered;
    }
    if (numbers.length === 0) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.POOL_EMPTY, '排除后没有可用序号，请调整范围或排除号'));
    }
    if (!config.allowDuplicates && config.count > numbers.length) {
      return DrawValidation.invalid(new DrawError(DrawErrorCode.COUNT_EXCEEDS_POOL,
        '最多可抽 ' + numbers.length + ' 个（可用池 ' + numbers.length + '）'));
    }
    return DrawValidation.valid(numbers);
  }
}
