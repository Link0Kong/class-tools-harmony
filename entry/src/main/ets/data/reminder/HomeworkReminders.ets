import { AsyncLock } from '../../common/AsyncLock';
import { Services } from '../../app/Services';
import { HomeworkRow } from '../homework/HomeworkModels';
import { ReminderPlanner } from '../../features/reminder/ReminderModels';
import { ReminderAgent, ReminderPublishResult } from './ReminderAgent';
import { NotifyStore } from '../notify/NotifyStore';
import { ReminderRecord, ReminderStore } from './ReminderStore';

export class HomeworkReminders {
  private static readonly lock = new AsyncLock();

  static async schedule(row: HomeworkRow, advance: number): Promise<ReminderPublishResult> {
    const sid = Services.currentSid;
    return HomeworkReminders.lock.run<ReminderPublishResult>(async () => {
      const fail = new ReminderPublishResult();
      const plan = ReminderPlanner.plan(row, Date.now(), advance);
      if (!sid || !plan || sid !== Services.currentSid) { fail.message = '没有可用的未来截止时间'; return fail; }
      if (!(await NotifyStore.loadSettings(sid)).master) {
        fail.message = '请先在提醒设置中开启系统通知';
        return fail;
      }
      const record = await ReminderStore.load(sid);
      const previous = record.ids.get(row.id);
      const result = await ReminderAgent.publish(plan);
      if (!result.ok) return result;
      if (sid !== Services.currentSid || (previous !== undefined && !(await ReminderAgent.cancel(previous)))) {
        await ReminderAgent.cancel(result.reminderId);
        fail.message = '未能替换原提醒';
        return fail;
      }
      record.ids.set(row.id, result.reminderId);
      record.leads.set(row.id, advance);
      record.dueTimes.set(row.id, plan.dueAt);
      record.triggerTimes.set(row.id, plan.triggerAt);
      record.advance = advance;
      if (!(await ReminderStore.save(sid, record))) {
        await ReminderAgent.cancel(result.reminderId);
        fail.message = '无法保存提醒设置';
        return fail;
      }
      return result;
    });
  }

  static async setAdvance(sid: string, minutes: number): Promise<void> {
    await HomeworkReminders.lock.run<void>(async () => {
      const record = await ReminderStore.load(sid);
      record.advance = ReminderPlanner.normalizeAdvance(minutes);
      await ReminderStore.save(sid, record);
    });
  }

  private static forget(record: ReminderRecord, id: string): void {
    record.ids.delete(id);
    record.leads.delete(id);
    record.dueTimes.delete(id);
    record.triggerTimes.delete(id);
  }

  static async cancel(id: string): Promise<boolean> {
    const sid = Services.currentSid;
    return HomeworkReminders.lock.run<boolean>(async () => {
      const record = await ReminderStore.load(sid);
      if (!record.leads.has(id) && !record.ids.has(id)) return true;
      const previous = record.ids.get(id);
      if (previous !== undefined && !(await ReminderAgent.cancel(previous))) return false;
      HomeworkReminders.forget(record, id);
      return await ReminderStore.save(sid, record);
    });
  }

  private static async deactivate(sid: string, discard: boolean): Promise<void> {
    await HomeworkReminders.lock.run<void>(async () => {
      const record = await ReminderStore.load(sid);
      if (!record.leads.size) return;
      for (const id of Array.from(record.leads.keys())) {
        const systemId = record.ids.get(id);
        if (systemId !== undefined && !(await ReminderAgent.cancel(systemId))) continue;
        const trigger = record.triggerTimes.get(id) || 0;
        if (discard || (trigger && trigger <= Date.now())) HomeworkReminders.forget(record, id);
        else record.ids.delete(id);
      }
      await ReminderStore.save(sid, record);
    });
  }

  static suspend(sid: string): Promise<void> { return HomeworkReminders.deactivate(sid, false); }

  static clear(sid: string): Promise<void> { return HomeworkReminders.deactivate(sid, true); }

  /** rows must come from a successful homework + marks read; missing rows then represent completed/hidden/removed items. */
  static async resume(sid: string, rows: HomeworkRow[]): Promise<void> {
    await HomeworkReminders.lock.run<void>(async () => {
      if (!sid || Services.currentSid !== sid || !(await NotifyStore.loadSettings(sid)).master) return;
      const record = await ReminderStore.load(sid);
      if (!record.leads.size) return;
      let changed = false;
      for (const id of Array.from(record.leads.keys())) {
        if (Services.currentSid !== sid) break;
        const row = rows.find((r: HomeworkRow) => r.id === id);
        const plan = row ? ReminderPlanner.plan(row, Date.now(), record.leads.get(id) || record.advance) : undefined;
        const systemId = record.ids.get(id);
        if (!plan) {
          if (systemId !== undefined && !(await ReminderAgent.cancel(systemId))) continue;
          HomeworkReminders.forget(record, id);
          changed = true;
          continue;
        }
        const knownDue = record.dueTimes.get(id);
        if (systemId !== undefined && (!knownDue || knownDue === plan.dueAt)) continue;
        const result = await ReminderAgent.publish(plan, false);
        if (!result.ok) continue;
        if (Services.currentSid !== sid || (systemId !== undefined && !(await ReminderAgent.cancel(systemId)))) {
          await ReminderAgent.cancel(result.reminderId);
          continue;
        }
        record.ids.set(id, result.reminderId);
        record.dueTimes.set(id, plan.dueAt);
        record.triggerTimes.set(id, plan.triggerAt);
        changed = true;
      }
      if (changed) await ReminderStore.save(sid, record);
    });
  }
}
