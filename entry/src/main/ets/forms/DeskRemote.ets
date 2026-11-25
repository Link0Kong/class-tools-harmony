import { common } from '@kit.AbilityKit';
import { BackgroundReads } from '../data/sync/BackgroundReads';
import { HidePrefs } from '../data/home/HidePrefs';
import { HomeworkRepository } from '../data/homework/HomeworkRepository';
import { HttpClient } from '../data/net/HttpClient';
import { NoticesRepository } from '../data/notices/NoticesRepository';
import { SessionStore } from '../data/session/SessionStore';
import { JsonBlob } from '../data/sync/JsonBlob';
import { FileUserdataLocalStore } from '../data/sync/UserdataLocalStore';
import { TimetableRepository } from '../data/timetable/TimetableRepository';
import { DeskFormStore } from './DeskFormStore';
import { applyDeskData } from './DeskProjection';

/** Refresh the desktop when the UIAbility is closed. This path never pushes user edits. */
export class DeskRemote {
  private static pending?: Promise<boolean>;

  static refresh(ctx: common.Context): Promise<boolean> {
    if (DeskRemote.pending) return DeskRemote.pending;
    DeskRemote.pending = DeskRemote.once(ctx).finally(() => { DeskRemote.pending = undefined; });
    return DeskRemote.pending;
  }

  private static async once(ctx: common.Context): Promise<boolean> {
    const dir = ctx.filesDir;
    const feed = DeskFormStore.feed(dir);
    if (!feed.sid || Date.now() - feed.refreshedAt < 10 * 60000) return false;
    const session = await new SessionStore(ctx).load();
    if (!session?.token || session.sid !== feed.sid || (session.expiresAt > 0 && session.expiresAt <= Date.now())) return false;
    const sid = session.sid;
    const stillCurrent = (): boolean => {
      const base = DeskFormStore.primary(dir);
      return base.sid === sid && base.revision === feed.revision;
    };
    const localSettings = new FileUserdataLocalStore(() => sid, dir + '/userdata');
    const sections = await localSettings.readCurrent();
    if (!stillCurrent()) return false;
    const api = new HttpClient();
    api.setTokenProvider(() => session.token);
    const tt = new TimetableRepository(api, () => JsonBlob.asBlob(sections['tt'])).load(true);
    const hw = new HomeworkRepository(api).load(true);
    const nt = new NoticesRepository(api, () => Date.now(), 0, () => sid, () => session.isAdmin, false).load(true);
    const marks = BackgroundReads.marks(api, sid, dir);
    const tasks = BackgroundReads.tasks(api, sid, dir);
    const courses = await tt;
    const homework = await hw;
    const notices = await nt;
    const flags = await marks;
    const personal = await tasks;
    if (!stillCurrent() || (session.expiresAt > 0 && session.expiresAt <= Date.now())) return false;
    applyDeskData(feed, HidePrefs.read(sections), courses, homework, notices, flags, personal);
    feed.refreshedAt = Date.now();
    DeskFormStore.saveRemote(dir, feed);
    return true;
  }
}
