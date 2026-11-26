import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppGlobal } from '../../app/AppGlobal';
import { NotifyWork } from './NotifyWork';
import { LiveActivity } from './LiveActivity';
import { NotificationDelivery } from './NotificationDelivery';
import { TaskRepository } from '../tasks/TaskRepository';
import { PersonalTask } from '../tasks/TaskModels';
import { HidePrefs } from '../home/HidePrefs';
import { HomeworkReminders } from '../reminder/HomeworkReminders';
import { ReminderStore } from '../reminder/ReminderStore';
import notificationManager from '@ohos.notificationManager';
import { Services } from '../../app/Services';
import { Log } from '../../common/Log';
import { AppPush } from '../../features/push/AppPush';
import { NotifyEvent, NotifyInput, NotifySnapshot } from '../../features/notify/NotifyModels';
import { NotifyPlanner } from '../../features/notify/NotifyPlanner';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { NotifyStore } from './NotifyStore';
import { HomeworkResult } from '../homework/HomeworkRepository';
import { HomeworkRow } from '../homework/HomeworkModels';
import { NoticesResult } from '../notices/NoticesRepository';
import { NoticeEntry } from '../notices/NoticesRepository';
import { PollSummary } from '../vote/VoteModels';
import { VoteRepository } from '../vote/VoteRepository';
import { WaterRoomState, WaterState } from '../../features/water/WaterModels';
import { WaterCodec } from '../../features/water/WaterCodec';
import { PowerPrefs } from '../power/PowerPrefs';
import { ReminderAgent, ReminderPublishResult } from '../reminder/ReminderAgent';
import { ReminderPlan } from '../../features/reminder/ReminderModels';
import { MarkKind } from '../marks/Marks';
import { TtResult } from '../timetable/TimetableRepository';
import { TtCalendar } from '../timetable/TtCalendar';
import { SessionInfo, TtSnapshot } from '../timetable/TimetableModels';

const THROTTLE_MS: number = 3 * 60 * 1000;

/** 本地通知中心：按设置扫描作业/通知/投票/水费，发送本地通知或排系统提醒。 */
export class NotifyCenter {
  private static queue: Promise<void> = Promise.resolve();
  private static generation: number = 0;
  private static lastSid: string = '';
  private static ending: boolean = false;

  private static enqueue(work: () => Promise<void>, context?: common.Context): Promise<void> {
    NotifyCenter.queue = NotifyCenter.queue.then(async () => {
      const ctx = context || AppGlobal.context;
      if (!ctx) return;
      const file = fs.openSync(ctx.filesDir + '/notify-delivery.lock', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        // UI 等当前后台批次收尾，机会性后台扫描遇到忙碌的前台则跳过本轮。
        if (context) {
          try { file.tryLock(true); } catch (_) { return; }
        } else {
          await file.lock(true);
        }
        await NotifyStore.refresh(ctx);
        await work();
      } finally {
        fs.closeSync(file);
      }
    }).catch(() => {
      Log.w('NotifyCenter', '系统提醒同步失败');
    });
    return NotifyCenter.queue;
  }

  static setForeground(value: boolean): void {
    LiveActivity.foregroundChanged(value);
  }
  private static lastRunAt: number = 0;

  /** 用户主动开启通知/设置提醒时调用（此时才请求系统权限）。 */
  static async ensurePermission(): Promise<boolean> {
    return await AppPush.ensurePermission();
  }

  static async currentSettings(): Promise<NotifySettings> {
    return await NotifyStore.loadSettings(Services.currentSid);
  }

  /** 用户主动点击「发送测试通知」时调用，先确认权限再发一条本地通知。 */
  static async sendTest(): Promise<boolean> {
    const allowed: boolean = await AppPush.ensurePermission();
    if (!allowed) {
      return false;
    }
    return await NotificationDelivery.publish(20261118, '枫丹工具箱 · 测试通知',
      '系统通知已开启，点击查看任务。', NotificationDelivery.route('hw'));
  }

  static async testScheduled(): Promise<string> {
    const plan = new ReminderPlan();
    plan.triggerAt = Date.now() + 20000;
    plan.title = '枫丹工具箱 · 定时测试';
    plan.content = '这条通知由系统定时送达。';
    const result = await ReminderAgent.publish(plan);
    return result.ok ? '系统已接受测试，请在约 20 秒后查看通知中心' : result.message;
  }

  static async saveSettings(settings: NotifySettings): Promise<void> {
    const sid: string = Services.currentSid;
    if (!sid) return;
    if (!settings.master) {
      NotifyCenter.generation++;
      await NotifyWork.configure(false);
    }
    await NotifyCenter.enqueue(async () => {
      if (sid !== Services.currentSid) return;
      await NotifyStore.saveSettings(sid, settings);
      if (settings.master) await NotifyWork.configure(true);
      if (!settings.master || !settings.liveActivities) await LiveActivity.clear();
      if (!settings.active()) {
        await NotifyCenter.reconcile(sid, [], [], '_sched');
        if (!settings.master) {
          await NotifyCenter.reconcile(sid, [], [], '_tasks');
          await HomeworkReminders.suspend(sid);
          await ReminderAgent.cancelAll();
          await notificationManager.cancelAll();
        }
      }
    });
  }

  static syncAll(force: boolean = false): Promise<void> {
    const sid: string = Services.currentSid;
    const gen: number = NotifyCenter.generation;
    if (!sid || NotifyCenter.ending) return Promise.resolve();
    return NotifyCenter.enqueue(async () => {
      if (sid !== Services.currentSid || gen !== NotifyCenter.generation) return;
      if (!force && sid === NotifyCenter.lastSid && Date.now() >= NotifyCenter.lastRunAt && Date.now() - NotifyCenter.lastRunAt < THROTTLE_MS) return;
      const settings = await NotifyStore.loadSettings(sid);
      const enabled: boolean = await AppPush.systemEnabled();
      if (!enabled) {
        await LiveActivity.clear();
        return;
      }
      if (!settings.master) return;
      if (NotifyCenter.lastSid !== sid) {
        const manual = await ReminderStore.load(sid);
        await ReminderAgent.removeLegacy(new Set<number>(Array.from(manual.ids.values())));
      }
      await NotifyCenter.planTasks(sid);
      const now: number = Date.now();
      const input = await NotifyCenter.collect(now, sid);
      if (sid !== Services.currentSid || gen !== NotifyCenter.generation) return;

      if (settings.classRemind && settings.liveActivities) {
        if (!input.unavailable.includes('cls')) {
          LiveActivity.coursePlan(sid, input.classes, NotifySettings.normalizeClassLead(settings.classLeadMinutes),
            NotifySettings.normalizeBreakLead(settings.breakLeadMinutes));
        }
      } else {
        LiveActivity.coursePlan(sid, [], 0);
      }
      await NotifyCenter.deliver(sid, input, settings,
        async () => sid === Services.currentSid && gen === NotifyCenter.generation && !NotifyCenter.ending);
      NotifyCenter.lastSid = sid;
      NotifyCenter.lastRunAt = now;
    });
  }

  static async syncBackground(context: common.Context, sid: string, input: NotifyInput,
    stillOwner: () => Promise<boolean>, tasks?: PersonalTask[]): Promise<boolean> {
    let completed = false;
    await NotifyCenter.enqueue(async () => {
      if (!sid || !await stillOwner() || !await AppPush.systemEnabled()) return;
      const settings = await NotifyStore.loadSettings(sid, context);
      if (!settings.master) return;
      let tasksOk = true;
      if (tasks !== undefined) {
        tasksOk = await NotifyCenter.reconcile(sid, NotifyPlanner.tasks(tasks, Date.now()), [], '_tasks', stillOwner, context);
      }
      completed = await NotifyCenter.deliver(sid, input, settings, stillOwner, context) && tasksOk && await stillOwner();
    }, context);
    return completed;
  }

  private static async deliver(sid: string, input: NotifyInput, settings: NotifySettings,
    stillOwner: () => Promise<boolean>, context?: common.Context): Promise<boolean> {
    if (!await stillOwner()) return false;
    const snapshot = await NotifyStore.loadSnapshot(sid, context);
    const events = NotifyPlanner.plan(input, settings, snapshot);
    const timed = events.filter((event: NotifyEvent) => event.fireAt > 0);
    let pending = events.filter((event: NotifyEvent) => event.fireAt <= 0);
    // A WorkScheduler run may be stopped between any two notifications.
    for (const event of pending.slice()) {
      if (!await stillOwner()) return false;
      if (await NotifyCenter.publishNow(event, stillOwner)) {
        pending = pending.filter((item: NotifyEvent) => item.key !== event.key);
        if (!await stillOwner()) return false;
        await NotifyStore.saveSnapshot(sid, NotifyPlanner.nextSnapshot(input, snapshot, pending), context);
      }
    }
    const preserve: string[] = [];
    if (settings.homeworkDue) preserve.push('hw');
    if (settings.noticeDeadline) preserve.push('ntd');
    if (settings.noticeSignup) preserve.push('nts');
    if (settings.voteResult) preserve.push('vres');
    if (settings.classRemind) preserve.push('cls');
    const scheduled = await NotifyCenter.reconcile(sid, timed, input.unavailable.filter((key: string) => preserve.includes(key)),
      '_sched', stillOwner, context);
    if (!await stillOwner()) return false;
    await NotifyStore.saveSnapshot(sid, NotifyPlanner.nextSnapshot(input, snapshot, pending), context);
    await NotifyStore.setLastRun(sid, Date.now(), context);
    return scheduled && pending.length === 0 && await stillOwner();
  }

  static syncTasks(): Promise<void> {
    const sid: string = Services.currentSid;
    const gen: number = NotifyCenter.generation;
    if (!sid || NotifyCenter.ending) return Promise.resolve();
    return NotifyCenter.enqueue(async () => {
      if (sid === Services.currentSid && gen === NotifyCenter.generation && await AppPush.systemEnabled()) {
        await NotifyCenter.planTasks(sid);
      }
    });
  }

  private static async planTasks(sid: string): Promise<void> {
    if (!(await NotifyStore.loadSettings(sid)).master) return;
    const tasks = await TaskRepository.load(false);
    if (TaskRepository.status() === '本机任务存储不可用') return;
    const events: NotifyEvent[] = NotifyPlanner.tasks(tasks, Date.now());
    if (sid === Services.currentSid && !NotifyCenter.ending) {
      await NotifyCenter.reconcile(sid, events, [], '_tasks', async () => sid === Services.currentSid && !NotifyCenter.ending);
    }
  }

  static async endSession(sid: string): Promise<void> {
    if (!sid) return;
    NotifyCenter.ending = true;
    NotifyCenter.generation++;
    NotifyCenter.lastSid = '';
    try {
      await LiveActivity.clear();
      await NotifyCenter.enqueue(async () => {
        await NotifyCenter.reconcile(sid, [], [], '_sched');
        await NotifyCenter.reconcile(sid, [], [], '_tasks');
        await HomeworkReminders.clear(sid);
        await ReminderAgent.cancelAll();
        await notificationManager.cancelAll();
      });
    } finally {
      NotifyCenter.ending = false;
    }
  }

  private static async reconcile(sid: string, events: NotifyEvent[], unknown: string[], bucket: string,
    stillOwner?: () => Promise<boolean>, context?: common.Context): Promise<boolean> {
    let complete = true;
    const records = await NotifyStore.loadScheduled(sid, bucket, context);
    const desired: Map<string, NotifyEvent> = new Map();
    events.sort((a: NotifyEvent, b: NotifyEvent) => a.fireAt - b.fireAt);
    for (const event of events) desired.set(event.signature(), event);
    const blocked: Set<string> = new Set();
    for (const key of Array.from(records.keys())) {
      if (stillOwner && !await stillOwner()) return false;
      const prefix: string = key.split(':')[0];
      if (!desired.has(key) && !unknown.includes(prefix)) {
        // An edit after a task reminder fired must not re-alert for the same time.
        if (prefix === 'task') {
          try {
            const previous: string[] = JSON.parse(key.substring(5)) as string[];
            const edited = events.find((event: NotifyEvent) => event.key === previous[0]
              && event.fireAt <= Date.now() && String(event.fireAt) === previous[1]);
            if (edited) {
              records.set(edited.signature(), records.get(key) as number);
              records.delete(key);
              if (!stillOwner || await stillOwner()) await NotifyStore.saveScheduled(sid, records, bucket, context);
              continue;
            }
          } catch (_) {
            // Legacy records are reconciled through their stored system ID.
          }
        }
        if (await ReminderAgent.cancel(records.get(key) as number)) {
          records.delete(key);
          if (!stillOwner || await stillOwner()) await NotifyStore.saveScheduled(sid, records, bucket, context);
        } else {
          complete = false;
          try {
            const parts: string[] = JSON.parse(key.substring(key.indexOf(':') + 1)) as string[];
            blocked.add(parts[0]);
          } catch (error) {
            blocked.add(key);
          }
        }
      }
    }
    let quotaExhausted = false;
    for (const key of Array.from(desired.keys())) {
      if (stillOwner && !await stillOwner()) return false;
      if (records.has(key)) continue;
      const event = desired.get(key) as NotifyEvent;
      if (blocked.has(event.key)) continue;
      // 消息键包含原定触发时刻，已进入提前窗口时只补发一次。
      if (event.fireAt <= Date.now()) {
        if (!await NotifyCenter.publishNow(event, stillOwner)) {
          complete = false;
          continue;
        }
        records.set(key, -1);
      } else {
        if (quotaExhausted) continue;
        const result = await ReminderAgent.publish(NotifyCenter.planOf(event), false);
        if (!result.ok) {
          complete = false;
          quotaExhausted = result.code === 1700002;
          continue;
        }
        if (stillOwner && !await stillOwner()) {
          await ReminderAgent.cancel(result.reminderId);
          return false;
        }
        records.set(key, result.reminderId);
      }
      if (!stillOwner || await stillOwner()) await NotifyStore.saveScheduled(sid, records, bucket, context);
    }
    return complete && (!stillOwner || await stillOwner());
  }

  private static async collect(now: number, sid: string): Promise<NotifyInput> {
    const input: NotifyInput = new NotifyInput();
    input.now = now;
    const marks = await Services.marks.refresh(false);
    const snapshotMarks = marks.snapshot;
    const hide = HidePrefs.read(Services.userdata.currentSections());
    input.unavailable = ['hw', 'ntd', 'nts', 'cls', 'vres'];
    const linked = new Set<string>((await TaskRepository.load(false)).map((t: PersonalTask) => t.sourceHwId));

    try {
      const hw: HomeworkResult = await Services.homework.load(false);
      if (hw.ok && hw.message.length === 0 && marks.ok) input.unavailable = input.unavailable.filter((s: string) => s !== 'hw');
      const open: HomeworkRow[] = [];
      for (let i = 0; i < hw.rows.length; i++) {
        if (marks.ok && !hw.rows[i].archived && !snapshotMarks.isDone(MarkKind.HW, hw.rows[i].id) && !hide.hwHide.has(hw.rows[i].id)) {
          open.push(hw.rows[i]);
        }
      }
      input.homework = open.filter((row: HomeworkRow) => !linked.has(row.id));
      if (hw.ok && hw.message.length === 0 && marks.ok && sid === Services.currentSid && !NotifyCenter.ending) {
        await HomeworkReminders.resume(sid, open);
      }
      input.manualHomework = Array.from((await ReminderStore.load(sid)).ids.keys());
    } catch (e) {
      // 忽略单项失败
    }
    try {
      const nt: NoticesResult = await Services.notices.load(false);
      if (nt.ok && nt.message.length === 0 && marks.ok) input.unavailable = input.unavailable.filter((s: string) => s !== 'ntd' && s !== 'nts');
      const entries: NoticeEntry[] = [];
      for (let i = 0; i < nt.entries.length; i++) {
        if (!nt.entries[i].row.hidden && !nt.entries[i].row.archived && marks.ok && !snapshotMarks.isDone(MarkKind.NT_DONE, nt.entries[i].row.id)
          && !hide.ntHide.has(nt.entries[i].id()) && !hide.ntHide.has(nt.entries[i].row.id)) {
          entries.push(nt.entries[i]);
        }
      }
      input.notices = entries;
    } catch (e) {
      // 忽略
    }
    try {
      const tt: TtResult = await Services.timetable.load(false);
      if (tt.ok && tt.message.length === 0) input.unavailable = input.unavailable.filter((s: string) => s !== 'cls');
      const snapshot: TtSnapshot | undefined = tt.snapshot;
      if (snapshot !== undefined && snapshot.c.length > 0) {
        input.classes = TtCalendar.upcomingBells(snapshot, now, 7);
      }
    } catch (e) {
      // 忽略
    }
    try {
      const voteRepo: VoteRepository = Services.vote;
      const pollResult = await voteRepo.list();
      if (pollResult.ok) {
        input.unavailable = input.unavailable.filter((s: string) => s !== 'vres');
        input.polls = pollResult.list.polls;
      }
    } catch (e) {
      // 忽略
    }
    try {
      const state: WaterState = WaterCodec.fromJson(Services.userdata.currentSections()['water']);
      const prefs = PowerPrefs.read(Services.userdata.currentSections());
      let key: string = prefs.sel.trim();
      let room: WaterRoomState | undefined = state.room(key);
      if (room === undefined) {
        state.rooms.forEach((value: WaterRoomState, roomKey: string) => {
          if (room === undefined) {
            room = value;
            key = roomKey;
          }
        });
      }
      input.waterRoom = room;
      input.waterRoomKey = key;
    } catch (e) {
      // 忽略
    }
    return input;
  }

  private static planOf(event: NotifyEvent): ReminderPlan {
    const plan: ReminderPlan = new ReminderPlan();
    const ref: string = event.key.substring(event.key.indexOf(':') + 1);
    if (event.kind === 'task') {
      plan.taskId = ref;
    } else if (event.kind.startsWith('homework')) {
      plan.homeworkId = ref;
    } else if (event.kind.startsWith('notice')) {
      plan.toolId = 'nt';
      plan.noticeId = ref;
    } else {
      plan.toolId = event.kind.startsWith('vote') ? 'vote' : (event.kind === 'class_remind' ? 'tt' : 'water');
    }
    plan.notificationId = NotificationDelivery.id(event.key);
    plan.title = event.title;
    plan.content = event.text;
    plan.triggerAt = event.fireAt;
    plan.dueAt = event.fireAt;
    return plan;
  }

  private static async publishNow(event: NotifyEvent, stillOwner?: () => Promise<boolean>): Promise<boolean> {
    const plan = NotifyCenter.planOf(event);
    const id = NotificationDelivery.id(event.key);
    const ok = await NotificationDelivery.publish(id, event.title, event.text,
      NotificationDelivery.route(plan.toolId, plan.homeworkId, plan.taskId, plan.noticeId));
    if (ok && stillOwner && !await stillOwner()) {
      try { await notificationManager.cancel(id); } catch (_) {}
      return false;
    }
    return ok;
  }
}
