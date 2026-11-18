/** 成员来源。 */
export enum GroupSource {
  /** 上一步抽签结果（带序号/可选姓名）。 */
  PREV = 'prev',
  /** 班级名单（按座号选择）。 */
  NAMES = 'names'
}

export function groupSourceFromWire(wire: string): GroupSource {
  const v: string = wire.trim();
  if (v === 'names' || v === 'pick' || v === 'paste' || v === 'roster') {
    return GroupSource.NAMES;
  }
  return GroupSource.PREV;
}

export function groupSourceLabel(source: GroupSource): string {
  return source === GroupSource.NAMES ? '班级名单' : '上一步抽签序号';
}

/** 分组方式。 */
export enum GroupMode {
  GROUPS = 'groups',
  PER_GROUP = 'pergroup'
}

export function groupModeFromWire(wire: string): GroupMode {
  const v: string = wire.trim();
  if (v === 'pergroup' || v === 'per' || v === 'size') {
    return GroupMode.PER_GROUP;
  }
  return GroupMode.GROUPS;
}

export function groupModeLabel(mode: GroupMode): string {
  return mode === GroupMode.PER_GROUP ? '按每组人数' : '按组数';
}

/** 一个可分组的学生：座号 + 可选姓名。 */
export class GroupMember {
  seat: number = 0;
  name: string = '';

  constructor(seat: number = 0, name: string = '') {
    this.seat = seat;
    this.name = name;
  }

  label(): string {
    return this.name.length > 0 ? this.seat + ' ' + this.name : '' + this.seat;
  }
}

/** 分组参数（表单状态 + userdata.group 持久化唯一真源）。 */
export class GroupConfig {
  static readonly DEFAULT_N: number = 4;
  static readonly MIN_GROUPS: number = 2;
  static readonly MIN_PER_GROUP: number = 1;
  static readonly MAX_PER_GROUP: number = 99;

  source: GroupSource = GroupSource.PREV;
  mode: GroupMode = GroupMode.GROUPS;
  /** 组数（GROUPS）或每组人数（PER_GROUP）。 */
  n: number = GroupConfig.DEFAULT_N;
  /** 是否打乱成员再分组（Fisher-Yates）。 */
  shuffle: boolean = false;
  /** 班级名单来源时已选座号（升序去重；blob 原样保存）。 */
  selectedSeats: number[] = [];

  copy(): GroupConfig {
    const next: GroupConfig = new GroupConfig();
    next.source = this.source;
    next.mode = this.mode;
    next.n = this.n;
    next.shuffle = this.shuffle;
    next.selectedSeats = this.selectedSeats.slice(0);
    return next;
  }

  /** 规范化 n：GROUPS 夹到 [2, 成员数]，PER_GROUP 夹到 [1, 99]。 */
  normalizedN(memberCount: number): number {
    if (this.mode === GroupMode.PER_GROUP) {
      return Math.min(Math.max(this.n, GroupConfig.MIN_PER_GROUP), GroupConfig.MAX_PER_GROUP);
    }
    const upper: number = Math.max(GroupConfig.MIN_GROUPS, memberCount);
    return Math.min(Math.max(this.n, GroupConfig.MIN_GROUPS), upper);
  }
}

/** 一组结果（index 从 1 开始）。 */
export class MemberGroup {
  index: number = 1;
  members: GroupMember[] = [];

  constructor(index: number = 1, members: GroupMember[] = []) {
    this.index = index;
    this.members = members;
  }

  size(): number {
    return this.members.length;
  }

  label(): string {
    return '第 ' + this.index + ' 组';
  }
}

/** 分组参数快照（导出卡参数区 + 结果页摘要）。 */
export class GroupConfigSnapshot {
  sourceLabel: string = '';
  modeLabel: string = '';
  total: number = 0;
  groupCount: number = 0;
  innerLabel: string = '';
}

/** 一次分组结果。 */
export class GroupResult {
  groups: MemberGroup[] = [];
  config: GroupConfig = new GroupConfig();
  snapshot: GroupConfigSnapshot = new GroupConfigSnapshot();

  totalMembers(): number {
    let sum: number = 0;
    for (let i = 0; i < this.groups.length; i++) {
      sum += this.groups[i].members.length;
    }
    return sum;
  }
}

/** 分组向导步骤（配置 → 结果）。 */
export enum GroupStep {
  CONFIG = 1,
  RESULT = 2
}

/** 向导状态。 */
export class GroupWorkflowState {
  step: GroupStep = GroupStep.CONFIG;
  config: GroupConfig = new GroupConfig();
  result: GroupResult | undefined = undefined;

  copy(): GroupWorkflowState {
    const next: GroupWorkflowState = new GroupWorkflowState();
    next.step = this.step;
    next.config = this.config.copy();
    next.result = this.result;
    return next;
  }
}

export enum GroupErrorCode {
  NO_MEMBERS = 'no_members',
  MEMBERS_TOO_FEW = 'members_too_few',
  COUNT_INVALID = 'count_invalid',
  ROSTER_EMPTY = 'roster_empty',
  INVALID_STEP = 'invalid_step'
}

export class GroupError {
  code: GroupErrorCode;
  message: string;

  constructor(code: GroupErrorCode, message: string) {
    this.code = code;
    this.message = message;
  }
}

export class GroupValidation {
  ok: boolean;
  members: GroupMember[];
  error: GroupError | undefined;

  constructor(ok: boolean, members: GroupMember[], error: GroupError | undefined) {
    this.ok = ok;
    this.members = members;
    this.error = error;
  }

  static valid(members: GroupMember[]): GroupValidation {
    return new GroupValidation(true, members, undefined);
  }

  static invalid(error: GroupError): GroupValidation {
    return new GroupValidation(false, [], error);
  }
}

export class GroupTransition {
  ok: boolean;
  state: GroupWorkflowState | undefined;
  error: GroupError | undefined;

  constructor(ok: boolean, state: GroupWorkflowState | undefined, error: GroupError | undefined) {
    this.ok = ok;
    this.state = state;
    this.error = error;
  }

  static next(state: GroupWorkflowState): GroupTransition {
    return new GroupTransition(true, state, undefined);
  }

  static rejected(error: GroupError): GroupTransition {
    return new GroupTransition(false, undefined, error);
  }
}
