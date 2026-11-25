import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import { field, numberField, taskDay, taskObjects } from './TaskModels';

export function emptyTasks(): Blob { return { 'v': 1, 'items': [], 'lists': [] }; }

/** Keep legacy wrappers and their unknown metadata when updating an existing row. */
export class TaskWire {
  snapshot: Blob = emptyTasks();
  private root: Blob = emptyTasks();
  private path: string[] = [];
  private asText: boolean = true;

  static read(value: JsonValue | undefined): TaskWire | undefined {
    const wire = new TaskWire();
    if (value === undefined || value === null || (typeof value === 'string' && !value.trim())) return wire;
    wire.asText = typeof value === 'string';
    const root = typeof value === 'string' ? JsonBlob.parse(value) : JsonBlob.asBlob(value);
    if (!root) return undefined;
    wire.root = root;
    let leaf = root;
    for (let depth = 0; depth < 4; depth++) {
      if (Array.isArray(leaf['items'])) { wire.snapshot = leaf; return wire; }
      const key = ['task', 'data', 'v'].find((k: string) => !!JsonBlob.asBlob(leaf[k]));
      if (!key) return undefined;
      wire.path.push(key);
      leaf = JsonBlob.asBlob(leaf[key]) as Blob;
    }
    return undefined;
  }

  write(snapshot: Blob): JsonValue {
    let result = snapshot;
    if (this.path.length) {
      result = JsonBlob.clone(this.root) as Blob;
      let parent = result;
      for (let i = 0; i < this.path.length - 1; i++) parent = JsonBlob.asBlob(parent[this.path[i]]) as Blob;
      parent[this.path[this.path.length - 1]] = snapshot;
    }
    return this.asText ? JSON.stringify(result) : result;
  }
}

function byId(doc: Blob): Map<string, Blob> {
  const map = new Map<string, Blob>();
  for (const row of taskObjects(doc, 'items')) map.set(field(row, 'id'), row);
  return map;
}

// Native edits only own changed item fields. Other clients own their own groups, prefs and future fields.
export function mergeTaskEdits(base: Blob, local: Blob, remote: Blob): Blob {
  const before = byId(base);
  const after = byId(local);
  const merged = byId(remote);
  before.forEach((_item: Blob, id: string) => { if (!after.has(id)) merged.delete(id); });
  after.forEach((item: Blob, id: string) => {
    const old = before.get(id);
    if (JsonBlob.deepEqual(old, item)) return;
    const found = merged.get(id);
    if (old && !found) return; // Respect another device deleting a task while it was edited offline.
    const parent = field(item, 'fromId');
    if (!old && !found && parent && Array.from(merged.values()).some((r: Blob) =>
      field(r, 'fromId') === parent && field(r, 'due') === field(item, 'due'))) return;
    if (!old && !found && !parent) {
      const duplicate = Array.from(merged.values()).some((r: Blob) =>
        (!!field(item, 'sourceHwId') && field(r, 'sourceHwId') === field(item, 'sourceHwId')) ||
        (!!field(item, 'sourceNoticeId') && field(r, 'sourceNoticeId') === field(item, 'sourceNoticeId')));
      if (duplicate) return;
    }
    const next: Blob = found ? JsonBlob.clone(found) as Blob : {};
    for (const key of Object.keys(item)) {
      if (!old || !JsonBlob.deepEqual(old[key], item[key])) next[key] = item[key];
    }
    merged.set(id, next);
  });
  const result = JsonBlob.clone(remote) as Blob;
  result['items'] = Array.from(merged.values());
  return result;
}

export function firstOrder(items: Blob[]): number {
  return items.reduce((low: number, item: Blob) => Math.min(low, numberField(item, 'order')), 0) - 1;
}

// Preserve repeat-series semantics even when completion happens from the desktop or offline.
export function completeTask(items: Blob[], id: string, done: boolean, now: number, childId: string): boolean {
  const row = items.find((i: Blob) => field(i, 'id') === id);
  if (!row || (row['done'] === true) === done) return false;
  const children = items.filter((i: Blob) => field(i, 'fromId') === id && i['done'] !== true);
  row['done'] = done;
  row['doneAt'] = done ? now : 0;
  row['snoozeUntil'] = 0;
  row['lastNotifyAt'] = done ? now : 0;
  row['updatedAt'] = now;
  if (!done) {
    for (const child of children) {
      if (child['updatedAt'] === child['createdAt']) items.splice(items.indexOf(child), 1);
    }
    return true;
  }
  const repeat = field(row, 'repeat');
  if (children.length || !['daily', 'weekday', 'weekly', 'monthly', 'yearly'].includes(repeat)) return true;
  const today = new Date(now);
  const base = new Date((field(row, 'due') || taskDay(today)) + 'T' + (field(row, 'dueTime') || '23:59') + ':00');
  if (!Number.isFinite(base.getTime())) return true;
  const next = new Date(base.getTime());
  if (['daily', 'weekly', 'weekday'].includes(repeat)) {
    next.setDate(next.getDate() + Math.max(0, Math.floor((now - base.getTime()) / (7 * 86400000)) - 1) * 7);
  }
  do {
    if (repeat === 'monthly' || repeat === 'yearly') {
      const day = next.getDate();
      next.setDate(1);
      next.setMonth(next.getMonth() + (repeat === 'yearly' ? 12 : 1));
      const last = new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate();
      next.setDate(Math.min(day, last));
    } else {
      next.setDate(next.getDate() + (repeat === 'weekly' ? 7 : 1));
      if (repeat === 'weekday') {
        while (next.getDay() === 0 || next.getDay() === 6) next.setDate(next.getDate() + 1);
      }
    }
  } while (next.getTime() <= now);
  const child = JsonBlob.clone(row) as Blob;
  child['id'] = childId;
  child['fromId'] = id;
  child['done'] = false;
  child['doneAt'] = 0;
  child['createdAt'] = now;
  child['updatedAt'] = now;
  child['order'] = firstOrder(items);
  child['myDay'] = '';
  child['lastNotifyAt'] = 0;
  child['due'] = taskDay(next);
  const steps = taskObjects(child, 'steps');
  for (const step of steps) step['done'] = false;
  child['steps'] = steps;
  const mode = field(child, 'remindMode');
  if (mode === 'custom' && numberField(row, 'remindAt') > 0) {
    child['remindCustom'] = numberField(row, 'remindAt') + next.getTime() - base.getTime();
    child['remindAt'] = child['remindCustom'];
  } else if (mode === 'due' || /^\d+$/.test(mode)) {
    child['remindAt'] = next.getTime() - (mode === 'due' ? 0 : Number(mode)) * 60000;
  }
  items.push(child);
  return true;
}
