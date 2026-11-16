import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { NoticeFilter, NoticeGroup, NoticeItemMeta, NoticeRow, NoticeSigRow } from './NoticeModels';
import { NoticeBodyParser } from './NoticeParser';

const SIG_PATH: string = 'notices?select=id,ts,hidden,edited_at&archived=eq.false&order=ts.desc';
const FULL_PATH: string = 'notices?select=*&archived=eq.false&order=ts.desc';
const DEFAULT_TTL_MS: number = 10 * 60 * 1000;

/** 一条通知（行 + 解析后的组 + 条目元信息）。 */
export class NoticeEntry {
  row: NoticeRow = new NoticeRow();
  group: NoticeGroup | undefined = undefined;
  items: NoticeItemMeta[] = [];
  attachmentCount: number = 0;

  id(): string {
    return this.row.id;
  }

  title(): string {
    if (this.group !== undefined && this.group.title.trim().length > 0) {
      return this.group.title.trim();
    }
    return this.row.title.trim();
  }

  summary(): string {
    if (this.group !== undefined) {
      const ai: string = this.group.aiSummary.trim();
      if (ai.length > 0) {
        return ai;
      }
      if (this.group.summary.trim().length > 0) {
        return this.group.summary.trim();
      }
    }
    const body: string = this.row.body;
    if (NoticeBodyParser.isAuto(body)) {
      return '';
    }
    return body.replace(new RegExp('\\s+', 'g'), ' ').trim();
  }

  /** 截止时间展示：ISO YYYY-MM-DDTHH:mm... → MM-dd HH:mm；其它原样。 */
  deadlineText(): string {
    if (this.group === undefined) {
      return '';
    }
    const raw: string = this.group.deadline.trim();
    if (raw.length === 0) {
      return '';
    }
    const match: RegExpMatchArray | null = raw.match(new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})'));
    if (match !== null) {
      return match[2] + '-' + match[3] + ' ' + match[4] + ':' + match[5];
    }
    return raw;
  }

  timeLabel(): string {
    if (this.group !== undefined && this.group.timeLabel.trim().length > 0) {
      return this.group.timeLabel.trim();
    }
    if (this.row.ts > 0) {
      const d: Date = new Date(this.row.ts);
      return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
    }
    return '';
  }
}

export class NoticesResult {
  ok: boolean;
  entries: NoticeEntry[];
  fromCache: boolean;
  message: string;

  constructor(ok: boolean, entries: NoticeEntry[], fromCache: boolean, message: string) {
    this.ok = ok;
    this.entries = entries;
    this.fromCache = fromCache;
    this.message = message;
  }
}

/**
 * 通知仓库（契约 `docs/api/NOTICES.md`）：
 *
 * 1. 先拉轻量签名 `notices?select=id,ts,hidden,edited_at`（约 2KB）；
 * 2. 签名未变且非强制 → 直接用缓存；否则拉整表 `notices?select=*`；
 * 3. 过滤 `hidden`；自动通知解析 `[[CLASS_NOTICE_V1]]` + 管理端 override；
 * 4. 排序：置顶 > 重要 > 时间倒序。
 */
export class NoticesRepository {
  private api: Api;
  private clock: () => number;
  private ttlMs: number;

  private signature: string = '';
  private cache: NoticeEntry[] = [];
  private cachedAt: number = 0;
  private loaded: boolean = false;

  constructor(api: Api, clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS) {
    this.api = api;
    this.clock = clock;
    this.ttlMs = ttlMs;
  }

  /** 最近一次签名（未加载过为空串），用于工作台「新通知」角标。 */
  currentSignature(): string {
    return this.signature;
  }

  async load(force: boolean): Promise<NoticesResult> {
    const now: number = this.clock();
    if (!force && this.loaded && now - this.cachedAt < this.ttlMs) {
      return new NoticesResult(true, this.cache, true, '');
    }
    const sigResult: ApiResult = await this.api.get(SIG_PATH, true);
    if (!sigResult.ok) {
      if (this.loaded) {
        return new NoticesResult(true, this.cache, true,
          sigResult.error !== undefined ? sigResult.error.displayMessage() : '通知签名加载失败');
      }
      return new NoticesResult(false, [], false,
        sigResult.error !== undefined ? sigResult.error.displayMessage() : '通知签名加载失败');
    }
    const sigRows: NoticeSigRow[] = NoticeBodyParser.parseSigRows(sigResult.value);
    const signature: string = NoticeSigRow.signatureOf(sigRows);
    if (!force && this.loaded && signature === this.signature) {
      this.cachedAt = now;
      return new NoticesResult(true, this.cache, true, '');
    }
    const fullResult: ApiResult = await this.api.get(FULL_PATH, true);
    if (!fullResult.ok) {
      if (this.loaded) {
        return new NoticesResult(true, this.cache, true,
          fullResult.error !== undefined ? fullResult.error.displayMessage() : '通知加载失败');
      }
      return new NoticesResult(false, [], false,
        fullResult.error !== undefined ? fullResult.error.displayMessage() : '通知加载失败');
    }
    const rows: NoticeRow[] = NoticeBodyParser.parseRows(fullResult.value);
    const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
    this.cache = entries;
    this.signature = signature;
    this.cachedAt = now;
    this.loaded = true;
    return new NoticesResult(true, entries, false, '');
  }

  local(): NoticeEntry[] {
    return this.cache;
  }

  static buildEntries(rows: NoticeRow[]): NoticeEntry[] {
    const built: NoticeEntry[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: NoticeRow = rows[i];
      if (row.hidden) {
        continue;
      }
      const entry: NoticeEntry = new NoticeEntry();
      entry.row = row;
      const group: NoticeGroup | undefined = NoticeBodyParser.parseGroup(row.body);
      if (group !== undefined) {
        entry.group = NoticeBodyParser.applyOverride(group, row.overrideJson);
        entry.items = NoticeBodyParser.parseItems(entry.group.items);
      }
      entry.attachmentCount = NoticeBodyParser.attachmentCount(row.attachments);
      built.push(entry);
    }
    // 去重：同一标题 + 同一摘要视为同一条通知（采集端重复入库），保留最新 ts
    const deduped = NoticesRepository.dedupe(built);
    deduped.sort((a: NoticeEntry, b: NoticeEntry) => {
      if (a.row.pin !== b.row.pin) {
        return a.row.pin ? -1 : 1;
      }
      if (a.row.imp !== b.row.imp) {
        return a.row.imp ? -1 : 1;
      }
      return b.row.ts - a.row.ts;
    });
    return deduped;
  }

  /** 标题 + 摘要（去空白）作为去重键；同键保留 ts 最大者。 */
  static dedupe(entries: NoticeEntry[]): NoticeEntry[] {
    const order: string[] = [];
    const best: Map<string, NoticeEntry> = new Map<string, NoticeEntry>();
    for (let i = 0; i < entries.length; i++) {
      const entry: NoticeEntry = entries[i];
      const key: string = entry.title().replace(new RegExp('\\s+', 'g'), '')
        + '|' + entry.summary().replace(new RegExp('\\s+', 'g'), '').substring(0, 160);
      const existing: NoticeEntry | undefined = best.get(key);
      if (existing === undefined) {
        best.set(key, entry);
        order.push(key);
      } else if (entry.row.ts >= existing.row.ts) {
        best.set(key, entry);
      }
    }
    const out: NoticeEntry[] = [];
    for (let i = 0; i < order.length; i++) {
      const entry: NoticeEntry | undefined = best.get(order[i]);
      if (entry !== undefined) {
        out.push(entry);
      }
    }
    return out;
  }

  /** 已处理判定键（普通通知 = row.id；长期期次卡本轮未实现）。 */
  static doneKey(entry: NoticeEntry): string {
    return entry.row.id;
  }

  /** 按筛选过滤（未处理/全部/已处理）。 */
  static filterEntries(entries: NoticeEntry[], filter: NoticeFilter, doneIds: string[]): NoticeEntry[] {
    if (filter === NoticeFilter.ALL) {
      return entries;
    }
    const out: NoticeEntry[] = [];
    for (let i = 0; i < entries.length; i++) {
      const done: boolean = doneIds.indexOf(NoticesRepository.doneKey(entries[i])) >= 0;
      if ((filter === NoticeFilter.DONE && done) || (filter === NoticeFilter.UNREAD && !done)) {
        out.push(entries[i]);
      }
    }
    return out;
  }
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
