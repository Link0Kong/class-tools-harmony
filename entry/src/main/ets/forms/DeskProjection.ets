import { HideData } from '../data/home/HidePrefs';
import { HomeworkDueCalculator, HomeworkRow } from '../data/homework/HomeworkModels';
import { HomeworkResult } from '../data/homework/HomeworkRepository';
import { PersonalTask, taskDay } from '../data/tasks/TaskModels';
import { NoticeCard, NoticeCards } from '../features/notices/NoticeCards';
import { NoticesResult } from '../data/notices/NoticesRepository';
import { HomeDigest } from '../features/home/HomeDigest';
import { TtResult } from '../data/timetable/TimetableRepository';
import { MarksRefreshResult } from '../data/marks/MarksRepository';
import { DeskFeed, DeskLine } from './DeskContent';

function assignmentLine(hw: HomeworkRow): DeskLine {
  const line = new DeskLine();
  const title = hw.content.trim().split('\n')[0].trim() || hw.subject || '未命名作业';
  line.title = '作业 · ' + title.slice(0, 100);
  line.detail = hw.subject !== title ? hw.subject.slice(0, 40) : '';
  line.dueAt = HomeworkDueCalculator.parseDue(hw.date, hw.time) || 0;
  if (!line.dueAt && hw.due) line.detail = [hw.due, line.detail].filter((s: string) => s.length > 0).join(' · ');
  line.priority = line.dueAt ? 4 : 5;
  line.toolId = 'hw';
  line.homeworkId = hw.id;
  return line;
}

function personalLine(task: PersonalTask): DeskLine {
  const line = new DeskLine();
  line.title = task.title.slice(0, 100);
  line.toolId = 'hw';
  line.taskId = task.id;
  line.dueAt = HomeworkDueCalculator.parseDue(task.due, task.dueTime || '23:59') || 0;
  line.priority = task.priority(taskDay(new Date()));
  line.detail = task.starred ? '重要' : task.group.slice(0, 40);
  return line;
}

function noticeLine(card: NoticeCard): DeskLine {
  const line = new DeskLine();
  line.title = card.title.slice(0, 100);
  line.detail = (card.label || card.dueText || card.timeText || card.source).slice(0, 75);
  line.toolId = 'nt';
  line.noticeId = card.key;
  return line;
}

export function applyDeskData(feed: DeskFeed, hidden: HideData, tt: TtResult, hw: HomeworkResult,
  nt: NoticesResult, marks: MarksRefreshResult, tasks: PersonalTask[] | undefined): void {
  const now = Date.now();
  if (tt.ok && tt.snapshot) {
    feed.term = tt.snapshot.termStart();
    feed.courses = tt.snapshot.c;
  }
  if (tasks !== undefined) {
    feed.imported = tasks.map((t: PersonalTask) => t.sourceHwId).filter((id: string) => id.length > 0);
    feed.tasks = tasks.filter((t: PersonalTask) => !t.done).map(personalLine);
    feed.taskAt = now;
  }
  if (hw.ok && (marks.ok || !feed.homeworkAt)) {
    feed.assignments = hw.rows.filter((r: HomeworkRow) => !r.archived && !hidden.hwHide.has(r.id) &&
      !marks.snapshot.hwDone.has(r.id)).map(assignmentLine);
    if (!hw.message) feed.homeworkAt = now;
  }
  if (nt.ok) {
    const cards = NoticeCards.build(nt.entries, now).filter((c: NoticeCard) => {
      const id = c.entry ? c.entry.row.id : '';
      return !hidden.ntHide.has(id) && !hidden.ntHide.has(c.key.split('@occ:')[0]);
    });
    const pending = HomeDigest.ntOpen(cards, (key: string) => marks.snapshot.ntDone.has(key));
    feed.pendingCount = pending.length;
    feed.pendingNotices = pending.slice(0, 5).map(noticeLine);
    feed.noticeCount = cards.length;
    feed.notices = cards.sort((a: NoticeCard, b: NoticeCard) => b.pubTs - a.pubTs).slice(0, 5).map(noticeLine);
    if (!nt.message) feed.noticeAt = now;
  }
}
