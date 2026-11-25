import { AppGlobal } from '../app/AppGlobal';
import { Services } from '../app/Services';
import { HidePrefs } from '../data/home/HidePrefs';
import { TaskRepository } from '../data/tasks/TaskRepository';
import { DeskFeed } from './DeskContent';
import { DeskFormStore } from './DeskFormStore';
import { Log } from '../common/Log';
import { applyDeskData } from './DeskProjection';

/** Snapshots only travel between the application and its form extension in the app sandbox. */
export class DeskForms {
  private static generation: number = 0;
  private static activeSid: string = '';

  static async sessionChanged(sid: string): Promise<void> {
    DeskForms.activeSid = sid;
    DeskForms.generation++;
    const dir = AppGlobal.context?.filesDir;
    if (!dir) return;
    try {
      if (DeskFormStore.feed(dir).sid !== sid) {
        const feed = new DeskFeed();
        feed.sid = sid;
        DeskFormStore.save(dir, feed);
        await DeskFormStore.publish(dir);
      }
    } catch (_) {
      Log.w('DeskForms', '无法重置卡片缓存');
    }
  }

  static async refresh(): Promise<void> {
    const sid = Services.currentSid;
    const dir = AppGlobal.context?.filesDir;
    if (!sid || !dir || sid !== DeskForms.activeSid) return;
    const version = ++DeskForms.generation;
    try {
      const ttLoad = Services.timetable.load(false);
      const hwLoad = Services.homework.load(false);
      const ntLoad = Services.notices.load(false);
      const marksLoad = Services.marks.refresh(false);
      const taskLoad = TaskRepository.load(false);
      const tt = await ttLoad;
      const hw = await hwLoad;
      const nt = await ntLoad;
      const marks = await marksLoad;
      const tasks = await taskLoad;
      if (version !== DeskForms.generation || sid !== Services.currentSid || sid !== DeskForms.activeSid) return;
      let feed = DeskFormStore.feed(dir);
      if (feed.sid !== sid) feed = new DeskFeed();
      feed.sid = sid;
      const resolved = tasks.length > 0 || TaskRepository.status() === '已同步' || feed.taskAt > 0;
      applyDeskData(feed, HidePrefs.read(Services.userdata.currentSections()), tt, hw, nt, marks, resolved ? tasks : undefined);
      feed.refreshedAt = Date.now();
      DeskFormStore.save(dir, feed);
      await DeskFormStore.publish(dir);
    } catch (_) {
      Log.w('DeskForms', '刷新桌面卡片失败');
    }
  }
}
