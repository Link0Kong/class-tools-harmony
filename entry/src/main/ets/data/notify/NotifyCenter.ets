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
  private static running: boolean = false;
  private static pendingForce: boolean = false;
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
    try {
      const request: notificationManager.NotificationRequest = {
        id: 20261118,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '枫丹工具箱 · 测试通知',
            text: '通知已开启，作业、通知、投票与水费提醒会在这里出现。',
            additionalText: '枫丹工具箱'
          }
        }
      };
      await notificationManager.publish(request);
      return true;
    } catch (e) {
      Log.w('NotifyCenter', '发送测试通知失败');
      return false;
    }
  }

  static async saveSettings(settings: NotifySettings): Promise<void> {
    await NotifyStore.saveSettings(Services.currentSid, settings);
  }

  /** 扫描并发送通知；force=true 时忽略 3 分钟节流（设置变更后）。 */
  static async syncAll(force: boolean = false): Promise<void> {
    const sid: string = Services.currentSid;
    if (sid.length === 0) {
      return;
    }
    if (NotifyCenter.running) {
      // 后台/退场前的强制扫描不能因为上一轮未结束而丢失
      if (force) {
        NotifyCenter.pendingForce = true;
      }
      return;
    }
    const now: number = Date.now();
    if (!force && now - NotifyCenter.lastRunAt < THROTTLE_MS) {
      return;
    }
    const settings: NotifySettings = await NotifyStore.loadSettings(sid);
    if (!settings.active()) {
      return;
    }
    if (!(await AppPush.systemEnabled())) {
      return;
    }
    NotifyCenter.running = true;
    try {
      const input: NotifyInput = await NotifyCenter.collect(now, sid);
      const snapshot: NotifySnapshot = await NotifyStore.loadSnapshot(sid);
      const events: NotifyEvent[] = NotifyPlanner.plan(input, settings, snapshot);
      const scheduled: Map<string, number> = await NotifyStore.loadScheduled(sid);
      for (let i = 0; i < events.length; i++) {
        const event: NotifyEvent = events[i];
        if (event.fireAt > now + 60 * 1000) {
          if (!scheduled.has(event.key)) {
            const plan: ReminderPlan = NotifyCenter.planOf(event);
            const result: ReminderPublishResult = await ReminderAgent.publish(plan);
            if (result.ok) {
              scheduled.set(event.key, result.reminderId);
            }
          }
        } else {
          await NotifyCenter.publishNow(event);
        }
      }
      await NotifyStore.saveScheduled(sid, scheduled);
      await NotifyStore.saveSnapshot(sid, NotifyPlanner.nextSnapshot(input, snapshot));
      NotifyCenter.lastRunAt = now;
      await NotifyStore.setLastRun(sid, now);
    } catch (e) {
      Log.w('NotifyCenter', '通知扫描失败');
    } finally {
      NotifyCenter.running = false;
      if (NotifyCenter.pendingForce) {
        NotifyCenter.pendingForce = false;
        NotifyCenter.syncAll(true);
      }
    }
  }

  private static async collect(now: number, sid: string): Promise<NotifyInput> {
    const input: NotifyInput = new NotifyInput();
    input.now = now;
    const snapshotMarks = Services.marks.marks();
    try {
      const hw: HomeworkResult = await Services.homework.load(false);
      const open: HomeworkRow[] = [];
      for (let i = 0; i < hw.rows.length; i++) {
        if (!snapshotMarks.isDone(MarkKind.HW, hw.rows[i].id)) {
          open.push(hw.rows[i]);
        }
      }
      input.homework = open;
    } catch (e) {
      // 忽略单项失败
    }
    try {
      const nt: NoticesResult = await Services.notices.load(false);
      const entries: NoticeEntry[] = [];
      for (let i = 0; i < nt.entries.length; i++) {
        if (!snapshotMarks.isDone(MarkKind.NT_DONE, nt.entries[i].row.id)) {
          entries.push(nt.entries[i]);
        }
      }
      input.notices = entries;
    } catch (e) {
      // 忽略
    }
    try {
      const tt: TtResult = await Services.timetable.load(false);
      const snapshot: TtSnapshot | undefined = tt.snapshot;
      if (snapshot !== undefined && snapshot.c.length > 0) {
        const termStart: Date | undefined = TtCalendar.parseTermStart(snapshot.termStart());
        const base: Date = new Date(now);
        const classes: SessionInfo[] = [];
        for (let d = 0; d < 7; d++) {
          const date: Date = new Date(base.getFullYear(), base.getMonth(), base.getDate() + d, 0, 0, 0);
          const list: SessionInfo[] = TtCalendar.sessionsOn(snapshot.c, termStart, date, now);
          for (let i = 0; i < list.length; i++) {
            if (list[i].startAt > now) {
              classes.push(list[i]);
            }
          }
        }
        input.classes = classes;
      }
    } catch (e) {
      // 忽略
    }
    try {
      const voteRepo: VoteRepository = Services.vote;
      const pollResult = await voteRepo.list();
      if (pollResult.ok) {
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
    plan.homeworkId = event.key;
    plan.title = event.title;
    plan.content = event.text;
    plan.triggerAt = event.fireAt;
    plan.dueAt = event.fireAt;
    return plan;
  }

  private static async publishNow(event: NotifyEvent): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: NotifyCenter.idOf(event.key),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: event.title,
            text: event.text,
            additionalText: '枫丹工具箱'
          }
        }
      };
      await notificationManager.publish(request);
    } catch (e) {
      Log.w('NotifyCenter', '发送通知失败');
    }
  }

  private static idOf(key: string): number {
    let hash: number = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) | 0;
    }
    const positive: number = hash < 0 ? -hash : hash;
    return positive % 2000000000 + 1;
  }
}
