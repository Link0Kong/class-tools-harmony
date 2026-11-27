import { TaskShare } from '../tasks/TaskModels';

export class ScanPayload {
  kind: string = '';
  ticket: string = '';
  harmony: boolean = false;
  recordId: string = '';
  task?: TaskShare;

  static parse(raw: string): ScanPayload {
    const result = new ScanPayload();
    if (raw.length > 8192) return result;
    const text = raw.trim();
    const login = /^https:\/\/tool\.furina\.fun\/#qr=([0-9a-fA-F]{32})(?:&p=(harmony|any|oppo|honor))?$/.exec(text);
    if (login) {
      result.kind = 'login';
      result.ticket = login[1].toLowerCase();
      result.harmony = login[2] === 'harmony';
      return result;
    }
    const draw = /^https:\/\/tool\.furina\.fun\/#verify=(d[0-9a-z]{8,31})$/.exec(text);
    if (draw) { result.kind = 'draw'; result.recordId = draw[1]; return result; }
    /* 统一内容链接（新二维码）：https://tool.furina.fun/l/draw/<recordId>[?query] */
    const link = /^https:\/\/tool\.furina\.fun\/l\/draw\/(d[0-9a-z]{8,31})(?:\?[^#]*)?(?:#.*)?$/i.exec(text);
    if (link) { result.kind = 'draw'; result.recordId = link[1].toLowerCase(); return result; }
    result.task = TaskShare.parse(text);
    if (result.task) result.kind = 'task';
    return result;
  }
}
