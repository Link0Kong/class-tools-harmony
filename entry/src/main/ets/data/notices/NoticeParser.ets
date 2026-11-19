import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import {
  NOTICE_BODY_PREFIX,
  NoticeArchiveFile,
  NoticeExtension,
  NoticeGroup,
  NoticeMsgMeta,
  NoticeRecurrence,
  NoticeItemMeta,
  NoticeRow,
  NoticeSegment,
  NoticeSigRow
} from './NoticeModels';

/** 文件扩展名 → 徽标文案（PDF/XLS/DOC/PPT/图片/压缩包/其它）。 */
export class NoticeExtInfo {
  kind: string = '';
  text: string = '';
}

/** 自动通知 body 解析（坏 JSON 返回 undefined，不崩整页）。 */
export class NoticeBodyParser {
  static isAuto(body: string): boolean {
    return body.trimStart().indexOf(NOTICE_BODY_PREFIX) === 0;
  }

  /** 解析前缀后的 group JSON；非自动/坏 JSON → undefined。 */
  static parseGroup(body: string): NoticeGroup | undefined {
    if (!NoticeBodyParser.isAuto(body)) {
      return undefined;
    }
    const raw: string = body.trimStart().substring(NOTICE_BODY_PREFIX.length).trim();
    if (raw.length === 0) {
      return undefined;
    }
    const obj: Blob | undefined = JsonBlob.parse(raw);
    if (obj === undefined) {
      return undefined;
    }
    const group: NoticeGroup = new NoticeGroup();
    group.id = JsonBlob.asString(JsonBlob.get(obj, 'id'), '');
    group.title = JsonBlob.asString(JsonBlob.get(obj, 'title'), '');
    group.cat = JsonBlob.asString(JsonBlob.get(obj, 'cat'), '');
    group.source = JsonBlob.asString(JsonBlob.get(obj, 'source'), '');
    group.groupName = JsonBlob.asString(JsonBlob.get(obj, 'group'), '');
    group.senderName = JsonBlob.asString(JsonBlob.get(obj, 'senderName'), '');
    group.senderRole = JsonBlob.asString(JsonBlob.get(obj, 'senderRole'), '');
    group.senderBadge = JsonBlob.asString(JsonBlob.get(obj, 'senderBadge'), '');
    group.ocr = JsonBlob.asBoolean(JsonBlob.get(obj, 'ocr'), false);
    group.summary = JsonBlob.asString(JsonBlob.get(obj, 'summary'), '');
    group.aiSummary = JsonBlob.asString(JsonBlob.get(obj, 'aiSummary'), '');
    group.deadline = JsonBlob.asString(JsonBlob.get(obj, 'deadline'), '');
    group.deadlineAction = JsonBlob.asString(JsonBlob.get(obj, 'deadlineAction'), '');
    group.signupStart = JsonBlob.asString(JsonBlob.get(obj, 'signupStart'), '');
    group.signupEnd = JsonBlob.asString(JsonBlob.get(obj, 'signupEnd'), '');
    group.timeLabel = JsonBlob.asString(JsonBlob.get(obj, 'timeLabel'), '');
    group.eventAt = JsonBlob.asString(JsonBlob.get(obj, 'eventAt'), '');
    group.eventAction = JsonBlob.asString(JsonBlob.get(obj, 'eventAction'), '');
    group.expireAt = JsonBlob.asString(JsonBlob.get(obj, 'expireAt'), '');
    group.publishedAt = JsonBlob.asString(JsonBlob.get(obj, 'publishedAt'), '');
    group.publishAction = JsonBlob.asString(JsonBlob.get(obj, 'publishAction'), '');
    group.updatedAt = JsonBlob.asString(JsonBlob.get(obj, 'updatedAt'), '');
    group.actionable = JsonBlob.asBoolean(JsonBlob.get(obj, 'actionable'), true);
    group.alert = JsonBlob.asBoolean(JsonBlob.get(obj, 'alert'), false);
    group.expired = JsonBlob.asBoolean(JsonBlob.get(obj, 'expired'), false);
    const extensions: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'extensions'));
    if (extensions !== undefined) {
      for (let i = 0; i < extensions.length; i++) {
        const extBlob: Blob | undefined = JsonBlob.asBlob(extensions[i]);
        if (extBlob === undefined) {
          continue;
        }
        const ext: NoticeExtension = new NoticeExtension();
        ext.deadline = JsonBlob.asString(JsonBlob.get(extBlob, 'deadline'), '');
        ext.at = JsonBlob.asString(JsonBlob.get(extBlob, 'at'), '');
        ext.reason = JsonBlob.asString(JsonBlob.get(extBlob, 'reason'), '');
        group.extensions.push(ext);
      }
    }
    const signupWindows: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'signupWindows'));
    if (signupWindows !== undefined) {
      for (let i = 0; i < signupWindows.length; i++) {
        const win: Blob | undefined = JsonBlob.asBlob(signupWindows[i]);
        if (win !== undefined) {
          group.signupWindows.push(win);
        }
      }
    }
    group.aiPoints = stringArray(JsonBlob.get(obj, 'aiPoints'));
    const recurrence: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(obj, 'recurrence'));
    if (recurrence !== undefined) {
      const recur: NoticeRecurrence = new NoticeRecurrence();
      recur.freq = JsonBlob.asString(JsonBlob.get(recurrence, 'freq'), '');
      recur.weekday = Math.round(JsonBlob.asNumber(JsonBlob.get(recurrence, 'weekday'), -1));
      recur.weeks = numberArray(JsonBlob.get(recurrence, 'weeks'));
      recur.day = Math.round(JsonBlob.asNumber(JsonBlob.get(recurrence, 'day'), 0));
      recur.time = JsonBlob.asString(JsonBlob.get(recurrence, 'time'), '');
      recur.startAt = JsonBlob.asString(JsonBlob.get(recurrence, 'startAt'), '');
      recur.label = JsonBlob.asString(JsonBlob.get(recurrence, 'label'), '');
      recur.until = JsonBlob.asString(JsonBlob.get(recurrence, 'until'), '');
      group.recurrence = recur;
    }
    const segments: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'aiSegments'));
    if (segments !== undefined) {
      for (let i = 0; i < segments.length; i++) {
        const seg: Blob | undefined = JsonBlob.asBlob(segments[i]);
        if (seg === undefined) {
          continue;
        }
        const item: NoticeSegment = new NoticeSegment();
        item.type = JsonBlob.asString(JsonBlob.get(seg, 'type'), '');
        item.text = JsonBlob.asString(JsonBlob.get(seg, 'text'), '');
        if (item.text.trim().length > 0) {
          group.aiSegments.push(item);
        }
      }
    }
    const items: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'items'));
    if (items !== undefined) {
      for (let i = 0; i < items.length; i++) {
        const blob: Blob | undefined = JsonBlob.asBlob(items[i]);
        if (blob !== undefined) {
          group.items.push(blob);
        }
      }
    }
    return group;
  }

  /** `items[]` → 渲染元信息（只保留展示文本/名称/体积，不保留 base64）。 */
  static parseItems(items: Blob[]): NoticeItemMeta[] {
    const out: NoticeItemMeta[] = [];
    let textPos: number = 0;
    for (let i = 0; i < items.length; i++) {
      const item: Blob = items[i];
      const kind: string = JsonBlob.asString(JsonBlob.get(item, 'kind'), '').trim();
      const meta: NoticeItemMeta = new NoticeItemMeta();
      meta.kind = kind.length > 0 ? kind : 'text';
      meta.lazy = JsonBlob.asBoolean(JsonBlob.get(item, 'lazy'), false);
      meta.timeText = JsonBlob.asString(JsonBlob.get(item, 'time'), '').trim();
      if (meta.kind === 'text' || meta.kind === 'follow') {
        const isFollow: boolean = meta.kind === 'follow';
        const label: string = JsonBlob.asString(JsonBlob.get(item, 'label'), '').trim();
        meta.label = label.length > 0 ? label
          : (isFollow ? '补充通知' : (textPos === 0 ? '原始消息' : '补充通知'));
        meta.isFollow = isFollow;
        meta.fromName = JsonBlob.asString(JsonBlob.get(item, 'fromName'), '').trim().length > 0
          ? JsonBlob.asString(JsonBlob.get(item, 'fromName'), '')
          : JsonBlob.asString(JsonBlob.get(item, 'from'), '');
        meta.fromRole = JsonBlob.asString(JsonBlob.get(item, 'fromRole'), '').trim().length > 0
          ? JsonBlob.asString(JsonBlob.get(item, 'fromRole'), '')
          : JsonBlob.asString(JsonBlob.get(item, 'fromBadge'), '');
        meta.text = JsonBlob.asString(JsonBlob.get(item, 'text'), '').trim();
        textPos += 1;
      } else if (meta.kind === 'img') {
        meta.name = JsonBlob.asString(JsonBlob.get(item, 'caption'), '');
        const src: string = NoticeBodyParser.firstText(item, ['src', 'url', 'realUrl']);
        meta.url = src;
        meta.hasUrl = src.length > 0;
        const bytes: number = estimateDataUriBytes(src);
        meta.sizeText = bytes > 0 ? formatSize(bytes) : '';
        meta.text = '图片' + (meta.name.length > 0 ? ' · ' + meta.name : '');
      } else if (meta.kind === 'file') {
        const name: string = JsonBlob.asString(JsonBlob.get(item, 'name'), '').trim();
        const fallback: string = JsonBlob.asString(JsonBlob.get(item, 'text'), '').trim();
        meta.name = name.length > 0 ? name : (fallback.length > 0 ? fallback : '附件');
        const explicitSize: string = JsonBlob.asString(JsonBlob.get(item, 'size'), '').trim();
        const raw: string = NoticeBodyParser.firstText(item, ['realUrl', 'url', 'src']);
        meta.url = raw;
        meta.hasUrl = raw.length > 0;
        const bytes: number = estimateDataUriBytes(raw);
        meta.sizeText = explicitSize.length > 0 ? explicitSize : (bytes > 0 ? formatSize(bytes) : '');
        const ext: NoticeExtInfo = NoticeBodyParser.extOf(meta.name);
        meta.extKind = ext.kind;
        meta.extText = ext.text;
        meta.note = JsonBlob.asString(JsonBlob.get(item, 'note'), '').trim();
        meta.text = '文件';
        const archive: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(item, 'archive'));
        if (archive !== undefined) {
          const files: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(archive, 'files'));
          const status: string = JsonBlob.asString(JsonBlob.get(archive, 'status'), '').trim();
          const archiveOk: boolean = (JsonBlob.asBoolean(JsonBlob.get(item, 'archiveOk'), false) || status === 'ok')
            && files !== undefined && files.length > 0;
          meta.archiveOk = archiveOk;
          if (files !== undefined) {
            meta.archiveCount = Math.round(JsonBlob.asNumber(JsonBlob.get(archive, 'count'), files.length));
            if (archiveOk) {
              for (let f = 0; f < files.length && f < 6; f++) {
                const fileBlob: Blob | undefined = JsonBlob.asBlob(files[f]);
                if (fileBlob === undefined) {
                  continue;
                }
                const af: NoticeArchiveFile = new NoticeArchiveFile();
                af.name = JsonBlob.asString(JsonBlob.get(fileBlob, 'name'), '').trim().length > 0
                  ? JsonBlob.asString(JsonBlob.get(fileBlob, 'name'), '')
                  : JsonBlob.asString(JsonBlob.get(fileBlob, 'path'), '');
                if (af.name.length === 0) {
                  af.name = '文件';
                }
                af.sizeText = JsonBlob.asString(JsonBlob.get(fileBlob, 'size'), '');
                af.extText = NoticeBodyParser.extOf(af.name).text;
                af.hasUrl = NoticeBodyParser.firstText(fileBlob, ['url', 'src']).length > 0;
                meta.archiveFiles.push(af);
              }
            }
            meta.archiveSummary = JsonBlob.asString(JsonBlob.get(archive, 'summary'), '')
              .replace(new RegExp('\\s+', 'g'), ' ').trim().substring(0, 120);
          }
        }
      } else if (meta.kind === 'form') {
        const realTitle: string = JsonBlob.asString(JsonBlob.get(item, 'realTitle'), '').trim();
        const name: string = JsonBlob.asString(JsonBlob.get(item, 'name'), '').trim();
        meta.name = realTitle.length > 0 ? realTitle : (name.length > 0 ? name : '收集表');
        const close: string = JsonBlob.asString(JsonBlob.get(item, 'close'), '').trim();
        meta.closeText = close;
        meta.statusText = close.length > 0 ? close + ' 截止' : '进行中';
        meta.note = JsonBlob.asString(JsonBlob.get(item, 'note'), '').trim();
        meta.url = NoticeBodyParser.firstText(item, ['realUrl', 'url']);
        meta.hasUrl = meta.url.length > 0;
        meta.text = '收集表';
      } else if (meta.kind === 'link' || meta.kind === 'mini' || meta.kind === 'article') {
        const name: string = JsonBlob.asString(JsonBlob.get(item, 'name'), '').trim();
        const title: string = JsonBlob.asString(JsonBlob.get(item, 'title'), '').trim();
        const fallbackName: string = meta.kind === 'article' ? '公众号文章'
          : (meta.kind === 'mini' ? '小程序' : '链接');
        meta.name = name.length > 0 ? name : (title.length > 0 ? title : fallbackName);
        meta.url = NoticeBodyParser.firstText(item, ['realUrl', 'url']);
        meta.hasUrl = meta.url.length > 0;
        meta.account = JsonBlob.asString(JsonBlob.get(item, 'account'), '').trim();
        meta.note = JsonBlob.asString(JsonBlob.get(item, 'note'), '').trim();
        meta.host = hostOf(meta.url);
        meta.text = '链接';
      } else if (meta.kind === 'merged') {
        const messages: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(item, 'messages'));
        const title: string = JsonBlob.asString(JsonBlob.get(item, 'title'), '').trim();
        meta.name = title.length > 0 ? title : '聊天记录';
        if (messages !== undefined) {
          meta.count = Math.round(JsonBlob.asNumber(JsonBlob.get(item, 'count'), messages.length));
          for (let m = 0; m < messages.length && m < 8; m++) {
            const msgBlob: Blob | undefined = JsonBlob.asBlob(messages[m]);
            if (msgBlob === undefined) {
              continue;
            }
            const msg: NoticeMsgMeta = new NoticeMsgMeta();
            msg.fromName = NoticeBodyParser.firstText(msgBlob, ['fromName', 'from']).trim();
            msg.fromBadge = NoticeBodyParser.firstText(msgBlob, ['fromRole', 'fromBadge']).trim();
            msg.timeText = JsonBlob.asString(JsonBlob.get(msgBlob, 'time'), '').trim();
            msg.text = JsonBlob.asString(JsonBlob.get(msgBlob, 'text'), '').trim();
            meta.messages.push(msg);
          }
        }
        meta.text = '聊天记录';
      } else {
        meta.text = JsonBlob.asString(JsonBlob.get(item, 'text'), '').trim();
      }
      out.push(meta);
    }
    return out;
  }

  /** 按优先级取第一个非空字符串字段（URL / 文本兜底）。 */
  static firstText(blob: Blob, keys: string[]): string {
    for (let i = 0; i < keys.length; i++) {
      const value: string = JsonBlob.asString(JsonBlob.get(blob, keys[i]), '').trim();
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  /** 文件扩展名 → 徽标文案。 */
  static extOf(name: string): NoticeExtInfo {
    const out: NoticeExtInfo = new NoticeExtInfo();
    const match: RegExpMatchArray | null = name.match(new RegExp('\\.([a-z0-9]+)$', 'i'));
    const ext: string = match !== null ? match[1].toLowerCase() : '';
    out.kind = ext.length > 0 ? ext : 'file';
    if (ext === 'pdf') {
      out.text = 'PDF';
    } else if (ext === 'xls' || ext === 'xlsx' || ext === 'csv') {
      out.text = 'XLS';
    } else if (ext === 'doc' || ext === 'docx') {
      out.text = 'DOC';
    } else if (ext === 'ppt' || ext === 'pptx') {
      out.text = 'PPT';
    } else if (ext === 'zip' || ext === 'rar' || ext === '7z') {
      out.text = 'ZIP';
    } else if (ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'gif' || ext === 'webp') {
      out.text = 'IMG';
    } else if (ext === 'txt' || ext === 'md') {
      out.text = 'TXT';
    } else {
      out.text = '文件';
    }
    return out;
  }

  /** 人工通知附件（`notices.attachments` JSON 字符串）数量。 */
  static attachmentCount(raw: string): number {
    if (raw.trim().length === 0) {
      return 0;
    }
    let parsed: JsonValue | undefined = undefined;
    try {
      parsed = JSON.parse(raw) as JsonValue;
    } catch (e) {
      return 0;
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    return array !== undefined ? array.length : 0;
  }

  /** 管理员覆盖（白名单：title/cat/summary/aiSummary/deadline/eventAt/expireAt/timeLabel）。 */
  static applyOverride(group: NoticeGroup, overrideJson: string): NoticeGroup {
    if (overrideJson.trim().length === 0) {
      return group;
    }
    const override: Blob | undefined = JsonBlob.parse(overrideJson);
    if (override === undefined) {
      return group;
    }
    if (JsonBlob.has(override, 'title')) {
      group.title = JsonBlob.asString(JsonBlob.get(override, 'title'), '');
    }
    if (JsonBlob.has(override, 'cat')) {
      group.cat = JsonBlob.asString(JsonBlob.get(override, 'cat'), '');
    }
    if (JsonBlob.has(override, 'summary')) {
      group.summary = JsonBlob.asString(JsonBlob.get(override, 'summary'), '');
    }
    if (JsonBlob.has(override, 'aiSummary')) {
      group.aiSummary = JsonBlob.asString(JsonBlob.get(override, 'aiSummary'), '');
    }
    if (JsonBlob.has(override, 'deadline')) {
      group.deadline = JsonBlob.asString(JsonBlob.get(override, 'deadline'), '');
    }
    if (JsonBlob.has(override, 'eventAt')) {
      group.eventAt = JsonBlob.asString(JsonBlob.get(override, 'eventAt'), '');
    }
    if (JsonBlob.has(override, 'expireAt')) {
      group.expireAt = JsonBlob.asString(JsonBlob.get(override, 'expireAt'), '');
    }
    if (JsonBlob.has(override, 'timeLabel')) {
      group.timeLabel = JsonBlob.asString(JsonBlob.get(override, 'timeLabel'), '');
    }
    return group;
  }

  /** 解析签名行数组。 */
  static parseSigRows(raw: string): NoticeSigRow[] {
    if (raw.length === 0) {
      return [];
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (e) {
      return [];
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined) {
      return [];
    }
    const out: NoticeSigRow[] = [];
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj === undefined) {
        continue;
      }
      const row: NoticeSigRow = new NoticeSigRow();
      row.id = JsonBlob.asString(JsonBlob.get(obj, 'id'), '');
      row.ts = JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0);
      row.hidden = JsonBlob.asBoolean(JsonBlob.get(obj, 'hidden'), false);
      row.editedAt = JsonBlob.asNumber(JsonBlob.get(obj, 'edited_at'), 0);
      if (row.id.length > 0) {
        out.push(row);
      }
    }
    return out;
  }

  /** 响应是否为 JSON 数组（区分「合法空列表」与「RPC 返回错误对象/非数组」）。 */
  static isRowsPayload(raw: string): boolean {
    if (raw.trim().length === 0) {
      return false;
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (e) {
      return false;
    }
    return JsonBlob.asArray(parsed) !== undefined;
  }

  /** 解析整表行。 */
  static parseRows(raw: string): NoticeRow[] {
    if (raw.length === 0) {
      return [];
    }
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (e) {
      return [];
    }
    const array: Object[] | undefined = JsonBlob.asArray(parsed);
    if (array === undefined) {
      return [];
    }
    const out: NoticeRow[] = [];
    for (let i = 0; i < array.length; i++) {
      const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
      if (obj === undefined) {
        continue;
      }
      const row: NoticeRow = new NoticeRow();
      row.id = JsonBlob.asString(JsonBlob.get(obj, 'id'), '');
      if (row.id.length === 0) {
        continue;
      }
      row.title = JsonBlob.asString(JsonBlob.get(obj, 'title'), '');
      row.body = JsonBlob.asString(JsonBlob.get(obj, 'body'), '');
      row.pin = JsonBlob.asBoolean(JsonBlob.get(obj, 'pin'), false);
      row.imp = JsonBlob.asBoolean(JsonBlob.get(obj, 'imp'), false);
      row.author = JsonBlob.asString(JsonBlob.get(obj, 'author'), '');
      row.owner = JsonBlob.asString(JsonBlob.get(obj, 'owner'), '');
      row.attachments = JsonBlob.asString(JsonBlob.get(obj, 'attachments'), '');
      row.archived = JsonBlob.asBoolean(JsonBlob.get(obj, 'archived'), false);
      row.ts = JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0);
      row.audience = JsonBlob.asString(JsonBlob.get(obj, 'audience'), 'all');
      row.overrideJson = JsonBlob.asString(JsonBlob.get(obj, 'override_json'), '');
      row.hidden = JsonBlob.asBoolean(JsonBlob.get(obj, 'hidden'), false);
      row.editedAt = JsonBlob.asNumber(JsonBlob.get(obj, 'edited_at'), 0);
      row.editedBy = JsonBlob.asString(JsonBlob.get(obj, 'edited_by'), '');
      out.push(row);
    }
    return out;
  }
}

function numberArray(value: JsonValue | undefined): number[] {
  const array: Object[] | undefined = JsonBlob.asArray(value);
  if (array === undefined) {
    return [];
  }
  const out: number[] = [];
  for (let i = 0; i < array.length; i++) {
    const num: number = JsonBlob.asNumber(array[i], 0);
    if (Number.isFinite(num)) {
      out.push(Math.round(num));
    }
  }
  return out;
}

function stringArray(value: JsonValue | undefined): string[] {
  const array: Object[] | undefined = JsonBlob.asArray(value);
  if (array === undefined) {
    return [];
  }
  const out: string[] = [];
  for (let i = 0; i < array.length; i++) {
    const item: string = JsonBlob.asString(array[i], '');
    if (item.trim().length > 0) {
      out.push(item);
    }
  }
  return out;
}

function estimateDataUriBytes(data: string): number {
  if (data.toLowerCase().indexOf('data:') !== 0) {
    return 0;
  }
  const comma: number = data.indexOf(',');
  if (comma < 0) {
    return 0;
  }
  return Math.floor((data.length - comma - 1) * 3 / 4);
}

function hostOf(url: string): string {
  const match: RegExpMatchArray | null = url.match(new RegExp('^https?://([^/]+)', 'i'));
  return match !== null ? match[1] : '';
}

function formatSize(bytes: number): string {
  if (bytes <= 0) {
    return '';
  }
  if (bytes < 1024) {
    return bytes + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}
