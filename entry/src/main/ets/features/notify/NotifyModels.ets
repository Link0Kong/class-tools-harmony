import { HomeworkRow } from '../../data/homework/HomeworkModels';
import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { PollSummary } from '../../data/vote/VoteModels';
import { WaterRoomState } from '../water/WaterModels';
import { SessionInfo } from '../../data/timetable/TimetableModels';

/** 本机通知快照（用于识别“新作业/新通知/新投票/新水费”）。 */
export class NotifySnapshot {
  initialized: boolean = false;
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
  key: string = '';
  title: string = '';
  text: string = '';
  fireAt: number = 0;
  kind: string = '';
}

export class NotifyInput {
  now: number = 0;
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
