/** 通知模块开关（本机 preferences 存储，按账号分桶）。 */
export class NotifySettings {
  master: boolean = false;
  liveActivities: boolean = true;
  homeworkNew: boolean = true;
  homeworkDue: boolean = true;
  classRemind: boolean = true;
  noticeNew: boolean = true;
  noticeDeadline: boolean = true;
  noticeSignup: boolean = true;
  voteNew: boolean = true;
  voteResult: boolean = true;
  waterDeduct: boolean = true;
  /** 作业/通知截止与投票结果的统一提前分钟数。 */
  leadMinutes: number = 60;
  classLeadMinutes: number = 10;
  breakLeadMinutes: number = 3;
  static readonly BREAK_LEAD_OPTIONS: number[] = [1, 3, 5, 10];

  static normalizeBreakLead(value: number): number {
    return NotifySettings.BREAK_LEAD_OPTIONS.includes(value) ? value : 3;
  }

  static readonly LEAD_OPTIONS: number[] = [10, 30, 60, 120, 1440];
  static readonly CLASS_LEAD_OPTIONS: number[] = [5, 10, 15, 30];

  static normalizeClassLead(value: number): number {
    for (let i = 0; i < NotifySettings.CLASS_LEAD_OPTIONS.length; i++) {
      if (NotifySettings.CLASS_LEAD_OPTIONS[i] === value) {
        return value;
      }
    }
    return 10;
  }

  static normalizeLead(value: number): number {
    for (let i = 0; i < NotifySettings.LEAD_OPTIONS.length; i++) {
      if (NotifySettings.LEAD_OPTIONS[i] === value) {
        return value;
      }
    }
    return 60;
  }

  anyModule(): boolean {
    return this.homeworkNew || this.homeworkDue || this.classRemind || this.noticeNew
      || this.noticeDeadline || this.noticeSignup || this.voteNew || this.voteResult || this.waterDeduct;
  }

  active(): boolean {
    return this.master && this.anyModule();
  }

  enabledCount(): number {
    let n: number = 0;
    if (this.homeworkNew) {
      n += 1;
    }
    if (this.homeworkDue) {
      n += 1;
    }
    if (this.classRemind) {
      n += 1;
    }
    if (this.noticeNew) {
      n += 1;
    }
    if (this.noticeDeadline) {
      n += 1;
    }
    if (this.noticeSignup) {
      n += 1;
    }
    if (this.voteNew) {
      n += 1;
    }
    if (this.voteResult) {
      n += 1;
    }
    if (this.waterDeduct) {
      n += 1;
    }
    return n;
  }

  copy(): NotifySettings {
    const next: NotifySettings = new NotifySettings();
    next.master = this.master;
    next.liveActivities = this.liveActivities;
    next.homeworkNew = this.homeworkNew;
    next.homeworkDue = this.homeworkDue;
    next.classRemind = this.classRemind;
    next.noticeNew = this.noticeNew;
    next.noticeDeadline = this.noticeDeadline;
    next.noticeSignup = this.noticeSignup;
    next.voteNew = this.voteNew;
    next.voteResult = this.voteResult;
    next.waterDeduct = this.waterDeduct;
    next.leadMinutes = NotifySettings.normalizeLead(this.leadMinutes);
    next.breakLeadMinutes = NotifySettings.normalizeBreakLead(this.breakLeadMinutes);
    next.classLeadMinutes = NotifySettings.normalizeClassLead(this.classLeadMinutes);
    return next;
  }

  toJson(): string {
    return JSON.stringify(this.copy());
  }

  static fromJson(raw: string): NotifySettings {
    const out: NotifySettings = new NotifySettings();
    if (raw.trim().length === 0) {
      return out;
    }
    try {
      const obj: NotifySettings = JSON.parse(raw) as NotifySettings;
      out.master = obj.master === true;
      out.liveActivities = obj.liveActivities !== false;
      out.homeworkNew = obj.homeworkNew !== false;
      out.homeworkDue = obj.homeworkDue !== false;
      out.classRemind = obj.classRemind !== false;
      out.noticeNew = obj.noticeNew !== false;
      out.noticeDeadline = obj.noticeDeadline !== false;
      out.noticeSignup = obj.noticeSignup !== false;
      out.voteNew = obj.voteNew !== false;
      out.voteResult = obj.voteResult !== false;
      out.waterDeduct = obj.waterDeduct !== false;
      out.leadMinutes = NotifySettings.normalizeLead(
        typeof obj.leadMinutes === 'number' ? obj.leadMinutes : 60);
      out.breakLeadMinutes = NotifySettings.normalizeBreakLead(obj.breakLeadMinutes);
      out.classLeadMinutes = NotifySettings.normalizeClassLead(
        typeof obj.classLeadMinutes === 'number' ? obj.classLeadMinutes : 10);
      return out;
    } catch (e) {
      return out;
    }
  }
}
