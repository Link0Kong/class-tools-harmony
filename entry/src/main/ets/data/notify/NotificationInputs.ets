import { common } from '@kit.AbilityKit';
import { Session } from '../session/Session';
import { FileUserdataLocalStore } from '../sync/UserdataLocalStore';
import { HttpClient } from '../net/HttpClient';
import { NotifyInput } from '../../features/notify/NotifyModels';
import { NotifySettings } from '../../features/notify/NotifySettings';
import { BackgroundReads } from '../sync/BackgroundReads';
import { HomeworkRepository } from '../homework/HomeworkRepository';
import { HomeworkRow } from '../homework/HomeworkModels';
import { NoticeEntry, NoticesRepository } from '../notices/NoticesRepository';
import { HidePrefs } from '../home/HidePrefs';
import { VoteRepository } from '../vote/VoteRepository';
import { TimetableRepository } from '../timetable/TimetableRepository';
import { TtCalendar } from '../timetable/TtCalendar';
import { JsonBlob } from '../sync/JsonBlob';
import { PersonalTask } from '../tasks/TaskModels';
import { WaterCodec } from '../../features/water/WaterCodec';
import { PowerPrefs } from '../power/PowerPrefs';

/** A worker has its own process. Read only the enabled feeds under the restored identity. */
export class NotificationInputs {
  input: NotifyInput = new NotifyInput();
  tasks: PersonalTask[] | undefined = undefined;

  static async read(ctx: common.Context, session: Session, settings: NotifySettings): Promise<NotificationInputs> {
    const result = new NotificationInputs();
    const input = result.input;
    input.unavailable = ['hw', 'ntd', 'nts', 'vres', 'cls'];
    const sid = session.sid;
    const dir = ctx.filesDir;
    const api = new HttpClient();
    api.setTokenProvider(() => session.token);
    const local = new FileUserdataLocalStore(() => sid, dir + '/userdata');
    let sections = await local.readCurrent();
    if (!Object.keys(sections).length) sections = await local.readCache() ?? sections;
    const hidden = HidePrefs.read(sections);
    const hw = settings.homeworkNew || settings.homeworkDue;
    const nt = settings.noticeNew || settings.noticeDeadline || settings.noticeSignup;
    const flagsRequest = hw || nt ? BackgroundReads.marks(api, sid, dir) : undefined;
    const hwRequest = hw ? new HomeworkRepository(api).load(true) : undefined;
    const ntRequest = nt ? new NoticesRepository(api, () => Date.now(), 0, () => sid, () => session.isAdmin, false).load(true) : undefined;
    const pollRequest = settings.voteNew || settings.voteResult ? new VoteRepository(api).list() : undefined;
    const classRequest = settings.classRemind ? new TimetableRepository(api, () => JsonBlob.asBlob(sections['tt'])).load(true) : undefined;
    result.tasks = await BackgroundReads.tasks(api, sid, dir);
    const flags = await flagsRequest;
    const homework = await hwRequest;
    const notices = await ntRequest;
    const polls = await pollRequest;
    const timetable = await classRequest;
    input.now = Date.now();
    if (homework?.ok && flags?.ok && result.tasks !== undefined) {
      const imported = new Set<string>(result.tasks.map((task: PersonalTask) => task.sourceHwId));
      input.homework = homework.rows.filter((row: HomeworkRow) => !row.archived && !imported.has(row.id)
        && !flags.snapshot.hwDone.has(row.id) && !hidden.hwHide.has(row.id));
      input.unavailable = input.unavailable.filter((key: string) => key !== 'hw');
    }
    if (notices?.ok && flags?.ok) {
      input.notices = notices.entries.filter((item: NoticeEntry) => !item.row.hidden && !item.row.archived
        && !flags.snapshot.ntDone.has(item.id()) && !hidden.ntHide.has(item.id()));
      input.unavailable = input.unavailable.filter((key: string) => key !== 'ntd' && key !== 'nts');
    }
    if (polls?.ok) {
      input.polls = polls.list.polls;
      input.unavailable = input.unavailable.filter((key: string) => key !== 'vres');
    }
    if (timetable?.ok && timetable.snapshot) {
      input.classes = TtCalendar.upcomingBells(timetable.snapshot, input.now, 7);
      input.unavailable = input.unavailable.filter((key: string) => key !== 'cls');
    }
    if (settings.waterDeduct) {
      const water = WaterCodec.fromJson(sections['water']);
      const selected = PowerPrefs.read(sections).sel.trim();
      const key = water.room(selected) ? selected : Array.from(water.rooms.keys())[0];
      if (key) {
        input.waterRoomKey = key;
        input.waterRoom = water.room(key);
      }
    }
    return result;
  }
}
