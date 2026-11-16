import {
  Poll,
  PollAudience,
  PollDraft,
  PollMode,
  PollOption,
  PollResultVisibility,
  PollSettings,
  PollSummary,
  PollVoter,
  VoteLimits
} from './VoteModels';

const MINUTE: number = 60 * 1000;

/** 投票纯逻辑（与网页/安卓同口径）。 */
export class VoteLogic {
  /** 是否已结束（状态 closed 或已过截止）。 */
  static effectiveClosed(poll: PollSummary, nowMillis: number): boolean {
    if (poll.closed || poll.status.trim().toLowerCase() === 'closed') {
      return true;
    }
    return poll.deadline > 0 && nowMillis >= poll.deadline;
  }

  /** 结果是否可见。 */
  static resultsVisible(settings: PollSettings, closed: boolean, hasVoted: boolean): boolean {
    if (settings.resultVisibility === PollResultVisibility.ALWAYS) {
      return true;
    }
    if (settings.resultVisibility === PollResultVisibility.AFTER_CLOSE) {
      return closed;
    }
    return hasVoted;
  }

  static canChangeVote(settings: PollSettings, closed: boolean, hasVoted: boolean): boolean {
    return !closed && hasVoted && settings.allowChange;
  }

  /** 不能投票的原因（'' = 可以投）。 */
  static voteBlockReason(poll: PollSummary, settings: PollSettings, closed: boolean, hasVoted: boolean): string {
    if (closed) {
      return '投票已结束';
    }
    if (hasVoted) {
      return settings.allowChange ? '' : '不可改票';
    }
    return '';
  }

  /** 选项校验（'' = 合法）。 */
  static validateChoices(settings: PollSettings, choices: string[], optionIds: string[]): string {
    if (choices.length === 0) {
      return '请至少选择 1 项';
    }
    if (!settings.multi && choices.length > 1) {
      return '单选投票只能选 1 项';
    }
    if (settings.multi && choices.length > settings.maxChoices) {
      return '最多选 ' + settings.maxChoices + ' 项';
    }
    for (let i = 0; i < choices.length; i++) {
      if (optionIds.indexOf(choices[i]) < 0) {
        return '选项无效';
      }
    }
    return '';
  }

  /** 截止倒计时（deadline=0 → 0）。 */
  static countdown(deadline: number, nowMillis: number): number {
    if (deadline <= 0) {
      return 0;
    }
    return Math.max(0, deadline - nowMillis);
  }

  static formatRemaining(millis: number): string {
    if (millis <= 0) {
      return '已截止';
    }
    const minutes: number = Math.floor(millis / MINUTE);
    if (minutes < 60) {
      const seconds: number = Math.floor((millis % MINUTE) / 1000);
      return '剩 ' + (minutes < 10 ? '0' + minutes : '' + minutes) + ':'
        + (seconds < 10 ? '0' + seconds : '' + seconds);
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return '剩 ' + hours + ' 小时';
    }
    const days: number = Math.floor(hours / 24);
    return '剩 ' + days + ' 天';
  }

  static deadlineText(deadline: number): string {
    return deadline > 0 ? '截止 ' + VoteLogic.formatAt(deadline) : '不限时';
  }

  static quickDeadline(nowMillis: number, minutes: number): number {
    return nowMillis + minutes * MINUTE;
  }

  static formatAt(millis: number): string {
    if (millis <= 0) {
      return '—';
    }
    const d: Date = new Date(millis);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  static percent(count: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    return Math.round(count / total * 1000) / 10;
  }

  static formatPercent(value: number): string {
    return value.toFixed(1) + '%';
  }

  /** 进行中在前、已结束按截止/创建倒序；组内按创建时间倒序。 */
  static sortPolls(polls: PollSummary[], nowMillis: number): PollSummary[] {
    const open: PollSummary[] = [];
    const closed: PollSummary[] = [];
    for (let i = 0; i < polls.length; i++) {
      if (VoteLogic.effectiveClosed(polls[i], nowMillis)) {
        closed.push(polls[i]);
      } else {
        open.push(polls[i]);
      }
    }
    open.sort((a: PollSummary, b: PollSummary) => b.createdAt - a.createdAt);
    closed.sort((a: PollSummary, b: PollSummary) => b.createdAt - a.createdAt);
    const out: PollSummary[] = [];
    for (let i = 0; i < open.length; i++) {
      out.push(open[i]);
    }
    for (let i = 0; i < closed.length; i++) {
      out.push(closed[i]);
    }
    return out;
  }

  static filterForTab(polls: PollSummary[], showClosed: boolean, nowMillis: number): PollSummary[] {
    const sorted: PollSummary[] = VoteLogic.sortPolls(polls, nowMillis);
    const out: PollSummary[] = [];
    for (let i = 0; i < sorted.length; i++) {
      const closed: boolean = VoteLogic.effectiveClosed(sorted[i], nowMillis);
      if (showClosed === closed) {
        out.push(sorted[i]);
      }
    }
    return out;
  }

  /** 草稿校验（返回中文错误；'' = 合法）。 */
  static validateDraft(draft: PollDraft, nowMillis: number): string {
    const title: string = draft.title.trim();
    if (title.length === 0) {
      return '请填写标题';
    }
    if (draft.id.length > 0 && !VoteLogic.isPollIdValid(draft.id)) {
      return '投票编号不合法';
    }
    if (title.length > VoteLimits.MAX_TITLE) {
      return '标题不能超过 ' + VoteLimits.MAX_TITLE + ' 字';
    }
    if (draft.description.trim().length > VoteLimits.MAX_DESCRIPTION) {
      return '说明不能超过 ' + VoteLimits.MAX_DESCRIPTION + ' 字';
    }
    const texts: string[] = [];
    for (let i = 0; i < draft.options.length; i++) {
      const text: string = draft.options[i].text.trim();
      if (text.length === 0) {
        continue;
      }
      if (text.length > VoteLimits.MAX_OPTION_TEXT) {
        return '选项不能超过 ' + VoteLimits.MAX_OPTION_TEXT + ' 字';
      }
      texts.push(text);
    }
    if (texts.length < VoteLimits.MIN_OPTIONS) {
      return '至少需要 ' + VoteLimits.MIN_OPTIONS + ' 个选项';
    }
    if (texts.length > VoteLimits.MAX_OPTIONS) {
      return '最多 ' + VoteLimits.MAX_OPTIONS + ' 个选项';
    }
    let imageChars: number = 0;
    for (let i = 0; i < draft.options.length; i++) {
      const img: string = draft.options[i].img;
      if (img.length === 0) {
        continue;
      }
      if (!img.startsWith('data:image/')) {
        return '选项配图格式不支持';
      }
      if (img.length > 150000) {
        return '单张配图过大（≤150000 字符）';
      }
      imageChars += img.length;
    }
    if (imageChars > 1600000) {
      return '配图总大小超限（≤1.6MB）';
    }
    for (let i = 0; i < texts.length; i++) {
      for (let j = i + 1; j < texts.length; j++) {
        if (texts[i] === texts[j]) {
          return '选项不能重复';
        }
      }
    }
    if (draft.deadline > 0 && draft.deadline <= nowMillis) {
      return '截止时间需晚于现在';
    }
    return '';
  }

  /** 生成投票 id（`poll_<ts>_<rand>`）。 */
  /** 服务端编号规则：`^p[a-z0-9]{4,32}$`。 */
  static isPollIdValid(id: string): boolean {
    return new RegExp('^p[a-z0-9]{4,32}$').test(id.trim());
  }

  /** 指定成员座号归一：1..70、去重、升序。 */
  static normalizeSeats(seats: number[]): number[] {
    const out: number[] = [];
    for (let i = 0; i < seats.length; i++) {
      const seat: number = Math.round(seats[i]);
      if (seat >= 1 && seat <= 70 && out.indexOf(seat) < 0) {
        out.push(seat);
      }
    }
    out.sort((a: number, b: number) => a - b);
    return out;
  }

  /** 可见范围校验：custom 至少 1 人（'' = 合法）。 */
  static validateAudience(audience: string, seats: number[]): string {
    if (audience === 'custom' && VoteLogic.normalizeSeats(seats).length === 0) {
      return '指定成员至少选 1 人';
    }
    return '';
  }

  /** 生成投票 id（`p` + base36(时间) + 随机后缀，≤33）。 */
  static newPollId(nowMillis: number): string {
    return ('p' + nowMillis.toString(36) + randomSuffix()).substring(0, 33);
  }

  static newOptionId(nowMillis: number, index: number): string {
    return ('o' + nowMillis.toString(36) + (index + 1) + randomSuffix()).substring(0, 24);
  }

  /** 只保留有文字的选项，并补 id。 */
  static normalizeOptions(options: PollOption[], nowMillis: number): PollOption[] {
    const out: PollOption[] = [];
    for (let i = 0; i < options.length; i++) {
      const option: PollOption = options[i];
      if (option.text.trim().length === 0) {
        continue;
      }
      const copy: PollOption = new PollOption();
      copy.id = option.id.trim().length > 0 ? option.id : VoteLogic.newOptionId(nowMillis, i);
      copy.text = option.text.trim();
      copy.desc = option.desc.trim();
      copy.img = option.img;
      out.push(copy);
    }
    return out;
  }

  /** 结果行：选项 + 票数 + 百分比 + 投票人姓名。 */
  static optionRows(detail: PollDetailView): PollOptionRow[] {
    const total: number = detail.total > 0 ? detail.total : 0;
    const rows: PollOptionRow[] = [];
    for (let i = 0; i < detail.poll.options.length; i++) {
      const option: PollOption = detail.poll.options[i];
      const count: number = detail.counts.get(option.id) !== undefined
        ? detail.counts.get(option.id) as number : 0;
      const row: PollOptionRow = new PollOptionRow();
      row.option = option;
      row.count = count;
      row.percent = VoteLogic.percent(count, total);
      const names: string[] = [];
      for (let v = 0; v < detail.voters.length; v++) {
        const voter: PollVoter = detail.voters[v];
        if (voter.choices.indexOf(option.id) >= 0 && voter.name.length > 0) {
          names.push(voter.name);
        }
      }
      row.voterNames = names;
      rows.push(row);
    }
    return rows;
  }
}

/** 详情视图（避免 UI 直接依赖 data 层类型名过多）。 */
export class PollDetailView {
  poll: Poll = new Poll();
  total: number = 0;
  counts: Map<string, number> = new Map<string, number>();
  voters: PollVoter[] = [];
}

export class PollOptionRow {
  option: PollOption = new PollOption();
  count: number = 0;
  percent: number = 0;
  voterNames: string[] = [];
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function randomSuffix(): string {
  const alphabet: string = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let out: string = '';
  for (let i = 0; i < 5; i++) {
    out += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return out;
}
