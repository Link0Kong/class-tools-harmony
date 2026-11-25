import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { HomeworkRow } from '../homework/HomeworkModels';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { PersonalTask, TaskShare, TaskView, field, numberField, taskDay, taskObjects } from './TaskModels';
import { completeTask, emptyTasks, firstOrder, mergeTaskEdits, TaskWire } from './TaskMerge';

class TaskAccount {
  sid: string = '';
  file: string = '';
  base: Blob = emptyTasks();
  local: Blob = emptyTasks();
  inflight?: Promise<void>;
  changedDuringSync: boolean = false;
  status: string = '本机缓存';

  store(local: Blob, base: Blob): void {
    const envelope: Blob = { 'base': base, 'local': local };
    const temp = this.file + '.tmp';
    const handle = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try { fs.writeSync(handle.fd, JSON.stringify(envelope)); } finally { fs.closeSync(handle); }
    fs.renameSync(temp, this.file);
    this.base = base;
    this.local = local;
  }
}

export class TaskRepository {
  static onChange: () => void = () => {};
  private static owner?: TaskAccount;

  private static account(): TaskAccount | undefined {
    const sid = Services.currentSid;
    const ctx = AppGlobal.context;
    if (!sid || !ctx || !Services.currentToken) return undefined;
    if (TaskRepository.owner?.sid === sid) return TaskRepository.owner;
    const account = new TaskAccount();
    account.sid = sid;
    account.file = ctx.filesDir + '/tasks_' + encodeURIComponent(sid) + '.json';
    try {
      if (fs.accessSync(account.file)) {
        const saved = JsonBlob.parse(fs.readTextSync(account.file));
        const base = JsonBlob.asBlob(saved?.['base']);
        const local = JsonBlob.asBlob(saved?.['local']);
        if (!base || !local || !Array.isArray(base['items']) || !Array.isArray(local['items'])) return undefined;
        account.base = base;
        account.local = local;
      }
    } catch (_) { return undefined; }
    TaskRepository.owner = account;
    return account;
  }

  static categories(): TaskView[] {
    return TaskView.categories(TaskRepository.account()?.local || emptyTasks());
  }

  static status(): string {
    return TaskRepository.account()?.status || '本机任务存储不可用';
  }

  static async load(refresh: boolean = true): Promise<PersonalTask[]> {
    const account = TaskRepository.account();
    if (!account) return [];
    if (refresh) await TaskRepository.sync(account);
    return Services.currentSid === account.sid ? PersonalTask.list(account.local) : [];
  }

  private static async sync(account: TaskAccount): Promise<void> {
    if (account.inflight) return account.inflight;
    account.inflight = TaskRepository.syncOnce(account);
    try {
      await account.inflight;
    } finally {
      account.inflight = undefined;
      const retry = account.changedDuringSync;
      account.changedDuringSync = false;
      if (retry && Services.currentSid === account.sid && !JsonBlob.deepEqual(account.local, account.base)) {
        TaskRepository.sync(account);
      }
    }
  }

  private static async syncOnce(account: TaskAccount): Promise<void> {
    const owns = (): boolean => Services.currentSid === account.sid && !!Services.currentToken &&
      account === TaskRepository.owner;
    const path = 'taskdata?id=eq.' + encodeURIComponent(account.sid);
    try {
      for (let attempt = 0; attempt < 4 && owns(); attempt++) {
        account.status = '同步中';
        const response = await Services.api.get(path + '&select=blob,ts');
        if (!owns()) return;
        if (!response.ok) { account.status = '离线 · 本机缓存'; return; }
        const rows = JSON.parse(response.value) as Blob[];
        if (!Array.isArray(rows)) { account.status = '云端格式异常'; return; }
        const wire = TaskWire.read(rows.length ? rows[0]['blob'] : undefined);
        if (!wire) { account.status = '云端格式异常'; return; }
        const remote = wire.snapshot;
        const sent = account.local;
        let confirmed = remote;
        if (!JsonBlob.deepEqual(sent, account.base)) {
          confirmed = mergeTaskEdits(account.base, sent, remote);
          const stamp = rows.length ? Number(rows[0]['ts']) : 0;
          if (!Number.isSafeInteger(stamp) || stamp < 0) { account.status = '云端版本异常'; return; }
          confirmed['updatedAt'] = Math.max(Date.now(), numberField(sent, 'updatedAt'), stamp + 1);
          const body: Blob = { 'id': account.sid, 'blob': wire.write(confirmed), 'ts': confirmed['updatedAt'] };
          const write = rows.length ?
            await Services.api.patch(path + '&ts=eq.' + stamp, JSON.stringify(body), 'return=representation') :
            await Services.api.post('taskdata', JSON.stringify(body), 'resolution=ignore-duplicates,return=representation');
          if (!owns()) return;
          if (!write.ok) { account.status = '待同步 · 已保存到本机'; return; }
          const saved = JSON.parse(write.value) as Object[];
          if (!Array.isArray(saved) || !saved.length) continue;
        }
        const latest = account.local;
        const next = sent === latest ? confirmed : mergeTaskEdits(sent, latest, confirmed);
        const changed = !JsonBlob.deepEqual(latest, next);
        if (changed || !JsonBlob.deepEqual(account.base, confirmed)) account.store(next, confirmed);
        if (changed) TaskRepository.onChange();
        if (JsonBlob.deepEqual(account.local, account.base)) { account.status = '已同步'; return; }
      }
      account.status = '待同步';
    } catch (_) { account.status = '同步失败 · 保留本机数据'; }
  }

  private static edit(change: (items: Blob[], now: number) => boolean): boolean {
    const account = TaskRepository.account();
    if (!account) return false;
    const next = JsonBlob.clone(account.local) as Blob;
    const items = taskObjects(next, 'items');
    const now = Math.max(Date.now(), numberField(next, 'updatedAt') + 1);
    if (!change(items, now)) return false;
    next['items'] = items;
    next['updatedAt'] = now;
    try { account.store(next, account.base); } catch (_) { return false; }
    account.status = '待同步';
    if (account.inflight) account.changedDuringSync = true;
    TaskRepository.onChange();
    TaskRepository.sync(account);
    return true;
  }

  private static draft(title: string, now: number, items: Blob[]): Blob {
    return { 'id': 't' + util.generateRandomUUID(true), 'title': title.trim().slice(0, 200),
      'createdAt': now, 'updatedAt': now, 'order': firstOrder(items) };
  }

  static async add(title: string, share?: TaskShare, due: string = '', starred: boolean = false,
    view: string = 'all'): Promise<boolean> {
    if (!title.trim() || !PersonalTask.validDue(due, '')) return false;
    return TaskRepository.edit((items: Blob[], now: number) => {
      if (items.length >= 2000) return false;
      const row = TaskRepository.draft(title, now, items);
      const today = taskDay(new Date(now));
      if (due || view === 'planned') row['due'] = due || today;
      if (starred || view === 'important') row['starred'] = true;
      if (view === 'myday') row['myDay'] = today;
      if (view.startsWith('group-') && TaskRepository.categories().some((v: TaskView) => v.key === view)) {
        row['list'] = view.slice(6);
      }
      if (share) {
        row['notes'] = share.notes;
        row['steps'] = share.steps.map((s: string): Blob => { return { 'text': s, 'done': false }; });
      }
      items.push(row);
      return true;
    });
  }

  static async importHomework(rows: HomeworkRow[]): Promise<number> {
    let count = 0;
    const saved = TaskRepository.edit((items: Blob[], now: number) => {
      const linked = new Set<string>(items.map((i: Blob) => field(i, 'sourceHwId')));
      for (const row of rows) {
        if (!row.id || linked.has(row.id) || items.length >= 2000 || row.archived) continue;
        const content = row.content.trim();
        const subject = row.subject.trim();
        const title = [subject, content.split('\n')[0]].filter((s: string) => !!s).join(' · ').replace(/\s+/g, ' ');
        const task = TaskRepository.draft(title.length > 100 ? title.slice(0, 98) + '…' : title || '班级作业', now, items);
        task['sourceHwId'] = row.id;
        task['sourceTitle'] = (subject || title).slice(0, 80);
        task['notes'] = [content, row.due ? '截止说明：' + row.due : ''].filter((s: string) => !!s).join('\n\n').slice(0, 5000);
        task['due'] = row.date;
        task['dueTime'] = row.date ? row.time : '';
        task['tags'] = subject && subject !== '班级作业' && subject.length <= 16 ? ['班级作业', subject] : ['班级作业'];
        items.push(task);
        linked.add(row.id);
        count++;
      }
      return count > 0;
    });
    return saved ? count : 0;
  }

  static async importNotice(id: string, title: string, summary: string, deadline: number = 0,
    category: string = ''): Promise<boolean> {
    return TaskRepository.edit((items: Blob[], now: number) => {
      if (!id || items.length >= 2000 || items.some((i: Blob) => field(i, 'sourceNoticeId') === id)) return false;
      const row = TaskRepository.draft(title || '班级通知', now, items);
      row['notes'] = summary.slice(0, 5000);
      row['sourceNoticeId'] = id;
      row['sourceTitle'] = title.slice(0, 80);
      row['tags'] = category && category !== '通知' ? ['通知', category.slice(0, 16)] : ['通知'];
      if (deadline > 0) {
        const date = new Date(deadline);
        row['due'] = taskDay(date);
        if (date.getHours() || date.getMinutes()) {
          row['dueTime'] = ('0' + date.getHours()).slice(-2) + ':' + ('0' + date.getMinutes()).slice(-2);
        }
      }
      items.push(row);
      return true;
    });
  }

  static async updateDetails(before: PersonalTask, title: string, notes: string, due: string, time: string,
    starred: boolean): Promise<boolean> {
    if (!title.trim() || !PersonalTask.validDue(due, time)) return false;
    return TaskRepository.edit((items: Blob[], now: number) => {
      const row = items.find((r: Blob) => field(r, 'id') === before.id);
      if (!row) return false;
      if (title !== before.title) row['title'] = title.trim().slice(0, 200);
      if (notes !== before.notes) row['notes'] = notes.slice(0, 5000);
      if (due !== before.due) row['due'] = due;
      if (time !== before.dueTime) row['dueTime'] = time;
      if (starred !== before.starred) row['starred'] = starred;
      const mode = field(row, 'remindMode');
      if ((due !== before.due || time !== before.dueTime) && (mode === 'due' || /^\d+$/.test(mode))) {
        const stamp = new Date(due + 'T' + (time || '23:59') + ':00').getTime();
        row['remindAt'] = due && Number.isFinite(stamp) ? Math.max(0, stamp - (mode === 'due' ? 0 : Number(mode)) * 60000) : 0;
        row['lastNotifyAt'] = 0;
        row['snoozeUntil'] = 0;
      }
      row['updatedAt'] = now;
      return true;
    });
  }

  static async toggle(id: string, done: boolean): Promise<boolean> {
    return TaskRepository.edit((items: Blob[], now: number) =>
      completeTask(items, id, done, now, 't' + util.generateRandomUUID(true)));
  }

  static async remind(id: string, at: number): Promise<boolean> {
    return TaskRepository.edit((items: Blob[], now: number) => {
      const row = items.find((r: Blob) => field(r, 'id') === id);
      if (!row || row['done'] === true || (at && at <= now)) return false;
      row['remindMode'] = at ? 'custom' : 'none';
      row['remindAt'] = at;
      row['remindCustom'] = at;
      row['snoozeUntil'] = 0;
      row['lastNotifyAt'] = 0;
      row['updatedAt'] = now;
      return true;
    });
  }

  static async toggleStep(id: string, index: number): Promise<boolean> {
    return TaskRepository.edit((items: Blob[], now: number) => {
      const row = items.find((r: Blob) => field(r, 'id') === id);
      if (!row) return false;
      const steps = taskObjects(row, 'steps');
      if (!steps[index]) return false;
      steps[index]['done'] = steps[index]['done'] !== true;
      row['updatedAt'] = now;
      return true;
    });
  }
}
