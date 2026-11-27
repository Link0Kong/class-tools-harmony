import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { liveViewManager } from '@kit.LiveViewKit';
import notificationManager from '@ohos.notificationManager';
import { Services } from '../../app/Services';
import { ToolLaunch } from '../../app/ToolLaunch';
import { AppPush } from '../../features/push/AppPush';
import { NotifyStore } from './NotifyStore';
import { NotificationDelivery } from './NotificationDelivery';
import { SessionInfo } from '../timetable/TimetableModels';
import { TimetableFocus } from '../timetable/TimetableFocus';
import { CourseWindow } from '../../features/notify/NotifyPlanner';
import { LiveRecord, LiveRecords } from './LiveRecord';
import { PollSummary } from '../vote/VoteModels';
import { VoteLogic } from '../vote/VoteLogic';
import { Log } from '../../common/Log';

/** Local activity changes are serialized. Receivers/timers re-read the owning identity and absolute deadline. */
export class LiveActivity {
  private static queue: Promise<void> = Promise.resolve();
  private static timer: number = -1;
  private static foreground: boolean = false;
  private static owner: string = '';
  private static classes: SessionInfo[] = [];
  private static lead: number = 0;
  private static breakLead: number = 3;
  private static polling: Set<number> = new Set();
  private static uploading: Set<number> = new Set();

  private static run(work: () => Promise<void>): Promise<void> {
    LiveActivity.queue = LiveActivity.queue.then(work).catch(() => { Log.w('LiveActivity', '更新当前活动失败'); });
    return LiveActivity.queue;
  }

  static async available(): Promise<boolean> {
    try {
      return canIUse('SystemCapability.LiveView.LiveViewService') && await liveViewManager.isLiveViewEnabled();
    } catch (_) { return false; }
  }

  static items(sid: string): LiveRecord[] {
    return LiveRecords.all(sid).filter((item: LiveRecord) => !item.endedAt && item.until > Date.now())
      .sort((a: LiveRecord, b: LiveRecord) => a.until - b.until);
  }

  private static get(sid: string, id: number): LiveRecord | undefined {
    return LiveRecords.all(sid).find((row: LiveRecord) => row.id === id);
  }

  static courseId(sid: string, cls: SessionInfo): number {
    return NotificationDelivery.id('schedule:' + sid + ':' + JSON.stringify(TimetableFocus.fromSession(cls)));
  }

  static async refreshBackground(context: common.Context): Promise<void> {
    await LiveRecords.refreshBackground(context);
  }

  static ownsCourse(sid: string, cls: SessionInfo, context?: common.Context): boolean {
    const id = LiveActivity.courseId(sid, cls);
    if (context) return LiveRecords.presentInBackground(sid, id, context);
    const row = LiveActivity.get(sid, id);
    return !!row && (row.endedAt > 0 || row.hidden || row.surface === 'native');
  }

  static foregroundChanged(value: boolean): void {
    LiveActivity.foreground = value;
    LiveActivity.reconcile();
  }

  static releasePage(): void {
    LiveActivity.foreground = false;
    LiveActivity.reconcile();
  }

  static coursePlan(sid: string, classes: SessionInfo[], lead: number, breakLead: number = 3): Promise<void> {
    LiveActivity.owner = sid;
    LiveActivity.classes = classes;
    LiveActivity.lead = lead;
    LiveActivity.breakLead = breakLead;
    return LiveActivity.reconcile();
  }

  static reconcile(): Promise<void> {
    return LiveActivity.run(async () => {
      const sid = Services.currentSid;
      if (!sid) return;
      clearTimeout(LiveActivity.timer);
      const now = Date.now();
      const window = CourseWindow.select(LiveActivity.owner === sid && LiveActivity.lead ? LiveActivity.classes : [],
        LiveActivity.lead, now, LiveActivity.breakLead);
      const cls = window.session;
      const id = cls ? LiveActivity.courseId(sid, cls) : 0;
      for (const item of LiveRecords.all(sid).slice()) {
        if (item.endedAt) {
          if (now - item.endedAt > 7 * 86400000) LiveRecords.remove(item);
        } else if (item.until <= now || (item.kind === 'tt' && LiveActivity.owner === sid && item.id !== id)) {
          await LiveActivity.end(item);
        } else if (item.conversion && !LiveActivity.polling.has(item.id)) {
          LiveActivity.poll(item);
        } else if ((item.kind === 'file' || item.kind === 'ppt') && !item.conversion && !LiveActivity.uploading.has(item.id)) {
          await LiveActivity.end(item);
        }
      }
      if (cls && !LiveActivity.get(sid, id)?.endedAt && (LiveActivity.foreground || LiveActivity.get(sid, id))) {
        const launch = new ToolLaunch('tt');
        launch.owner = sid;
        launch.timetableFocus = TimetableFocus.fromSession(cls);
        const row = LiveActivity.get(sid, id) ?? LiveActivity.create(id, launch, cls.name, cls.startAt);
        row.noticeId = NotificationDelivery.id(sid + ':' + TimetableFocus.reminderKey(cls));
        const room = cls.fullRoom || cls.room;
        const lines = [cls.startText + (cls.endText ? '–' + cls.endText : '') + (cls.span ? ' · 第 ' + cls.span : '')];
        if (room) lines.unshift(room);
        if (cls.teacher) lines.push(cls.teacher);
        if (cls.dateText) lines.push(cls.dateText + (cls.week ? ' · 第 ' + cls.week + ' 周' : ''));
        await LiveActivity.show(row, lines.join(' · '), -1);
      }
      if (sid !== Services.currentSid) return;
      const deadlines = LiveRecords.all(sid).filter((row: LiveRecord) => !row.endedAt).map((item: LiveRecord) => item.until);
      if (window.nextAt > now && LiveActivity.foreground) deadlines.push(window.nextAt);
      if (deadlines.length > 0) {
        const wait = Math.min(...deadlines) - Date.now();
        LiveActivity.timer = setTimeout(() => { LiveActivity.reconcile(); }, Math.max(1, Math.min(wait, LiveActivity.foreground ? 60000 : 2147483647)));
      }
    });
  }

  private static create(id: number, launch: ToolLaunch, title: string, until: number): LiveRecord {
    const row = new LiveRecord();
    row.id = id;
    row.noticeId = id;
    row.owner = launch.owner;
    row.kind = launch.toolId;
    row.parameters = launch.parameters();
    row.title = title;
    row.until = until;
    LiveRecords.save(row);
    return row;
  }

  private static async allowed(sid: string): Promise<boolean> {
    if (sid !== Services.currentSid || !await AppPush.systemEnabled()) return false;
    const settings = await NotifyStore.loadSettings(sid);
    return sid === Services.currentSid && settings.master && settings.liveActivities;
  }

  private static async show(row: LiveRecord, text: string, percent: number): Promise<void> {
    if (row.endedAt || row.owner !== Services.currentSid || row.until <= Date.now()) return;
    const unchanged = row.text === text;
    if (!unchanged) {
      row.text = text;
      row.updated = Date.now();
      LiveRecords.save(row);
    }
    if (row.hidden || (unchanged && row.surface) || !await LiveActivity.allowed(row.owner)) return;
    if (row.until <= Date.now()) return;
    if (row.surface === 'ordinary' && await LiveActivity.removed(row)) {
      row.hidden = true;
      LiveRecords.save(row);
      return;
    }
    const left = row.until - Date.now();
    const native = row.kind !== 'vote' && row.surface !== 'ordinary' && left >= 15000 && await LiveActivity.available();
    if (native) {
      const course = row.kind === 'tt';
      const detail = course ? '距上课 ' + '${placeholder.timer}' + ' · ' + text : text;
      const primary: liveViewManager.PrimaryData = { title: row.title.slice(0, 120), content: [{ text: detail.slice(0, 124) }],
        aliveTime: Math.floor(left / 1000), clickAction: await NotificationDelivery.action(row.id, row.parameters) };
      const view: liveViewManager.LiveView = { id: row.id, event: course ? 'SCHEDULE' : 'PROGRESS',
        isMute: true, lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
        liveViewData: { primary: primary } };
      if (course) {
        view.timer = { time: left, isCountdown: true };
        view.liveViewData.capsule = { type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER, status: 1, icon: 'live_icon.png',
          content: row.title.slice(0, 32), time: left, isCountdown: true } as liveViewManager.TimerCapsule;
      } else {
        view.subEvent = 'UPLOAD';
        if (percent >= 0) {
          primary.layoutData = { layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS, progress: percent } as liveViewManager.ProgressLayout;
          view.liveViewData.capsule = { type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS, status: 1,
            max: 100, progress: percent, indeterminate: false, icon: 'live_icon.png', content: text.slice(0, 32) } as liveViewManager.ProgressCapsule;
        } else {
          view.liveViewData.capsule = { type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT, status: 1,
            icon: 'live_icon.png', title: row.title.slice(0, 32), content: text.slice(0, 32) } as liveViewManager.TextCapsule;
        }
      }
      if (row.owner !== Services.currentSid || row.until <= Date.now()) return;
      try {
        const result = row.surface === 'native' ? await liveViewManager.updateLiveView(view) : await liveViewManager.startLiveView(view);
        if (result.resultCode === 0) {
          if (row.noticeId !== row.id && !row.surface) {
            try { await notificationManager.cancel(row.noticeId); } catch (_) {}
          }
          row.surface = 'native';
          LiveRecords.save(row);
          return;
        }
      } catch (err) { Log.i('LiveActivity', view.event + ' 系统返回 ' + (err as BusinessError).code); }
      if (row.surface === 'native') {
        if (await LiveActivity.removed(row)) {
          row.hidden = true;
          LiveRecords.save(row);
        }
        return;
      }
      try {
        await liveViewManager.stopLiveView({ id: row.id, event: view.event, liveViewData: { primary: { keepTime: 0 } } });
      } catch (_) {}
    } else if (row.surface === 'native') return;
    if (row.owner !== Services.currentSid || row.until <= Date.now()) return;
    if (await NotificationDelivery.publish(row.noticeId, row.title, text, row.parameters, row.until)) {
      row.surface = 'ordinary';
      LiveRecords.save(row);
    }
  }

  private static async removed(row: LiveRecord): Promise<boolean> {
    if (row.surface === 'ordinary') {
      try {
        const posted = await notificationManager.getActiveNotifications();
        return !posted.some((n: notificationManager.NotificationRequest) => n.id === row.noticeId);
      } catch (_) { return false; }
    }
    if (row.surface === 'native') {
      try { await liveViewManager.getActiveLiveView(row.id); }
      catch (err) { return (err as BusinessError).code === 1003500009; }
    }
    return false;
  }

  private static async withdraw(row: LiveRecord): Promise<void> {
    if (row.surface === 'native') {
      try { await liveViewManager.stopLiveView({ id: row.id, event: row.kind === 'tt' ? 'SCHEDULE' : 'PROGRESS',
        liveViewData: { primary: { keepTime: 0 } } }); } catch (_) {}
    } else if (row.surface === 'ordinary') {
      try { await notificationManager.cancel(row.noticeId); } catch (_) {}
    }
    row.surface = '';
  }

  private static async end(row: LiveRecord): Promise<void> {
    await LiveActivity.withdraw(row);
    if (row.kind === 'tt') {
      row.endedAt = Date.now();
      LiveRecords.save(row);
    } else LiveRecords.remove(row);
  }

  static hide(id: number): Promise<void> {
    const sid = Services.currentSid;
    return LiveActivity.run(async () => {
      if (sid !== Services.currentSid) return;
      const row = LiveActivity.get(sid, id);
      if (!row) return;
      row.hidden = true;
      await LiveActivity.withdraw(row);
      LiveRecords.save(row);
    });
  }

  static followed(sid: string, pollId: string): boolean {
    return !!LiveActivity.get(sid, NotificationDelivery.id('vote:' + sid + ':' + pollId));
  }

  static vote(sid: string, pollId: string, title: string, deadline: number, now: number, follow: boolean): Promise<void> {
    return LiveActivity.run(async () => {
      if (sid !== Services.currentSid) return;
      const id = NotificationDelivery.id('vote:' + sid + ':' + pollId);
      const previous = LiveActivity.get(sid, id);
      if (!follow || deadline <= now) {
        if (previous) await LiveActivity.end(previous);
        return;
      }
      const launch = new ToolLaunch('vote');
      launch.owner = sid;
      launch.objectId = pollId;
      const row = previous ?? LiveActivity.create(id, launch, title, Date.now() + deadline - now);
      if (!previous) LiveActivity.reconcile();
      const expires = Date.now() + deadline - now;
      if (Math.abs(expires - row.until) > 1000 || row.title !== title) {
        row.until = expires;
        row.title = title;
        row.text = '';
      }
      await LiveActivity.show(row, '关注的投票 · ' + VoteLogic.deadlineText(deadline), -1);
    });
  }

  static reconcileVotes(sid: string, polls: PollSummary[]): Promise<void> {
    return LiveActivity.run(async () => {
      if (sid !== Services.currentSid) return;
      for (const row of LiveRecords.all(sid).filter((r: LiveRecord) => r.kind === 'vote')) {
        const poll = polls.find((p: PollSummary) => p.id === row.launch()?.objectId);
        if (!poll || poll.closed || poll.status === 'closed' || row.until <= Date.now()) {
          await LiveActivity.end(row);
        } else if (poll.deadline > 0 && (row.title !== poll.title || row.text.indexOf(VoteLogic.deadlineText(poll.deadline)) < 0)) {
          row.until = poll.deadline;
          row.title = poll.title;
          await LiveActivity.show(row, '关注的投票 · ' + VoteLogic.deadlineText(poll.deadline), -1);
        }
      }
    });
  }

  static upload(id: number, sid: string, name: string, percent: number, stage: string,
    tool: string = 'ppt', objectId: string = ''): void {
    if (sid !== Services.currentSid) return;
    LiveActivity.uploading.add(id);
    LiveActivity.run(async () => {
      if (sid !== Services.currentSid) return;
      const existing = LiveActivity.get(sid, id);
      if (existing && percent > 0 && percent < 100 && Date.now() - existing.updated < 1500) return;
      const launch = new ToolLaunch(tool);
      launch.owner = sid;
      launch.objectId = objectId;
      const row = existing ?? LiveActivity.create(id, launch, name, Date.now() + 1800000);
      if (objectId) row.parameters = launch.parameters();
      const value = percent < 0 ? -1 : Math.min(100, Math.max(0, Math.floor(percent)));
      await LiveActivity.show(row, stage + (value >= 0 ? ' ' + value + '%' : ''), value);
    });
  }

  static followConversion(sid: string, objectId: string, name: string, id: number, tool: string = 'ppt'): void {
    LiveActivity.run(async () => {
      if (sid !== Services.currentSid) return;
      LiveActivity.uploading.delete(id);
      const launch = new ToolLaunch(tool);
      launch.owner = sid;
      launch.objectId = objectId;
      const row = LiveActivity.get(sid, id) ?? LiveActivity.create(id, launch, name, Date.now() + 1800000);
      row.parameters = launch.parameters();
      row.conversion = true;
      row.until = Date.now() + 1800000;
      LiveRecords.save(row);
      await LiveActivity.show(row, '等待转换', -1);
      LiveActivity.poll(row);
    });
  }

  private static async poll(row: LiveRecord): Promise<void> {
    if (LiveActivity.polling.has(row.id)) return;
    LiveActivity.polling.add(row.id);
    const id = row.launch()?.objectId ?? '';
    let delay = 5000;
    try {
      while (row.owner === Services.currentSid && LiveActivity.get(row.owner, row.id) === row && row.until > Date.now()) {
        await new Promise<void>((resolve) => { setTimeout(resolve, delay); });
        if (row.owner !== Services.currentSid || LiveActivity.get(row.owner, row.id) !== row) return;
        let status = '';
        let error = '';
        let percent = -1;
        try {
          if (row.kind === 'file') {
            const reply = await Services.cloudspace.conversionStatus(id);
            if (reply.value) {
              status = reply.value.status;
              error = reply.value.error;
              if (reply.value.progressKnown) percent = reply.value.progress;
            } else if (reply.error?.status === 404 || reply.error?.status === 410) {
              status = 'failed';
              error = '文件已移除或到期';
            }
          } else {
            const deck = await Services.ppt.conversionStatus(id);
            if (deck) {
              status = deck.status;
              error = deck.error;
              if (deck.progressKnown) percent = deck.progress;
            }
          }
        } catch (_) {}
        if (row.owner !== Services.currentSid || LiveActivity.get(row.owner, row.id) !== row) return;
        if (status === 'ready' || status === 'failed') {
          await LiveActivity.finishUpload(row.id, row.owner, row.title, status === 'ready' ? '转换完成，可下载' : '转换失败' + (error ? ' · ' + error.slice(0, 80) : ''));
          return;
        }
        delay = status ? 10000 : Math.min(60000, delay * 2);
        if (status) await LiveActivity.run(async () => {
          if (row.owner === Services.currentSid && LiveActivity.get(row.owner, row.id) === row) {
            const processing = status === 'processing' || status === 'converting';
            const value = processing ? percent : -1;
            await LiveActivity.show(row, processing ? '转换中' + (value >= 0 ? ' ' + value + '%' : '') : '等待转换', value);
          }
        });
      }
      if (row.owner === Services.currentSid && LiveActivity.get(row.owner, row.id) === row) {
        await LiveActivity.finishUpload(row.id, row.owner, row.title, '状态查询超时，进入任务查看进度');
      }
    } finally { LiveActivity.polling.delete(row.id); }
  }

  static finishUpload(id: number, sid: string, name: string, result: string, objectId: string = ''): Promise<void> {
    return LiveActivity.run(async () => {
      LiveActivity.uploading.delete(id);
      if (sid !== Services.currentSid) return;
      const row = LiveActivity.get(sid, id);
      if (!row) return;
      const dismissed = row.hidden || (row.until > Date.now() && await LiveActivity.removed(row));
      const route = row.parameters;
      if (objectId) route['objectId'] = objectId;
      await LiveActivity.end(row);
      if (!dismissed && await LiveActivity.allowed(sid)) await NotificationDelivery.publish(id, result, name, route);
    });
  }

  static suspendDisplays(sid: string): Promise<void> {
    return LiveActivity.run(async () => {
      if (!sid || sid !== Services.currentSid) return;
      for (const row of LiveRecords.all(sid)) {
        if (!row.surface) continue;
        await LiveActivity.withdraw(row);
        LiveRecords.save(row);
      }
    });
  }

  static clear(sid: string = Services.currentSid): Promise<void> {
    clearTimeout(LiveActivity.timer);
    LiveActivity.owner = '';
    LiveActivity.classes = [];
    return LiveActivity.run(async () => {
      if (!sid) return;
      for (const row of LiveRecords.all(sid).slice()) {
        await LiveActivity.withdraw(row);
        LiveRecords.remove(row);
      }
    });
  }
}
