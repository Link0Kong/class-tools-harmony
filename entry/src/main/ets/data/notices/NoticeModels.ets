import { Blob } from '../sync/JsonBlob';

/** 自动通知 body 前缀（契约：`body = "[[CLASS_NOTICE_V1]]" + JSON`）。 */
export const NOTICE_BODY_PREFIX: string = '[[CLASS_NOTICE_V1]]';

/** 通知行（`public.notices`）；管理员覆盖 4 列只读。 */
export class NoticeRow {
  id: string = '';
  title: string = '';
  body: string = '';
  pin: boolean = false;
  imp: boolean = false;
  author: string = '';
  owner: string = '';
  attachments: string = '';
  archived: boolean = false;
  ts: number = 0;
  audience: string = 'all';
  overrideJson: string = '';
  hidden: boolean = false;
  editedAt: number = 0;
  editedBy: string = '';
}

/** 轻量签名行：`GET notices?select=id,ts,hidden,edited_at`（约 2KB，先比签名再拉整表）。 */
export class NoticeSigRow {
  id: string = '';
  ts: number = 0;
  hidden: boolean = false;
  editedAt: number = 0;

  static signatureOf(rows: NoticeSigRow[]): string {
    let out: string = '';
    for (let i = 0; i < rows.length; i++) {
      out += rows[i].id + '|' + rows[i].ts + '|' + (rows[i].hidden ? '1' : '0') + '|' + rows[i].editedAt + ';';
    }
    return out;
  }
}

export class NoticeSegment {
  type: string = '';
  text: string = '';
}

/** 一次延期（extensions[] 的最后一项才是真实截止）。 */
export class NoticeExtension {
  deadline: string = '';
  at: string = '';
  reason: string = '';
}

/** 取通知 body 前缀后的 JSON；字段全部可选，容错）。 */
/** 长期安排 recurrence（req + 	ime 有效才算）。 */
export class NoticeRecurrence {
  freq: string = '';
  weekday: number = -1;
  weeks: number[] = [];
  day: number = 0;
  time: string = '';
  startAt: string = '';
  label: string = '';
  until: string = '';
}

/** 一次期次（长期安排的下一场）。 */
export class NoticeOccurrence {
  groupId: string = '';
  title: string = '';
  nextMillis: number = 0;
  windowStartMillis: number = 0;
  key: string = '';
  label: string = '';
}

export class NoticeGroup {
  id: string = '';
  title: string = '';
  cat: string = '';
  source: string = '';
  groupName: string = '';
  senderName: string = '';
  senderRole: string = '';
  senderBadge: string = '';
  ocr: boolean = false;
  summary: string = '';
  aiSummary: string = '';
  aiPoints: string[] = [];
  aiSegments: NoticeSegment[] = [];
  deadline: string = '';
  deadlineAction: string = '';
  signupStart: string = '';
  signupEnd: string = '';
  timeLabel: string = '';
  eventAt: string = '';
  eventAction: string = '';
  expireAt: string = '';
  publishedAt: string = '';
  publishAction: string = '';
  actionable: boolean = true;
  alert: boolean = false;
  expired: boolean = false;
  updatedAt: string = '';
  items: Blob[] = [];
  extensions: NoticeExtension[] = [];
  /** 报名窗口（旧数据可能只有 signupStart/signupEnd）。 */
  signupWindows: Blob[] = [];
  recurrence: NoticeRecurrence | undefined = undefined;
}

/** 条目渲染元信息（不保留 base64）。 */
export class NoticeItemMeta {
  kind: string = 'text';
  label: string = '';
  text: string = '';
  fromName: string = '';
  fromRole: string = '';
  timeText: string = '';
  /** img：说明；file：文件名；form/link：标题。 */
  name: string = '';
  sizeText: string = '';
  statusText: string = '';
  url: string = '';
  isFollow: boolean = false;
  /** 压缩包识别结果 / 链接域名 / 公众号名称 / 收集表截止原文。 */
  closeText: string = '';
  account: string = '';
  host: string = '';
  note: string = '';
  extText: string = '';
  extKind: string = '';
  hasUrl: boolean = false;
  /** 轻量 meta：该条目的图片/附件内容被服务端置空，展开时需按 row id 拉完整 body。 */
  lazy: boolean = false;
  archiveOk: boolean = false;
  archiveCount: number = 0;
  archiveSummary: string = '';
  archiveFiles: NoticeArchiveFile[] = [];
  messages: NoticeMsgMeta[] = [];
  count: number = 0;
}

/** 压缩包内单个文件（仅元数据，不含 data URI）。 */
export class NoticeArchiveFile {
  name: string = '';
  sizeText: string = '';
  extText: string = '';
  hasUrl: boolean = false;
}

/** 合并聊天记录中的一条消息。 */
export class NoticeMsgMeta {
  fromName: string = '';
  fromBadge: string = '';
  timeText: string = '';
  text: string = '';
}

/** 通知筛选。 */
export enum NoticeFilter {
  UNREAD = '未处理',
  ALL = '全部',
  DONE = '已处理'
}
