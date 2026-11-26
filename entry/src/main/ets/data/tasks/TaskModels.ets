import { Blob, JsonBlob } from '../sync/JsonBlob';
import { HomeworkAttachmentMeta, HomeworkAttachments, HomeworkDueCalculator, HomeworkItem, HomeworkRow } from '../homework/HomeworkModels';

export function taskObjects(doc: Blob, key: string): Blob[] {
  const rows = JsonBlob.asArray(doc[key]) || [];
  const out: Blob[] = [];
  for (const row of rows) {
    const obj = JsonBlob.asBlob(row);
    if (obj) out.push(obj);
  }
  return out;
}

export function field(doc: Blob, key: string): string { return JsonBlob.asString(doc[key], ''); }
export function numberField(doc: Blob, key: string): number { return JsonBlob.asNumber(doc[key], 0); }
export function taskDay(date: Date): string {
  return date.getFullYear() + '-' + ('0' + (date.getMonth() + 1)).slice(-2) + '-' + ('0' + date.getDate()).slice(-2);
}

const REPEAT_LABELS: Record<string, string> = { 'daily': '每天', 'weekday': '工作日', 'weekly': '每周', 'monthly': '每月', 'yearly': '每年' };

export class TaskDraftStep {
  text: string;
  note: string;
  readonly key: number;

  constructor(text: string = '', note: string = '', key: number = 0) {
    this.text = text;
    this.note = note;
    this.key = key;
  }
}

export class TaskCreateDraft {
  title: string = '';
  notes: string = '';
  due: string = '';
  dueTime: string = '';
  starred: boolean = false;
  steps: TaskDraftStep[] = [];

  stepRows(): Blob[] {
    return this.steps.filter((step: TaskDraftStep) => !!step.text.trim()).slice(0, 50)
      .map((step: TaskDraftStep): Blob => {
        const row: Blob = { 'text': step.text.trim().slice(0, 120), 'done': false };
        if (step.note.trim()) row['note'] = step.note.trim().slice(0, 500);
        return row;
      });
  }
}

export class PersonalTask {
  id: string = '';
  title: string = '';
  notes: string = '';
  due: string = '';
  dueTime: string = '';
  done: boolean = false;
  sourceHwId: string = '';
  sourceNoticeId: string = '';
  starred: boolean = false;
  order: number = 0;
  myDay: string = '';
  remindAt: number = 0;
  lastNotifyAt: number = 0;
  snoozeUntil: number = 0;
  group: string = '';
  groupId: string = '';
  sourceTitle: string = '';
  tags: string[] = [];
  doneAt: number = 0;
  steps: string[] = [];
  stepNotes: string[] = [];
  stepsDone: boolean[] = [];
  attachments: HomeworkAttachmentMeta[] = [];
  repeatLabel: string = '';

  static attachmentJson(row: Blob): string {
    const value = row['attachments'];
    return typeof value === 'string' ? value : Array.isArray(value) ? JSON.stringify(value) : '';
  }

  deadlineText(): string {
    return this.due ? this.due + (this.dueTime ? ' ' + this.dueTime : '（全天）') : '未设置';
  }

  statusLabel(now: number): string {
    if (this.done) return '已完成';
    const due = HomeworkDueCalculator.parseDue(this.due, this.dueTime || '23:59');
    return due && now > due + (this.dueTime ? 0 : 59999) ? '已逾期' : '待完成';
  }

  static validDue(due: string, time: string): boolean {
    if (!due) return !time;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(due) || (time && !/^([01]\d|2[0-3]):[0-5]\d$/.test(time))) return false;
    const date = new Date(due + 'T12:00:00');
    return Number.isFinite(date.getTime()) && taskDay(date) === due;
  }

  static list(doc: Blob): PersonalTask[] {
    const groups = new Map<string, string>();
    taskObjects(doc, 'lists').forEach((g: Blob) => { groups.set(field(g, 'id'), field(g, 'name')); });
    return taskObjects(doc, 'items').map((row: Blob) => {
      const item = new PersonalTask();
      item.id = field(row, 'id');
      item.title = field(row, 'title');
      item.notes = field(row, 'notes');
      item.due = field(row, 'due');
      item.dueTime = field(row, 'dueTime');
      item.done = row['done'] === true;
      item.sourceHwId = field(row, 'sourceHwId');
      item.sourceNoticeId = field(row, 'sourceNoticeId');
      item.starred = row['starred'] === true;
      item.order = numberField(row, 'order');
      item.myDay = field(row, 'myDay');
      item.remindAt = numberField(row, 'remindAt');
      item.lastNotifyAt = numberField(row, 'lastNotifyAt');
      item.snoozeUntil = numberField(row, 'snoozeUntil');
      item.groupId = field(row, 'list');
      item.group = groups.get(item.groupId) || '';
      item.doneAt = numberField(row, 'doneAt');
      item.attachments = HomeworkAttachments.parse(PersonalTask.attachmentJson(row));
      item.repeatLabel = REPEAT_LABELS[field(row, 'repeat')] || '';
      item.sourceTitle = field(row, 'sourceTitle');
      item.tags = (JsonBlob.asArray(row['tags']) || []).map((tag: Object) => JsonBlob.asString(tag, ''));
      const steps = taskObjects(row, 'steps');
      item.steps = steps.map((s: Blob) => field(s, 'text'));
      item.stepNotes = steps.map((s: Blob) => field(s, 'note'));
      item.stepsDone = steps.map((s: Blob) => s['done'] === true);
      return item;
    }).filter((t: PersonalTask) => t.id.length > 0 && t.title.length > 0);
  }

  priority(today: string): number {
    if (this.due && this.due < today) return 0;
    if (this.due === today) return 1;
    if (this.starred) return 2;
    if (this.myDay === today) return 3;
    return this.due ? 4 : 5;
  }

  dueLabel(): string {
    const today = taskDay(new Date());
    if (!this.due) return '';
    const day = this.due === today ? '今天' : (this.due < today ? '已逾期 ' : '') + this.due.slice(5);
    return day + (this.dueTime ? ' ' + this.dueTime : '') + ' 截止';
  }
}

export class TaskView {
  key: string;
  label: string;

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }

  static categories(doc: Blob): TaskView[] {
    const smart = [new TaskView('myday', '我的一天'), new TaskView('important', '重要'), new TaskView('planned', '计划中'),
      new TaskView('all', '待办'), new TaskView('done', '已完成')];
    const prefs = JsonBlob.asBlob(doc['prefs']);
    const order = (JsonBlob.asArray(prefs?.['sidebarOrder']) || []).map((v: Object) => JsonBlob.asString(v, ''));
    const keys = new Set<string>(order.concat(smart.map((v: TaskView) => v.key)));
    const views: TaskView[] = [];
    keys.forEach((key: string) => {
      const found = smart.find((v: TaskView) => v.key === key);
      if (found) views.push(found);
    });
    const groups = taskObjects(doc, 'lists').sort((a: Blob, b: Blob) => numberField(a, 'order') - numberField(b, 'order'));
    const seenGroups = new Set<string>();
    for (const group of groups) {
      const id = field(group, 'id');
      const key = 'group-' + id;
      if (id && id !== 'inbox' && !seenGroups.has(key)) {
        views.push(new TaskView(key, field(group, 'name') || '未命名分组'));
        seenGroups.add(key);
      }
    }
    return views;
  }

  static index(views: TaskView[], selected: string): number {
    const current = views.findIndex((v: TaskView) => v.key === selected);
    return current >= 0 ? current : Math.max(0, views.findIndex((v: TaskView) => v.key === 'all'));
  }

  static filter(items: PersonalTask[], view: string, today: string, query: string): PersonalTask[] {
    const word = query.trim().toLowerCase();
    const visible = items.filter((t: PersonalTask) => {
      if (t.done !== (view === 'done')) return false;
      if (view === 'important' && !t.starred || view === 'myday' && t.myDay !== today ||
        view === 'planned' && !t.due || view.startsWith('group-') && t.groupId !== view.slice(6)) return false;
      return !word || [t.title, t.notes, t.sourceTitle, t.tags.join(' ')].some((v: string) => v.toLowerCase().includes(word));
    });
    return visible.sort((a: PersonalTask, b: PersonalTask) => {
      if (view === 'done') return b.doneAt - a.doneAt;
      const priority = view === 'all' ? a.priority(today) - b.priority(today) : 0;
      if (priority) return priority;
      if (view === 'all' || view === 'planned') {
        const dateA = (a.due || '9999-99-99') + (a.dueTime || '23:59:59');
        const dateB = (b.due || '9999-99-99') + (b.dueTime || '23:59:59');
        if (dateA !== dateB) return dateA < dateB ? -1 : 1;
      }
      return a.order - b.order;
    });
  }
}

export class HomeworkBrief {
  pending: HomeworkItem[] = [];
  highlights: HomeworkItem[] = [];
  overdue: number = 0;
  soon: number = 0;

  static build(rows: HomeworkRow[], doneOrHidden: Set<string>, tasks: PersonalTask[], now: number): HomeworkBrief {
    const result = new HomeworkBrief();
    const linked = new Set<string>(tasks.map((task: PersonalTask) => task.sourceHwId));
    for (const row of rows) {
      if (row.archived || linked.has(row.id) || doneOrHidden.has(row.id)) continue;
      const due = HomeworkDueCalculator.evaluate(row, now);
      if (due?.prunable) continue;
      const item = new HomeworkItem();
      item.row = row;
      item.due = due;
      result.pending.push(item);
      if (due?.expired) result.overdue++;
      else if (due && due.atMillis - now <= 86400000) result.soon++;
    }
    result.pending.sort((a: HomeworkItem, b: HomeworkItem) =>
      (a.due?.atMillis ?? Number.MAX_SAFE_INTEGER) - (b.due?.atMillis ?? Number.MAX_SAFE_INTEGER));
    const upcoming = result.pending.find((item: HomeworkItem) => item.due !== undefined && !item.due.expired);
    result.highlights = result.overdue && upcoming ? [result.pending[0], upcoming] : result.pending.slice(0, 2);
    return result;
  }
}

export class TaskShare {
  static readonly PREFIX: string = 'https://tool.furina.fun/#task-share=';
  title: string = '';
  group: string = '';
  due: string = '';
  notes: string = '';
  steps: string[] = [];

  private static clip(text: string, length: number): string {
    return text.trim().slice(0, length).replace(/[\uD800-\uDBFF]$/, '');
  }

  static link(task: PersonalTask): string {
    const payload: Blob = { 't': TaskShare.clip(task.title, 60), 'd': TaskShare.clip(task.dueLabel(), 32),
      'l': TaskShare.clip(task.group || '未分组', 12), 'n': '',
      's': task.steps.slice(0, 3).map((s: string) => TaskShare.clip(s, 40)) };
    return TaskShare.PREFIX + encodeURIComponent(JSON.stringify(payload));
  }

  static parse(input: string): TaskShare | undefined {
    const url = input.trim();
    if (input.length > 8192 || !url.startsWith(TaskShare.PREFIX)) return undefined;
    try {
      const payload = JsonBlob.parse(decodeURIComponent(url.substring(TaskShare.PREFIX.length)));
      if (!payload) return undefined;
      const result = new TaskShare();
      result.title = TaskShare.clip(field(payload, 't'), 100);
      if (!result.title) return undefined;
      result.due = TaskShare.clip(field(payload, 'd'), 32);
      result.group = TaskShare.clip(field(payload, 'l'), 20);
      result.notes = TaskShare.clip(field(payload, 'n'), 500);
      result.steps = (JsonBlob.asArray(payload['s']) || []).slice(0, 6)
        .map((s: Object) => TaskShare.clip(JsonBlob.asString(s, ''), 120)).filter((s: string) => s.length > 0);
      return result;
    } catch (_) { return undefined; }
  }
}
