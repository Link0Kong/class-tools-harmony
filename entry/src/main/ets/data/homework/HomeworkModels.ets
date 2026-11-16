import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';

/** 作业行（`public.homework`；`done` 列前端忽略，完成状态唯一真源是 marks kind='hw'）。 */
export class HomeworkRow {
  id: string = '';
  subject: string = '';
  content: string = '';
  due: string = '';
  date: string = '';
  time: string = '';
  author: string = '';
  owner: string = '';
  /** 附件 JSON 字符串（`[{n,t,s,d}]`），需二次解析且不把 base64 常驻内存。 */
  attachments: string = '';
  archived: boolean = false;
  ts: number = 0;
}

export enum HomeworkAttachmentKind {
  DATA_URI = 'data',
  URL = 'url',
  NONE = 'none'
}

/** 作业附件元信息（不含 base64 内容）。 */
export class HomeworkAttachmentMeta {
  index: number = 0;
  name: string = '';
  mime: string = '';
  sizeBytes: number = 0;
  kind: HomeworkAttachmentKind = HomeworkAttachmentKind.NONE;

  isImage(): boolean {
    return this.mime.indexOf('image/') === 0;
  }

  sizeText(): string {
    const bytes: number = this.sizeBytes;
    if (bytes <= 0) {
      return '—';
    }
    if (bytes < 1024) {
      return bytes + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
}

export enum HomeworkDueState {
  NONE = 'none',
  HOURS_LEFT = 'hours_left',
  DAYS_LEFT = 'days_left',
  OVERDUE_HOURS = 'overdue_hours',
  OVERDUE_DAYS = 'overdue_days'
}

export enum HomeworkDueTone {
  NEUTRAL = 'neutral',
  SAFE = 'safe',
  WARN = 'warn',
  URGENT = 'urgent',
  OVERDUE = 'overdue'
}

export class HomeworkDue {
  atMillis: number = 0;
  label: string = '';
  state: HomeworkDueState = HomeworkDueState.NONE;
  tone: HomeworkDueTone = HomeworkDueTone.NEUTRAL;
  expired: boolean = false;
  /** 过期超过 3 天：只在内存过滤（不写云、不 DELETE）。 */
  prunable: boolean = false;
}

export class HomeworkItem {
  row: HomeworkRow = new HomeworkRow();
  done: boolean = false;
  due: HomeworkDue | undefined = undefined;
  attachments: HomeworkAttachmentMeta[] = [];

  id(): string {
    return this.row.id;
  }

  /** 标题：subject 优先，否则正文首行。 */
  title(): string {
    if (this.row.subject.trim().length > 0) {
      return this.row.subject.trim();
    }
    const lines: string[] = this.row.content.split('\n');
    return lines.length > 0 ? lines[0].trim() : '';
  }

  /** 正文摘要（去掉首行标题，压成一行）。 */
  bodyPreview(): string {
    const text: string = this.row.content.replace(new RegExp('\\s+', 'g'), ' ').trim();
    const title: string = this.title();
    if (title.length > 0 && text.indexOf(title) === 0) {
      return text.substring(title.length).trim();
    }
    return text;
  }
}

export enum HomeworkFilter {
  ALL = '全部',
  UNFINISHED = '未完成',
  DONE = '已完成'
}

const DAY_MS: number = 24 * 60 * 60 * 1000;
const PRUNE_AFTER_DAYS: number = 3;

/** 作业截止时间计算（纯函数，对齐网页 hwDue/dueInfo/hwExpired/pruneHW）。 */
export class HomeworkDueCalculator {
  /** 解析 `date`（YYYY-MM-DD）(+`time` HH:MM) → epoch ms；无法解析返回 undefined。 */
  static parseDue(date: string, time: string): number | undefined {
    const d: string = date.trim();
    const dateMatch: RegExpMatchArray | null = d.match(new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})$'));
    if (dateMatch === null) {
      return undefined;
    }
    const year: number = Number(dateMatch[1]);
    const month: number = Number(dateMatch[2]);
    const day: number = Number(dateMatch[3]);
    let hour: number = 0;
    let minute: number = 0;
    const t: string = time.trim();
    if (t.length > 0) {
      const timeMatch: RegExpMatchArray | null = t.match(new RegExp('^(\\d{1,2}):(\\d{2})$'));
      if (timeMatch !== null) {
        hour = Number(timeMatch[1]);
        minute = Number(timeMatch[2]);
        if (hour > 23 || minute > 59) {
          hour = 0;
          minute = 0;
        }
      }
    }
    const stamp: number = new Date(year, month - 1, day, hour, minute, 0).getTime();
    return Number.isFinite(stamp) ? stamp : undefined;
  }

  /** 截止信息；无日期返回 undefined。 */
  static evaluate(row: HomeworkRow, nowMillis: number): HomeworkDue | undefined {
    const dueAt: number | undefined = HomeworkDueCalculator.parseDue(row.date, row.time);
    if (dueAt === undefined) {
      return undefined;
    }
    const diff: number = dueAt - nowMillis;
    const due: HomeworkDue = new HomeworkDue();
    due.atMillis = dueAt;
    due.prunable = nowMillis > dueAt + PRUNE_AFTER_DAYS * DAY_MS;
    if (diff < 0) {
      const overdue: number = -diff;
      due.expired = true;
      due.tone = HomeworkDueTone.OVERDUE;
      if (overdue < DAY_MS) {
        const hours: number = Math.max(1, Math.floor(overdue / (60 * 60 * 1000)));
        due.state = HomeworkDueState.OVERDUE_HOURS;
        due.label = '已过期 ' + hours + ' 小时';
      } else {
        const days: number = Math.floor(overdue / DAY_MS);
        due.state = HomeworkDueState.OVERDUE_DAYS;
        due.label = '已过期 ' + days + ' 天';
      }
      return due;
    }
    if (diff < DAY_MS) {
      const hours: number = Math.max(1, Math.floor(diff / (60 * 60 * 1000)));
      due.state = HomeworkDueState.HOURS_LEFT;
      due.label = '还剩 ' + hours + ' 小时';
      due.tone = HomeworkDueTone.URGENT;
      return due;
    }
    const days: number = Math.floor(diff / DAY_MS);
    due.state = HomeworkDueState.DAYS_LEFT;
    due.label = '还剩 ' + days + ' 天';
    due.tone = days <= 3 ? HomeworkDueTone.WARN : HomeworkDueTone.SAFE;
    return due;
  }

  /** `MM-dd HH:mm` 展示。 */
  static dueText(dueAt: number): string {
    if (dueAt <= 0) {
      return '—';
    }
    const d: Date = new Date(dueAt);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }
}

/** 附件解析（JSON 字符串 → 元信息列表；不保留 base64）。 */
export class HomeworkAttachments {
  static parse(raw: string): HomeworkAttachmentMeta[] {
    if (raw.trim().length === 0) {
      return [];
    }
    let parsed: JsonValue | undefined = undefined;
    try {
      parsed = JSON.parse(raw) as JsonValue;
    } catch (e) {
      return [];
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined) {
      return [];
    }
    const out: HomeworkAttachmentMeta[] = [];
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj === undefined) {
        continue;
      }
      const name: string = JsonBlob.asString(JsonBlob.get(obj, 'n'), '').trim();
      const mime: string = JsonBlob.asString(JsonBlob.get(obj, 't'), '');
      const data: string = JsonBlob.asString(JsonBlob.get(obj, 'd'), '');
      const explicitSize: number = JsonBlob.asNumber(JsonBlob.get(obj, 's'), 0);
      const meta: HomeworkAttachmentMeta = new HomeworkAttachmentMeta();
      meta.index = i;
      meta.name = name.length > 0 ? name : '附件 ' + (i + 1);
      meta.mime = mime;
      meta.sizeBytes = explicitSize > 0 ? explicitSize : HomeworkAttachments.estimateDataUriBytes(data);
      if (data.toLowerCase().indexOf('data:') === 0) {
        meta.kind = HomeworkAttachmentKind.DATA_URI;
      } else if (data.toLowerCase().indexOf('http://') === 0 || data.toLowerCase().indexOf('https://') === 0) {
        meta.kind = HomeworkAttachmentKind.URL;
      } else {
        meta.kind = HomeworkAttachmentKind.NONE;
      }
      out.push(meta);
    }
    return out;
  }

  /** 取第 index 个附件的原始 data URI / URL（仅详情预览用）。 */
  static dataOf(raw: string, index: number): string {
    if (raw.trim().length === 0) {
      return '';
    }
    let parsed: JsonValue | undefined = undefined;
    try {
      parsed = JSON.parse(raw) as JsonValue;
    } catch (e) {
      return '';
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined || index < 0 || index >= array.length) {
      return '';
    }
    const obj: Blob | undefined = JsonBlob.asBlob(array[index]);
    return JsonBlob.asString(JsonBlob.get(obj, 'd'), '');
  }

  /** data URI 的近似解码体积（base64 4→3）。 */
  private static estimateDataUriBytes(data: string): number {
    if (data.toLowerCase().indexOf('data:') !== 0) {
      return 0;
    }
    const comma: number = data.indexOf(',');
    if (comma < 0) {
      return 0;
    }
    const base64Length: number = data.length - comma - 1;
    return Math.floor(base64Length * 3 / 4);
  }
}

export function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
