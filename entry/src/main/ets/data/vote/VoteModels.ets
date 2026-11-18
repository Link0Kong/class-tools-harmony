/** 投票上限（对齐 `web/vote/CONTRACT.md` §1）。 */
export class VoteLimits {
  static readonly MAX_TITLE: number = 80;
  static readonly MAX_DESCRIPTION: number = 500;
  static readonly MIN_OPTIONS: number = 2;
  static readonly MAX_OPTIONS: number = 20;
  static readonly MAX_OPTION_TEXT: number = 80;
  static readonly MAX_OPTION_DESC: number = 200;
  static readonly MAX_CHOICES: number = 20;
  static readonly MAX_LIST: number = 100;
  /** 快捷限时（分钟）。 */
  static readonly QUICK_MINUTES: number[] = [5, 10, 30, 60, 120];
}

export enum PollMode {
  QUICK = 'quick',
  LONG = 'long'
}

export function pollModeLabel(mode: string): string {
  return mode === PollMode.QUICK ? '限时' : '长时';
}

export enum PollResultVisibility {
  ALWAYS = 'always',
  AFTER_VOTE = 'afterVote',
  AFTER_CLOSE = 'afterClose'
}

export function visibilityLabel(value: string): string {
  if (value === PollResultVisibility.ALWAYS) {
    return '结果始终可见';
  }
  if (value === PollResultVisibility.AFTER_CLOSE) {
    return '截止后可见';
  }
  return '投票后可见';
}

export enum PollAudience {
  ALL = 'all',
  COMMITTEE = 'committee',
  LEAGUE = 'league',
  CUSTOM = 'custom'
}

export function audienceLabel(value: string): string {
  if (value === PollAudience.COMMITTEE) {
    return '班委可见';
  }
  if (value === PollAudience.LEAGUE) {
    return '团员可见';
  }
  if (value === PollAudience.CUSTOM) {
    return '指定成员';
  }
  return '全班可见';
}

/** 可见范围标签（all 不显示）。 */
export function audienceTag(value: string, count: number): string {
  if (value === PollAudience.COMMITTEE) {
    return '班委可见';
  }
  if (value === PollAudience.LEAGUE) {
    return '团员可见';
  }
  if (value === PollAudience.CUSTOM) {
    return count > 0 ? '指定 ' + count + ' 人' : '指定成员';
  }
  return '';
}

export class PollSettings {
  multi: boolean = false;
  maxChoices: number = 1;
  anonymous: boolean = true;
  allowChange: boolean = true;
  resultVisibility: string = PollResultVisibility.AFTER_VOTE;

  normalized(optionCount: number): PollSettings {
    const next: PollSettings = new PollSettings();
    next.multi = this.multi && optionCount >= 2;
    next.maxChoices = !next.multi ? 1
      : Math.min(VoteLimits.MAX_CHOICES, Math.max(2, Math.min(this.maxChoices, Math.max(2, optionCount))));
    next.anonymous = this.anonymous;
    next.allowChange = this.allowChange;
    next.resultVisibility = this.resultVisibility;
    return next;
  }

  /** 规则标签（不含可见范围）。 */
  tags(hasVoted: boolean, closed: boolean, resultsHidden: boolean): string[] {
    const out: string[] = [];
    out.push(this.multi ? '多选' : '单选');
    if (this.multi) {
      out.push('最多 ' + this.maxChoices + ' 项');
    }
    out.push(this.anonymous ? '匿名' : '实名');
    if (this.allowChange && !closed) {
      out.push('可改票');
    }
    if (resultsHidden) {
      out.push(visibilityLabel(this.resultVisibility));
    }
    return out;
  }
}

export class PollOption {
  id: string = '';
  text: string = '';
  desc: string = '';
  img: string = '';
}

export class PollVoter {
  name: string = '';
  choices: string[] = [];
}

export class PollSummary {
  id: string = '';
  title: string = '';
  description: string = '';
  mode: string = PollMode.LONG;
  ownerName: string = '';
  settings: PollSettings = new PollSettings();
  deadline: number = 0;
  status: string = 'open';
  closedAt: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  audience: string = PollAudience.ALL;
  audienceCount: number = 0;
  closed: boolean = false;
  total: number = 0;
  counts: Map<string, number> = new Map<string, number>();
  hasVoted: boolean = false;
}

export class Poll extends PollSummary {
  options: PollOption[] = [];
  audienceSeats: number[] = [];
}

export class PollList {
  polls: PollSummary[] = [];
  serverNow: number = 0;
  hasMore: boolean = false;
}

export class PollDetail {
  poll: Poll = new Poll();
  serverNow: number = 0;
  closed: boolean = false;
  total: number = 0;
  counts: Map<string, number> = new Map<string, number>();
  hasVoted: boolean = false;
  myChoices: string[] = [];
  resultsHidden: boolean = false;
  mine: boolean = false;
  canManage: boolean = false;
  voters: PollVoter[] = [];
}

/** 发起投票草稿（UI 表单 → RPC body）。 */
export class PollDraft {
  id: string = '';
  title: string = '';
  description: string = '';
  mode: string = PollMode.LONG;
  options: PollOption[] = [];
  settings: PollSettings = new PollSettings();
  deadline: number = 0;
  audience: string = PollAudience.ALL;
  audienceSeats: number[] = [];
}

export class VoteResult {
  ok: boolean = false;
  message: string = '';
  pollId: string = '';

  constructor(ok: boolean, message: string, pollId: string) {
    this.ok = ok;
    this.message = message;
    this.pollId = pollId;
  }
}

export class PollListResult {
  ok: boolean = false;
  message: string = '';
  list: PollList = new PollList();

  constructor(ok: boolean, message: string, list: PollList) {
    this.ok = ok;
    this.message = message;
    this.list = list;
  }
}

export class PollDetailResult {
  ok: boolean = false;
  message: string = '';
  detail: PollDetail = new PollDetail();

  constructor(ok: boolean, message: string, detail: PollDetail) {
    this.ok = ok;
    this.message = message;
    this.detail = detail;
  }
}
