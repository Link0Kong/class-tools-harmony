import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { liveViewManager } from '@kit.LiveViewKit';
import notificationManager from '@ohos.notificationManager';
import { Services } from '../../app/Services';
import { AppPush } from '../../features/push/AppPush';
import { NotifyStore } from './NotifyStore';
import { NotificationDelivery } from './NotificationDelivery';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { SessionInfo } from '../timetable/TimetableModels';
import { CourseWindow } from '../../features/notify/NotifyPlanner';
import { PptRepository } from '../ppt/PptRepository';
import { pptStatusLabel } from '../ppt/PptModels';
import { VoteLogic } from '../vote/VoteLogic';
import { Log } from '../../common/Log';

const COURSE_ID: number = 7240001;
const VOTE_ID: number = 7240002;

export class LiveActivity {
  private static queue: Promise<void> = Promise.resolve();
  private static live: Map<number, string> = new Map();
  private static lastUploadAt: Map<number, number> = new Map();
  private static ordinary: Set<number> = new Set();
  private static last: Map<number, string> = new Map();
  private static fallback: Set<number> = new Set();
  private static foreground: boolean = false;
  private static timer: number = -1;
  private static courseSid: string = '';
  private static classes: SessionInfo[] = [];
  private static clockOffset: number = 0;
  private static voteExpiry: number = 0;
  private static lead: number = 0;
  private static courseNotice: number = 0;
  private static uploads: Set<number> = new Set();

  private static run(work: () => Promise<void>): Promise<void> {
    LiveActivity.queue = LiveActivity.queue.then(work).catch(() => {
      Log.w('LiveActivity', '实时通知暂不可用');
    });
    return LiveActivity.queue;
  }

  static async available(): Promise<boolean> {
    try {
      return canIUse('SystemCapability.LiveView.LiveViewService') && await liveViewManager.isLiveViewEnabled();
    } catch (e) {
      return false;
    }
  }

  static foregroundChanged(value: boolean): void {
    LiveActivity.foreground = value;
    LiveActivity.updateCourse();
  }

  static releasePage(): void {
    LiveActivity.foreground = false;
    LiveActivity.coursePlan('', [], 0);
    LiveActivity.endVote();
  }

  static coursePlan(sid: string, classes: SessionInfo[], lead: number): void {
    LiveActivity.courseSid = sid;
    LiveActivity.classes = classes;
    LiveActivity.lead = lead;
    LiveActivity.updateCourse();
  }

  private static updateCourse(): void {
    clearTimeout(LiveActivity.timer);
    const sid: string = LiveActivity.courseSid;
    if (!sid || sid !== Services.currentSid || LiveActivity.lead === 0) {
      LiveActivity.stop(COURSE_ID);
      return;
    }
    if (!LiveActivity.foreground) {
      return;
    }
    const now: number = Date.now();
    const offset = now - systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
    if (Math.abs(offset - LiveActivity.clockOffset) > 1000) {
      LiveActivity.last.delete(COURSE_ID);
      LiveActivity.clockOffset = offset;
    }
    const window: CourseWindow = CourseWindow.select(LiveActivity.classes, LiveActivity.lead, now);
    const cls = window.session;
    if (cls) {
      const room = cls.fullRoom || cls.room;
      const msg = cls.startText + (cls.endText ? '–' + cls.endText : '') + (room ? ' · ' + room : '');
      LiveActivity.run(async () => {
        const left: number = cls.startAt - Date.now();
        if (left <= 0 || !await LiveActivity.allowed(sid)) return;
        const noteId = NotificationDelivery.id('cls:' + cls.startAt + ':' + cls.name);
        const key = String(cls.startAt) + cls.name + msg;
        if (!canIUse('SystemCapability.LiveView.LiveViewService')) {
          await LiveActivity.publishFallback(COURSE_ID, noteId, cls.name, msg, 'tt', key, cls.startAt);
          return;
        }
        const timer: liveViewManager.TimerCapsule = {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER, status: 1, icon: 'live_icon.png',
          content: '上课', time: left, isCountdown: true
        };
        const view: liveViewManager.LiveView = {
          id: COURSE_ID, event: 'SCHEDULE', timer: { time: left, isCountdown: true },
          lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
          liveViewData: { primary: { title: cls.name, content: [{ text: msg }],
            aliveTime: Math.ceil(left / 1000) }, capsule: timer }
        };
        await LiveActivity.display(view, 'tt', msg, key, cls.startAt, noteId);
      });
    } else {
      LiveActivity.stop(COURSE_ID);
    }
    if (window.nextAt > now) {
      LiveActivity.timer = setTimeout(() => LiveActivity.updateCourse(), Math.min(60000, window.nextAt - now + 25));
    }
  }

  static upload(id: number, sid: string, name: string, percent: number, stage: string): void {
    LiveActivity.uploads.add(id);
    const determinate = (stage === '上传中' || stage === '转换中') && Number.isFinite(percent) && percent >= 0;
    const completed: number = Math.max(0, Math.min(100, Math.floor(percent)));
    const text = stage + (determinate ? ' ' + completed + '%' : '');
    LiveActivity.run(async () => {
      if (!LiveActivity.uploads.has(id) || !await LiveActivity.allowed(sid)) {
        return;
      }
      const time: number = Date.now();
      const last: number = LiveActivity.lastUploadAt.get(id) || 0;
      if (stage === '上传中' && completed > 0 && completed < 100 && time - last < 1500) return;
      LiveActivity.lastUploadAt.set(id, time);
      if (!canIUse('SystemCapability.LiveView.LiveViewService')) {
        await LiveActivity.publishFallback(id, id, name, text, 'ppt', text, time + 1800000);
        return;
      }
      const progress: liveViewManager.ProgressCapsule = { type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
        status: 1, icon: 'live_icon.png', max: 100, progress: completed, indeterminate: true, content: stage };
      const phase: liveViewManager.TextCapsule = { type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
        status: 1, icon: 'live_icon.png', title: name, content: stage };
      const primary: liveViewManager.PrimaryData = { title: name, content: [{ text: text }], aliveTime: 1800 };
      if (determinate) {
        const layout: liveViewManager.ProgressLayout = {
          layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS, progress: completed
        };
        primary.layoutData = layout;
      }
      const view: liveViewManager.LiveView = {
        id: id, event: 'PROGRESS', subEvent: 'UPLOAD', lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
        liveViewData: { primary: primary, capsule: determinate ? progress : phase }
      };
      await LiveActivity.display(view, 'ppt', text, text, Date.now() + 1800000);
    });
  }

  static async followConversion(sid: string, deckId: string, name: string, id: number): Promise<void> {
    if (!await LiveActivity.allowed(sid)) {
      await LiveActivity.stop(id);
      return;
    }
    const started = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
    LiveActivity.upload(id, sid, name, -1, '排队中');
    const repo: PptRepository = new PptRepository(Services.api);
    while (LiveActivity.uploads.has(id) && Services.currentSid === sid && systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) - started < 1800000) {
      await new Promise<void>((resolve) => { setTimeout(resolve, 10000); });
      if (!LiveActivity.uploads.has(id) || sid !== Services.currentSid) {
        return;
      }
      const deck = await repo.conversionStatus(deckId);
      if (!deck || !LiveActivity.uploads.has(id) || sid !== Services.currentSid) {
        continue;
      }
      if (deck.status === 'failed' || deck.status === 'ready') {
        await LiveActivity.finishUpload(id, sid, name, deck.status === 'ready' ? '转换完成' : '转换失败');
        return;
      }
      LiveActivity.upload(id, sid, name, deck.progressKnown ? deck.progress : -1, pptStatusLabel(deck.status));
    }
    await LiveActivity.stop(id);
  }

  static async finishUpload(id: number, sid: string, name: string, result: string): Promise<void> {
    await LiveActivity.stop(id);
    if (await LiveActivity.allowed(sid)) {
      await NotificationDelivery.publish(id, result, name, NotificationDelivery.route('ppt'));
    }
  }

  static vote(sid: string, title: string, deadline: number, now: number): void {
    const minutes: number = Math.ceil((deadline - now) / 60000);
    if (minutes <= 0) {
      LiveActivity.stop(VOTE_ID);
      return;
    }
    const expires = Date.now() + deadline - now;
    const message = title + ' · 剩余 ' + minutes + ' 分钟 · ' + VoteLogic.deadlineText(deadline);
    LiveActivity.run(async () => {
      if ((LiveActivity.last.get(VOTE_ID) === message && Math.abs(expires - LiveActivity.voteExpiry) <= 1000)
        || !await LiveActivity.allowed(sid)) {
        return;
      }
      if (await NotificationDelivery.publish(VOTE_ID, '限时投票', message, NotificationDelivery.route('vote'), expires)) {
        LiveActivity.voteExpiry = expires;
        LiveActivity.ordinary.add(VOTE_ID);
        LiveActivity.last.set(VOTE_ID, message);
      }
    });
  }

  static endVote(): void {
    LiveActivity.stop(VOTE_ID);
  }

  private static async allowed(sid: string): Promise<boolean> {
    if (!sid || Services.currentSid !== sid || !await AppPush.systemEnabled()) {
      return false;
    }
    const prefs: NotifySettings = await NotifyStore.loadSettings(sid);
    return Services.currentSid === sid && prefs.master && prefs.liveActivities;
  }

  private static async display(view: liveViewManager.LiveView, toolId: string, text: string, key: string,
    until: number, fallbackId: number = view.id): Promise<void> {
    const id: number = view.id;
    if (LiveActivity.last.get(id) === key) {
      return;
    }
    if (!LiveActivity.fallback.has(id) && await LiveActivity.available()) {
      try {
        view.liveViewData.primary.clickAction = await NotificationDelivery.action(id, NotificationDelivery.route(toolId));
        const result = LiveActivity.live.has(id) ? await liveViewManager.updateLiveView(view)
          : await liveViewManager.startLiveView(view);
        // 部分区域显示失败时，系统仍可能保留实况卡片，需先撤回再降级。
        LiveActivity.live.set(id, view.event);
        if (result.resultCode === 0) {
          LiveActivity.last.set(id, key);
          return;
        }
      } catch (e) {
        Log.i('LiveActivity', view.event + ' 实况窗返回 ' + (e as BusinessError).code);
      }
      await LiveActivity.endNative(id);
      LiveActivity.fallback.add(id);
    }
    await LiveActivity.publishFallback(id, fallbackId, view.liveViewData.primary.title || '进度', text, toolId, key, until);
  }

  private static async publishFallback(id: number, fallbackId: number, title: string, text: string, toolId: string,
    key: string, until: number): Promise<void> {
    if (LiveActivity.last.get(id) === key) return;
    if (await NotificationDelivery.publish(fallbackId, title, text, NotificationDelivery.route(toolId), until)) {
      if (id === COURSE_ID) LiveActivity.courseNotice = fallbackId;
      LiveActivity.ordinary.add(fallbackId);
      LiveActivity.last.set(id, key);
    }
  }

  private static async endNative(id: number): Promise<void> {
    const event: string | undefined = LiveActivity.live.get(id);
    if (event) {
      try {
        await liveViewManager.stopLiveView({ id: id, event: event, liveViewData: { primary: { keepTime: 0 } } });
      } catch (e) {
        Log.i('LiveActivity', '实况窗已结束或服务不可用');
      }
      LiveActivity.live.delete(id);
    }
  }

  private static stop(id: number): Promise<void> {
    LiveActivity.uploads.delete(id);
    LiveActivity.lastUploadAt.delete(id);
    return LiveActivity.run(async () => {
      await LiveActivity.endNative(id);
      const ordinaryId: number = id === COURSE_ID ? LiveActivity.courseNotice : id;
      if (LiveActivity.ordinary.delete(ordinaryId)) {
        try {
          await notificationManager.cancel(ordinaryId);
        } catch (e) {
          Log.i('LiveActivity', '通知已撤除');
        }
      }
      LiveActivity.last.delete(id);
      LiveActivity.fallback.delete(id);
    });
  }

  static async clear(): Promise<void> {
    LiveActivity.courseSid = '';
    LiveActivity.classes = [];
    clearTimeout(LiveActivity.timer);
    const ids: number[] = Array.from(LiveActivity.uploads);
    ids.push(VOTE_ID, COURSE_ID);
    for (const id of ids) {
      await LiveActivity.stop(id);
    }
  }
}

