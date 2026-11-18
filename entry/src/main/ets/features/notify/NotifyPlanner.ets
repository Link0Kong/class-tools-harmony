import { HomeworkDueCalculator, HomeworkRow } from '../../data/homework/HomeworkModels';
import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { NoticeGroup } from '../../data/notices/NoticeModels';
import { PollResultVisibility, PollSummary } from '../../data/vote/VoteModels';
import { WaterMonthStats, WaterRoomState } from '../water/WaterModels';
import { WaterCalculator } from '../water/WaterCalculator';
import { NoticeStatus } from '../notices/NoticeStatus';
import { NoticeRecurrenceLogic } from '../notices/NoticeRecurrence';
import { SessionInfo } from '../../data/timetable/TimetableModels';
import { NotifyEvent, NotifyInput, NotifySnapshot } from './NotifyModels';
import { NotifySettings } from './NotifySettings';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const MIN_LEAD_MS: number = 60 * 1000;
const SCHEDULE_WINDOW_MS: number = 7 * DAY_MS;

/**
 * 通知事件规划（纯函数）：
 * - 新增类：与上次快照比较，首次运行只建立基线不推送；
 * - 截止/开抢/结果类：只在未来 7 天内排程，避免一次性排太多提醒；
 * - 水费：用本机水量记录计算，只有真正产生费用才提醒。
 */
export class NotifyPlanner {
  static plan(input: NotifyInput, settings: NotifySettings, snapshot: NotifySnapshot): NotifyEvent[] {
    const out: NotifyEvent[] = [];
    const firstRun: boolean = !snapshot.initialized;
    const lead: number = NotifySettings.normalizeLead(settings.leadMinutes) * 60 * 1000;
    NotifyPlanner.planHomework(input, settings, snapshot, firstRun, lead, out);
    if (settings.classRemind) {
      NotifyPlanner.planClasses(input, settings, out);
    }
    NotifyPlanner.planNotices(input, settings, snapshot, firstRun, lead, out);
    NotifyPlanner.planVotes(input, settings, snapshot, firstRun, lead, out);
    if (settings.waterDeduct) {
      NotifyPlanner.planWater(input, snapshot, firstRun, out);
    }
    return out;
  }

  private static planHomework(input: NotifyInput, settings: NotifySettings, snapshot: NotifySnapshot,
    firstRun: boolean, lead: number, out: NotifyEvent[]): void {
    for (let i = 0; i < input.homework.length; i++) {
      const row: HomeworkRow = input.homework[i];
      if (row.id.length === 0) {
        continue;
      }
      if (settings.homeworkNew && !firstRun && snapshot.hwIds.indexOf(row.id) < 0) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'hwnew:' + row.id;
        event.kind = 'homework_new';
        event.title = '新作业';
        const dueNew: number | undefined = HomeworkDueCalculator.parseDue(row.date, row.time);
        event.text = titleOfHomework(row)
          + (dueNew !== undefined ? ' · 截止 ' + HomeworkDueCalculator.dueText(dueNew) : '');
        out.push(event);
      }
      if (!settings.homeworkDue) {
        continue;
      }
      const due: number | undefined = HomeworkDueCalculator.parseDue(row.date, row.time);
      if (due === undefined || due <= input.now + MIN_LEAD_MS || due - input.now > SCHEDULE_WINDOW_MS) {
        continue;
      }
      const event: NotifyEvent = new NotifyEvent();
      event.key = 'hw:' + row.id;
      event.kind = 'homework_due';
      event.title = '作业即将截止';
      event.text = titleOfHomework(row) + ' · 截止 ' + HomeworkDueCalculator.dueText(due);
      event.fireAt = Math.max(input.now + MIN_LEAD_MS, due - lead);
      out.push(event);
    }
  }

  private static planClasses(input: NotifyInput, settings: NotifySettings, out: NotifyEvent[]): void {
    const leadMs: number = NotifySettings.normalizeClassLead(settings.classLeadMinutes) * 60 * 1000;
    for (let i = 0; i < input.classes.length; i++) {
      const cls: SessionInfo = input.classes[i];
      if (cls.startAt <= input.now + MIN_LEAD_MS) {
        continue;
      }
      if (cls.startAt - input.now > SCHEDULE_WINDOW_MS) {
        continue;
      }
      const fireAt: number = Math.max(input.now + MIN_LEAD_MS, cls.startAt - leadMs);
      const minutes: number = Math.max(1, Math.round((cls.startAt - fireAt) / (60 * 1000)));
      const event: NotifyEvent = new NotifyEvent();
      event.key = 'cls:' + cls.startAt + ':' + cls.name;
      event.kind = 'class_remind';
      event.title = '上课提醒 · ' + cls.name;
      const timeText: string = cls.endText.length > 0
        ? cls.startText + '–' + cls.endText : cls.startText;
      event.text = timeText
        + (cls.room.length > 0 ? ' · ' + cls.room : '')
        + ' · 还有 ' + minutes + ' 分钟';
      event.fireAt = fireAt;
      out.push(event);
    }
  }

  private static planNotices(input: NotifyInput, settings: NotifySettings, snapshot: NotifySnapshot,
    firstRun: boolean, lead: number, out: NotifyEvent[]): void {
    for (let i = 0; i < input.notices.length; i++) {
      const entry: NoticeEntry = input.notices[i];
      const id: string = entry.id();
      if (id.length === 0) {
        continue;
      }
      if (settings.noticeNew && !firstRun && snapshot.ntIds.indexOf(id) < 0) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'ntnew:' + id;
        event.kind = 'notice_new';
        event.title = '新通知';
        const groupNew: NoticeGroup | undefined = entry.group;
        const who: string = groupNew !== undefined && groupNew.senderName.trim().length > 0
          ? groupNew.senderName.trim() : '';
        event.text = (who.length > 0 ? who + ' · ' : '') + entry.title();
        out.push(event);
      }
      const group: NoticeGroup | undefined = entry.group;
      if (group === undefined || NoticeRecurrenceLogic.isLongterm(group)) {
        continue;
      }
      const when: number = NoticeStatus.whenAt(group);
      if (settings.noticeDeadline && when > input.now + MIN_LEAD_MS
        && when - input.now <= SCHEDULE_WINDOW_MS) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'ntd:' + id;
        event.kind = 'notice_deadline';
        event.title = '活动即将截止';
        event.text = entry.title() + ' · 截止 ' + NoticeStatus.shortTime(when);
        event.fireAt = Math.max(input.now + MIN_LEAD_MS, when - lead);
        out.push(event);
      }
      if (settings.noticeSignup) {
        const start: number = NoticeRecurrenceLogic.parseTs(group.signupStart);
        if (start > input.now + MIN_LEAD_MS && start - input.now <= SCHEDULE_WINDOW_MS) {
          const event: NotifyEvent = new NotifyEvent();
          event.key = 'nts:' + id;
          event.kind = 'notice_signup';
          event.title = '活动开抢提醒';
          event.text = entry.title() + ' · ' + NoticeStatus.shortTime(start) + ' 开始报名';
          event.fireAt = Math.max(input.now + MIN_LEAD_MS, start - 5 * 60 * 1000);
          out.push(event);
        }
      }
    }
  }

  private static planVotes(input: NotifyInput, settings: NotifySettings, snapshot: NotifySnapshot,
    firstRun: boolean, lead: number, out: NotifyEvent[]): void {
    for (let i = 0; i < input.polls.length; i++) {
      const poll: PollSummary = input.polls[i];
      if (poll.id.length === 0) {
        continue;
      }
      if (settings.voteNew && !firstRun && snapshot.pollIds.indexOf(poll.id) < 0) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'vnew:' + poll.id;
        event.kind = 'vote_new';
        event.title = '新投票';
        event.text = poll.title;
        out.push(event);
      }
      if (!settings.voteResult) {
        continue;
      }
      if (poll.closed && !firstRun && snapshot.closedPollIds.indexOf(poll.id) < 0) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'vclosed:' + poll.id;
        event.kind = 'vote_result';
        event.title = '投票结果可查看';
        event.text = poll.title;
        out.push(event);
        continue;
      }
      if (!poll.closed && poll.deadline > input.now + MIN_LEAD_MS
        && poll.deadline - input.now <= SCHEDULE_WINDOW_MS
        && poll.settings.resultVisibility === PollResultVisibility.AFTER_CLOSE) {
        const event: NotifyEvent = new NotifyEvent();
        event.key = 'vres:' + poll.id;
        event.kind = 'vote_result';
        event.title = '投票结果可查看';
        event.text = poll.title;
        event.fireAt = Math.max(input.now + MIN_LEAD_MS, poll.deadline + 60 * 1000);
        out.push(event);
      }
    }
  }

  private static planWater(input: NotifyInput, snapshot: NotifySnapshot,
    firstRun: boolean, out: NotifyEvent[]): void {
    if (input.waterRoom === undefined || input.waterRoomKey.length === 0) {
      return;
    }
    const latest = input.waterRoom.records.length > 0
      ? input.waterRoom.records[input.waterRoom.records.length - 1] : undefined;
    if (latest === undefined) {
      return;
    }
    const key: string = input.waterRoomKey + '|' + latest.month + '|' + latest.reading;
    if (firstRun || snapshot.waterKey === key) {
      return;
    }
    const stats: WaterMonthStats = WaterCalculator.stats(input.waterRoom, latest.month, input.now);
    if (!stats.charge.hasUsage || stats.charge.fee <= 0) {
      return;
    }
    const event: NotifyEvent = new NotifyEvent();
    event.key = 'water:' + key;
    event.kind = 'water_deduct';
    event.title = '水费扣除提醒';
    event.text = latest.month + ' · 用量 ' + stats.charge.usage.toFixed(2) + ' 吨 · 水费 ¥'
      + stats.charge.fee.toFixed(2) + '（扣电 ' + stats.charge.degree.toFixed(2) + ' 度）';
    out.push(event);
  }

  /** 更新快照（保留最近 300 条 id，避免无限增长）。 */
  static nextSnapshot(input: NotifyInput, snapshot: NotifySnapshot): NotifySnapshot {
    const next: NotifySnapshot = new NotifySnapshot();
    next.initialized = true;
    next.hwIds = mergeIds(snapshot.hwIds, idsOfHomework(input.homework));
    next.ntIds = mergeIds(snapshot.ntIds, idsOfNotices(input.notices));
    next.pollIds = mergeIds(snapshot.pollIds, idsOfPolls(input.polls));
    next.closedPollIds = mergeIds(snapshot.closedPollIds, closedIdsOfPolls(input.polls));
    if (input.waterRoom !== undefined && input.waterRoom.records.length > 0) {
      const latest = input.waterRoom.records[input.waterRoom.records.length - 1];
      next.waterKey = input.waterRoomKey + '|' + latest.month + '|' + latest.reading;
    } else {
      next.waterKey = snapshot.waterKey;
    }
    return next;
  }
}

function titleOfHomework(row: HomeworkRow): string {
  const subject: string = row.subject.trim();
  if (subject.length > 0) {
    return subject + ' 作业';
  }
  const first: string = row.content.split('\n')[0].trim();
  return first.length > 0 ? first : '作业';
}

function mergeIds(oldIds: string[], newIds: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < oldIds.length; i++) {
    if (out.indexOf(oldIds[i]) < 0) {
      out.push(oldIds[i]);
    }
  }
  for (let i = 0; i < newIds.length; i++) {
    if (out.indexOf(newIds[i]) < 0) {
      out.push(newIds[i]);
    }
  }
  return out.length > 300 ? out.slice(out.length - 300) : out;
}

function idsOfHomework(rows: HomeworkRow[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].id.length > 0) {
      out.push(rows[i].id);
    }
  }
  return out;
}

function idsOfNotices(entries: NoticeEntry[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].id().length > 0) {
      out.push(entries[i].id());
    }
  }
  return out;
}

function idsOfPolls(polls: PollSummary[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < polls.length; i++) {
    if (polls[i].id.length > 0) {
      out.push(polls[i].id);
    }
  }
  return out;
}

function closedIdsOfPolls(polls: PollSummary[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < polls.length; i++) {
    if (polls[i].closed && polls[i].id.length > 0) {
      out.push(polls[i].id);
    }
  }
  return out;
}
