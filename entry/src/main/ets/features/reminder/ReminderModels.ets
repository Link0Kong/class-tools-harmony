import { HomeworkDueCalculator, HomeworkRow } from '../../data/homework/HomeworkModels';

/** 提醒偏好（本机 + 可随账号同步；当前本机保存）。 */
export class ReminderPrefs {
  enabled: boolean = true;
  /** 提前分钟数。 */
  advanceMinutes: number = 30;
}

export class ReminderPlan {
  expiresAt: number = 0;
  launchParameters?: Record<string, Object>;
  notificationId: number = 0;
  homeworkId: string = '';
  taskId: string = '';
  noticeId: string = '';
  toolId: string = 'hw';
  title: string = '';
  content: string = '';
  triggerAt: number = 0;
  dueAt: number = 0;

  calendarLeadMinutes(): number {
    const lead: number = (this.dueAt - this.triggerAt) / 60000;
    return Number.isInteger(lead) && lead >= 0 && lead <= 40320 ? lead : 0;
  }

  calendarStart(): number {
    return this.calendarLeadMinutes() > 0 ? this.dueAt : this.triggerAt;
  }
}

/** 作业截止提醒规划（纯函数）。 */
export class ReminderPlanner {
  static readonly ADVANCE_OPTIONS: number[] = [10, 30, 60, 120];

  static normalizeAdvance(value: number): number {
    for (let i = 0; i < ReminderPlanner.ADVANCE_OPTIONS.length; i++) {
      if (ReminderPlanner.ADVANCE_OPTIONS[i] === value) {
        return value;
      }
    }
    return 30;
  }

  /** 生成提醒计划：截止时间需在未来，触发时间 = 截止 - 提前分钟（若已过则 1 分钟后）。 */
  static plan(row: HomeworkRow, nowMillis: number, advanceMinutes: number): ReminderPlan | undefined {
    const dueAt: number | undefined = HomeworkDueCalculator.parseDue(row.date, row.time);
    if (dueAt === undefined || dueAt <= nowMillis) {
      return undefined;
    }
    const advance: number = ReminderPlanner.normalizeAdvance(advanceMinutes);
    const triggerAt: number = Math.min(dueAt, Math.max(nowMillis + 60 * 1000, dueAt - advance * 60 * 1000));
    const plan: ReminderPlan = new ReminderPlan();
    plan.homeworkId = row.id;
    plan.title = ReminderPlanner.titleOf(row);
    const firstLine: string = row.content.trim().split('\n')[0].slice(0, 90);
    const actualMinutes: number = Math.round((dueAt - triggerAt) / 60000);
    const leadText: string = actualMinutes === 0 ? '截止时' :
      (actualMinutes % 60 === 0 ? '提前 ' + (actualMinutes / 60) + ' 小时' : '提前 ' + actualMinutes + ' 分钟');
    plan.content = (firstLine.length > 0 ? firstLine + ' · ' : '') + '截止 ' + HomeworkDueCalculator.dueText(dueAt)
      + '（' + leadText + '）';
    plan.triggerAt = triggerAt;
    plan.dueAt = dueAt;
    return plan;
  }

  static titleOf(row: HomeworkRow): string {
    const subject: string = row.subject.trim();
    if (subject.length > 0) {
      return subject + ' 作业截止';
    }
    const firstLine: string = row.content.split('\n')[0].trim();
    return (firstLine.length > 0 ? firstLine : '作业') + ' 截止';
  }

  /** 是否临近（24h 内）/已过期，用于列表提醒标记。 */
  static urgency(dueAt: number | undefined, nowMillis: number): string {
    if (dueAt === undefined) {
      return '';
    }
    const diff: number = dueAt - nowMillis;
    if (diff < 0) {
      return '已过期';
    }
    if (diff <= 24 * 60 * 60 * 1000) {
      return '今日到期';
    }
    return '';
  }
}
