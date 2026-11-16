/** 结果排序模式（wire 值必须与 userdata.draw.sort 对齐：draw|num|desc|rand）。 */
export enum DrawSortMode {
  DRAW_ORDER = 'draw',
  ASCENDING = 'num',
  DESCENDING = 'desc',
  RANDOM = 'rand'
}

export function drawSortFromWire(wire: string): DrawSortMode {
  if (wire === 'num') {
    return DrawSortMode.ASCENDING;
  }
  if (wire === 'desc') {
    return DrawSortMode.DESCENDING;
  }
  if (wire === 'rand') {
    return DrawSortMode.RANDOM;
  }
  return DrawSortMode.DRAW_ORDER;
}

export function drawSortLabel(mode: DrawSortMode): string {
  if (mode === DrawSortMode.ASCENDING) {
    return '从小到大';
  }
  if (mode === DrawSortMode.DESCENDING) {
    return '从大到小';
  }
  if (mode === DrawSortMode.RANDOM) {
    return '随机';
  }
  return '按抽取顺序';
}

/** 候选池来源：纯号码范围 / 班级名单（与范围取交集）。RANGE 以外不跨端持久化。 */
export enum DrawPoolSource {
  RANGE = 'range',
  ROSTER = 'roster'
}

/** 抽签参数（表单状态 + userdata.draw 同步的唯一真源）。 */
export class DrawConfig {
  static readonly DEFAULT_START: number = 1;
  static readonly DEFAULT_END: number = 70;
  static readonly DEFAULT_COUNT: number = 10;
  static readonly MIN_NUMBER: number = 1;
  static readonly MAX_NUMBER: number = 999;
  static readonly MIN_COUNT: number = 1;
  static readonly MAX_COUNT: number = 999;

  start: number = DrawConfig.DEFAULT_START;
  end: number = DrawConfig.DEFAULT_END;
  count: number = DrawConfig.DEFAULT_COUNT;
  allowDuplicates: boolean = false;
  /** 排除序号原始文本（支持 `3,7,10-12`），持久化时原样保存。 */
  excludedText: string = '';
  sort: DrawSortMode = DrawSortMode.DRAW_ORDER;
  poolSource: DrawPoolSource = DrawPoolSource.RANGE;

  copy(): DrawConfig {
    const next: DrawConfig = new DrawConfig();
    next.start = this.start;
    next.end = this.end;
    next.count = this.count;
    next.allowDuplicates = this.allowDuplicates;
    next.excludedText = this.excludedText;
    next.sort = this.sort;
    next.poolSource = this.poolSource;
    return next;
  }
}

/** 候选/结果条目：序号 + 可选姓名（名单来源时带姓名）。 */
export class DrawEntry {
  number: number = 0;
  name: string = '';

  constructor(number: number = 0, name: string = '') {
    this.number = number;
    this.name = name;
  }

  label(): string {
    return this.name.length > 0 ? this.number + ' ' + this.name : '' + this.number;
  }
}

/** 剔除重抽记录：被剔除的条目 + 补抽条目（未补抽为空）。 */
export class DrawRemoveLog {
  removed: DrawEntry;
  added: DrawEntry | undefined;

  constructor(removed: DrawEntry, added: DrawEntry | undefined) {
    this.removed = removed;
    this.added = added;
  }
}

/** 一次抽签的完整结果（含候选池与参数快照，便于结果单/导出/重抽）。 */
export class DrawResult {
  entries: DrawEntry[] = [];
  pool: DrawEntry[] = [];
  config: DrawConfig = new DrawConfig();
  log: DrawRemoveLog[] = [];

  copy(): DrawResult {
    const next: DrawResult = new DrawResult();
    next.entries = this.entries.slice(0);
    next.pool = this.pool.slice(0);
    next.config = this.config.copy();
    next.log = this.log.slice(0);
    return next;
  }
}

export enum DrawErrorCode {
  RANGE_INVALID = 'range_invalid',
  COUNT_INVALID = 'count_invalid',
  EXCLUSION_INVALID = 'exclusion_invalid',
  POOL_EMPTY = 'pool_empty',
  COUNT_EXCEEDS_POOL = 'count_exceeds_pool',
  ROSTER_REQUIRED = 'roster_required',
  INVALID_STEP = 'invalid_step',
  INVALID_INDEX = 'invalid_index'
}

export class DrawError {
  code: DrawErrorCode;
  message: string;

  constructor(code: DrawErrorCode, message: string) {
    this.code = code;
    this.message = message;
  }
}
