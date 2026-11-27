import { HomeworkRow } from '../../data/homework/HomeworkModels';
import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { PollSummary } from '../../data/vote/VoteModels';
import { WaterRoomState } from '../water/WaterModels';
import { SessionInfo } from '../../data/timetable/TimetableModels';

/** 本机通知快照（用于识别“新作业/新通知/新投票/新水费”）。 */
export class NotifySnapshot {
  initialized: boolean = false;
  homeworkReady: boolean = false;
  noticesReady: boolean = false;
  pollsReady: boolean = false;
  hwIds: string[] = [];
  ntIds: string[] = [];
  pollIds: string[] = [];
  closedPollIds: string[] = [];
  waterKey: string = '';

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(raw: string): NotifySnapshot {
    const out: NotifySnapshot = new NotifySnapshot();
    if (raw.trim().length === 0) {
      return out;
    }
    try {
      const obj: NotifySnapshot = JSON.parse(raw) as NotifySnapshot;
      out.initialized = obj.initialized === true;
      out.homeworkReady = obj.homeworkReady === undefined ? out.initialized : obj.homeworkReady === true;
      out.noticesReady = obj.noticesReady === undefined ? out.initialized : obj.noticesReady === true;
      out.pollsReady = obj.pollsReady === undefined ? out.initialized : obj.pollsReady === true;
      out.hwIds = stringArray(obj.hwIds);
      out.ntIds = stringArray(obj.ntIds);
      out.pollIds = stringArray(obj.pollIds);
      out.closedPollIds = stringArray(obj.closedPollIds);
      out.waterKey = typeof obj.waterKey === 'string' ? obj.waterKey : '';
      return out;
    } catch (e) {
      return out;
    }
  }
}

/** 一条待发送通知：fireAt=0 立即发送，>0 由系统提醒定时触发。 */
export class NotifyEvent {
  course?: SessionInfo;
  key: string = '';
  title: string = '';
  text: string = '';
  fireAt: number = 0;
  kind: string = '';

  signature(): string {
    return this.key.split(':')[0] + ':' + JSON.stringify([this.key, String(this.fireAt), this.title, this.text]);
  }
}

export class NotifyInput {
  now: number = 0;
  unavailable: string[] = [];
  manualHomework: string[] = [];
  homework: HomeworkRow[] = [];
  notices: NoticeEntry[] = [];
  classes: SessionInfo[] = [];
  polls: PollSummary[] = [];
  waterRoom: WaterRoomState | undefined = undefined;
  waterRoomKey: string = '';
}

function stringArray(value: string[] | undefined): string[] {
  const out: string[] = [];
  if (value === undefined || !Array.isArray(value)) {
    return out;
  }
  for (let i = 0; i < value.length; i++) {
    if (typeof value[i] === 'string' && value[i].length > 0) {
      out.push(value[i]);
    }
  }
  return out;
}
