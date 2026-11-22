import {
  GroupConfig,
  GroupConfigSnapshot,
  GroupError,
  GroupErrorCode,
  GroupMember,
  GroupMode,
  GroupResult,
  GroupSource,
  GroupValidation,
  MemberGroup
} from './GroupModels';

/** 分组随机源（可注入 seed，便于单测复现）。 */
export interface GroupRandom {
  nextInt(bound: number): number;
}

/** 固定 seed 的随机源（mulberry32，与抽签同算法）。 */
export class SeededGroupRandom implements GroupRandom {
  private state: number = 0;

  constructor(seed: number) {
    this.state = (seed >>> 0);
  }

  nextInt(bound: number): number {
    if (bound <= 0) {
      return 0;
    }
    this.state = (this.state + 0x6D2B79F5) >>> 0;
    let t: number = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t = (t ^ (t + Math.imul(t ^ (t >>> 7), t | 61))) >>> 0;
    const unit: number = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    return Math.floor(unit * bound);
  }
}

export function defaultGroupRandom(): GroupRandom {
  return new SeededGroupRandom(Date.now() % 2147483647);
}

/**
 * 分组引擎（纯函数，与小程序 `doGroup()` 同算法）：
 * 1. 组数：`groups` 模式 = clamp(n, 2, 成员数)；`pergroup` 模式 = ceil(成员数 / n)；
 * 2. 可选打乱：Fisher-Yates；
 * 3. 轮流分配 `out[i % groups].push(member)` → 各组人数差 ≤1（均衡）；
 * 4. 生成参数快照（导出/摘要用）。
 */
export class GroupEngine {
  /** 计算实际组数（供 UI 预览「将分成 N 组」）。 */
  static groupCount(memberCount: number, config: GroupConfig): number {
    if (memberCount <= 0) {
      return 0;
    }
    if (config.mode === GroupMode.PER_GROUP) {
      const per: number = Math.min(Math.max(config.n, GroupConfig.MIN_PER_GROUP), GroupConfig.MAX_PER_GROUP);
      return Math.max(Math.ceil(memberCount / per), 1);
    }
    return Math.min(Math.max(config.n, GroupConfig.MIN_GROUPS), Math.max(GroupConfig.MIN_GROUPS, memberCount));
  }

  /** 执行分组。成员为空时返回空结果（调用方应先校验）。 */
  static group(members: GroupMember[], config: GroupConfig, random: GroupRandom): GroupResult {
    const list: GroupMember[] = config.shuffle ? GroupEngine.shuffle(members, random) : members.slice(0);
    const groups: number = GroupEngine.groupCount(list.length, config);
    const buckets: GroupMember[][] = [];
    for (let i = 0; i < groups; i++) {
      buckets.push([]);
    }
    for (let i = 0; i < list.length; i++) {
      if (groups > 0) {
        buckets[i % groups].push(list[i]);
      }
    }
    const resultGroups: MemberGroup[] = [];
    for (let i = 0; i < buckets.length; i++) {
      resultGroups.push(new MemberGroup(i + 1, buckets[i]));
    }
    const result: GroupResult = new GroupResult();
    result.groups = resultGroups;
    result.config = config.copy();
    result.snapshot = GroupEngine.snapshotOf(config, resultGroups);
    return result;
  }

  /** Fisher-Yates（返回副本）。 */
  static shuffle(members: GroupMember[], random: GroupRandom): GroupMember[] {
    const list: GroupMember[] = members.slice(0);
    for (let i = list.length - 1; i > 0; i--) {
      const j: number = Math.min(Math.max(random.nextInt(i + 1), 0), i);
      const tmp: GroupMember = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  /** 参数快照（文案与 web/mp `cfg` 一致）。 */
  static snapshotOf(config: GroupConfig, groups: MemberGroup[]): GroupConfigSnapshot {
    let total: number = 0;
    for (let i = 0; i < groups.length; i++) {
      total += groups[i].members.length;
    }
    const snapshot: GroupConfigSnapshot = new GroupConfigSnapshot();
    snapshot.total = total;
    snapshot.groupCount = groups.length;
    snapshot.sourceLabel = config.source === GroupSource.NAMES
      ? '班级名单（' + total + ' 人）'
      : '最近抽签（' + total + ' 人）';
    snapshot.modeLabel = config.mode === GroupMode.PER_GROUP
      ? '按每组人数(' + config.n + ' 人)'
      : '按组数(' + groups.length + ' 组)';
    snapshot.innerLabel = config.shuffle ? '打乱后随机分配' : '按原顺序轮流分配';
    return snapshot;
  }

  /** 校验来源成员与参数（开始分组前调用）。 */
  static validate(members: GroupMember[], config: GroupConfig): GroupValidation {
    if (members.length === 0) {
      if (config.source === GroupSource.NAMES && config.selectedSeats.length === 0) {
        return GroupValidation.invalid(new GroupError(GroupErrorCode.ROSTER_EMPTY, '请先勾选班级名单成员'));
      }
      return GroupValidation.invalid(new GroupError(GroupErrorCode.NO_MEMBERS,
        '没有可分组的成员，请选择「最近抽签」或勾选班级名单'));
    }
    if (members.length < 2) {
      return GroupValidation.invalid(new GroupError(GroupErrorCode.MEMBERS_TOO_FEW, '成员不足 2 人，无法分组'));
    }
    if (config.mode === GroupMode.GROUPS) {
      const n: number = config.normalizedN(members.length);
      if (n < GroupConfig.MIN_GROUPS || n > members.length) {
        return GroupValidation.invalid(new GroupError(GroupErrorCode.COUNT_INVALID, '组数需在 2–' + members.length + ' 之间'));
      }
    } else if (config.n < GroupConfig.MIN_PER_GROUP || config.n > GroupConfig.MAX_PER_GROUP) {
      return GroupValidation.invalid(new GroupError(GroupErrorCode.COUNT_INVALID,
        '每组人数需在 ' + GroupConfig.MIN_PER_GROUP + '–' + GroupConfig.MAX_PER_GROUP + ' 之间'));
    }
    return GroupValidation.valid(members);
  }
}
