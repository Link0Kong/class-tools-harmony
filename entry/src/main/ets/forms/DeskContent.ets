import { TtCalendar } from '../data/timetable/TtCalendar';
import { Course, SessionInfo, SessionState, TtSnapshot } from '../data/timetable/TimetableModels';
import { HomeworkDueCalculator } from '../data/homework/HomeworkModels';

// Only the fields displayed on a form are shared with its extension.
export class DeskLine {
  title: string = '';
  detail: string = '';
  toolId: string = '';
  homeworkId: string = '';
  taskId: string = '';
  noticeId: string = '';
  dueAt: number = 0;
  priority: number = 5;
}

export class DeskFeed {
  sid: string = '';
  revision: string = '';
  refreshedAt: number = 0;
  term: string = '';
  courses: Course[] = [];
  tasks: DeskLine[] = [];
  assignments: DeskLine[] = [];
  imported: string[] = [];
  notices: DeskLine[] = [];
  pendingNotices: DeskLine[] = [];
  noticeCount: number = 0;
  pendingCount: number = 0;
  noticeAt: number = 0;
  homeworkAt: number = 0;
  taskAt: number = 0;
}

function heading(kind: string): string {
  if (kind === 'tt') return '班级课表';
  if (kind === 'hw') return '待办任务';
  if (kind === 'nt') return '班级通知';
  return '工作台';
}

export class DeskView {
  heading: string = '';
  summary: string = '';
  empty: string = '';
  rows: DeskLine[] = [];
  toolId: string = '';
  dim: number = 2;
  palette: number = 0;
}

function courseRow(course: SessionInfo): DeskLine {
  const row = new DeskLine();
  row.title = course.name;
  row.toolId = 'tt';
  const room = course.fullRoom || course.room;
  row.detail = course.startText + '–' + course.endText +
    (room ? ' · ' + room : '') + (course.span ? ' · ' + course.span : '');
  return row;
}

function dated(row: DeskLine, now: number): DeskLine {
  const copy = new DeskLine();
  copy.title = row.title;
  copy.detail = row.detail;
  copy.toolId = row.toolId;
  copy.homeworkId = row.homeworkId;
  copy.taskId = row.taskId;
  copy.dueAt = row.dueAt;
  copy.priority = row.priority;
  if (row.dueAt > 0) {
    const delta = row.dueAt - now;
    copy.priority = delta < 0 ? 0 : delta < 86400000 ? 1 : row.priority;
    const deadline = HomeworkDueCalculator.dueText(row.dueAt) + ' 截止';
    copy.detail = (delta < 0 ? '已逾期 · ' : '') + deadline + (row.detail ? ' · ' + row.detail : '');
  }
  return copy;
}

function byUrgency(a: DeskLine, b: DeskLine): number {
  return a.priority - b.priority || (a.dueAt || Number.MAX_SAFE_INTEGER) - (b.dueAt || Number.MAX_SAFE_INTEGER);
}

export function deskContent(kind: string, feed: DeskFeed, dim: number, palette: number, now: number): DeskView {
  const result = new DeskView();
  result.toolId = kind;
  result.dim = dim;
  result.palette = palette;
  result.heading = heading(kind);
  if (!feed.sid) {
    result.empty = '登录后查看';
    result.summary = '点按打开枫丹工具箱';
    return result;
  }
  if (kind === 'nt') {
    result.rows = feed.notices;
    result.summary = feed.noticeAt ? feed.noticeCount + ' 条通知 · ' + feed.pendingCount + ' 待处理' : '等待同步';
    result.empty = feed.noticeAt ? '暂无班级通知' : '打开通知同步';
  } else {
    const snap = new TtSnapshot();
    snap.c = feed.courses;
    snap.t = feed.term;
    const plan = TtCalendar.plan(snap, now);
    const ongoing = plan.today.find((s: SessionInfo) => s.state === SessionState.ONGOING);
    const current = ongoing || plan.next;
    if (kind === 'tt') {
      result.empty = plan.hasData ? '近期暂无课程' : '打开课表同步课程';
      result.summary = plan.hasData ? (plan.week ? '第 ' + plan.week + ' 周 · ' : '') + '今日 ' + plan.today.length + ' 门' : '';
      if (current) {
        result.heading = ongoing ? '正在上课' : current.dayText + ' · 下一节';
        result.rows.push(courseRow(current));
        const upcoming = plan.today.filter((s: SessionInfo) => s.startAt > current.startAt);
        const next = plan.next;
        if (ongoing && next && !upcoming.some((s: SessionInfo) => s.startAt === next.startAt && s.name === next.name)) {
          upcoming.push(next);
          upcoming.sort((a: SessionInfo, b: SessionInfo) => a.startAt - b.startAt);
        }
        upcoming.forEach((s: SessionInfo) => {
          const line = courseRow(s);
          if (s.dayOffset > 0) line.detail = s.dayText + ' ' + line.detail;
          result.rows.push(line);
        });
      }
    } else {
      const imported = new Set<string>(feed.imported);
      const hw = feed.assignments.filter((row: DeskLine) => !imported.has(row.homeworkId) &&
        (!row.dueAt || now <= row.dueAt + 3 * 86400000));
      const items = hw.concat(feed.tasks).map((row: DeskLine) => dated(row, now));
      const overview = [feed.taskAt ? feed.tasks.length + ' 待办' : '待办待同步',
        feed.homeworkAt ? hw.length + ' 作业' : '作业待同步'];
      if (kind === 'home') {
        overview.push(feed.noticeAt ? feed.pendingCount + ' 通知待处理' : '通知待同步');
        items.push(...feed.pendingNotices);
        if (current) {
          const course = courseRow(current);
          course.title = (ongoing ? '上课中 · ' : '下一节 · ') + course.title;
          course.priority = ongoing || current.startAt - now < 900000 ? 2 : 6;
          items.push(course);
        }
      }
      result.rows = items.sort(byUrgency);
      result.summary = overview.join(' · ');
      result.empty = feed.taskAt && feed.homeworkAt ? '暂无待办' : '点按查看并同步';
    }
  }
  result.rows = result.rows.slice(0, dim === 4 ? 5 : dim === 3 ? 2 : 1);
  const last = kind === 'nt' ? feed.noticeAt : kind === 'hw' ? feed.homeworkAt : 0;
  if (last > 0 && now - last >= 3600000) result.summary += ' · 上次同步';
  return result;
}
