import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { NoticeFilter, NoticeGroup, NoticeItemMeta, NoticeRow, NoticeSigRow } from './NoticeModels';
import { NoticeBodyParser } from './NoticeParser';
import { NoticeCacheBlob, NoticeCacheStore } from './NoticeCacheStore';

const META_PATH: string = 'rpc/class_notices_meta';
const SIG_PATH: string = 'notices?select=id,ts,hidden,edited_at&archived=eq.false&order=ts.asc,id.asc';
const FULL_PATH: string = 'notices?select=*&archived=eq.false&order=ts.asc,id.asc';
const DETAIL_PATH: string = 'notices?select=*&id=eq.';
const DEFAULT_TTL_MS: number = 10 * 60 * 1000;
/** 轻量列表（约 0.3MB）给 30s；旧整表（约 12MB）给 55s；单条详情给 30s。 */
const META_TIMEOUT_MS: number = 30000;
const SIG_TIMEOUT_MS: number = 20000;
const FULL_TIMEOUT_MS: number = 55000;
const DETAIL_TIMEOUT_MS: number = 30000;
/** 磁盘缓存最多回放 7 天，避免离线时展示过旧内容。 */
const MAX_DISK_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;

/** 一条通知（行 + 解析后的组 + 条目元信息）。 */
export class NoticeEntry {
  row: NoticeRow = new NoticeRow();
  group: NoticeGroup | undefined = undefined;
  items: NoticeItemMeta[] = [];
  attachmentCount: number = 0;
  /** true = 来自轻量 meta，图片/附件内容尚未拉取。 */
  lazy: boolean = false;

  id(): string {
    return this.row.id;
  }

  /** 是否有条目需要按需拉完整 body。 */
  needsDetail(): boolean {
    if (this.lazy) {
      return true;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].lazy) {
        return true;
      }
    }
    return false;
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

/** 单条通知完整 body 的按需加载结果。 */
export class NoticeDetailResult {
  ok: boolean;
  entry: NoticeEntry | undefined = undefined;
  message: string = '';

  constructor(ok: boolean, entry: NoticeEntry | undefined, message: string) {
    this.ok = ok;
    this.entry = entry;
    this.message = message;
  }

  static success(entry: NoticeEntry): NoticeDetailResult {
    return new NoticeDetailResult(true, entry, '');
  }

  static failure(message: string): NoticeDetailResult {
    return new NoticeDetailResult(false, undefined, message);
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
  private sidProvider: () => string;
  private adminProvider: () => boolean;

  private signature: string = '';
  private cache: NoticeEntry[] = [];
  private cachedAt: number = 0;
  private loaded: boolean = false;
  private hydratedKey: string = '';
  /** 并发合并：工作台与通知扫描同时冷启动时只发一轮签名/整表请求。 */
  private inflight: Promise<NoticesResult> | undefined = undefined;

  constructor(api: Api, clock: () => number = () => Date.now(), ttlMs: number = DEFAULT_TTL_MS,
    sidProvider: () => string = () => '', adminProvider: () => boolean = () => false) {
    this.api = api;
    this.clock = clock;
    this.ttlMs = ttlMs;
    this.sidProvider = sidProvider;
    this.adminProvider = adminProvider;
  }

  /** 最近一次签名（未加载过为空串），用于工作台「新通知」角标。 */
  currentSignature(): string {
    return this.signature;
  }

  /**
   * 从本机磁盘恢复上次的通知（冷启动/离线首发用）。
   * 同一会话内只尝试一次；切换账号后按 sid 重新恢复。
   */
  async hydrate(): Promise<void> {
    const sid: string = this.sidProvider();
    const key: string = sid.length > 0 ? sid : 'anon';
    if (this.hydratedKey === key) {
      return;
    }
    // 切换账号（同一台设备退出后换人登录）必须先清空上一位用户的内存缓存，避免串号泄露
    this.hydratedKey = key;
    this.cache = [];
    this.signature = '';
    this.cachedAt = 0;
    this.loaded = false;
    const blob: NoticeCacheBlob | undefined = await NoticeCacheStore.load(sid);
    if (blob === undefined) {
      return;
    }
    if (this.clock() - blob.savedAt > MAX_DISK_AGE_MS) {
      return;
    }
    const rows: NoticeRow[] = this.filterAudience(NoticeBodyParser.parseRows(blob.rowsJson));
    if (rows.length === 0) {
      return;
    }
    this.cache = NoticesRepository.buildEntries(rows);
    this.signature = blob.signature;
    this.cachedAt = blob.savedAt;
    this.loaded = true;
  }

  /**
   * 可见范围的客户端兜底：服务端 RLS 已按 audience 过滤，
   * 这里再拦一次 `sid:` / `admin`（防止缓存或旧环境返回越权行）；
   * committee/league/set 由服务端判定，客户端不猜测。
   */
  private filterAudience(rows: NoticeRow[]): NoticeRow[] {
    const sid: string = this.sidProvider();
    const admin: boolean = this.adminProvider();
    const out: NoticeRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: NoticeRow = rows[i];
      const aud: string = row.audience.trim();
      if (aud.length === 0 || aud === 'all') {
        out.push(row);
        continue;
      }
      if (aud === 'admin') {
        if (admin) {
          out.push(row);
        }
        continue;
      }
      if (aud.indexOf('sid:') === 0) {
        if (aud.substring(4) === sid) {
          out.push(row);
        }
        continue;
      }
      out.push(row);
    }
    return out;
  }

  /** 退出登录：清空内存与当前身份的本机通知缓存。 */
  async clearLocal(): Promise<void> {
    const sid: string = this.sidProvider();
    this.hydratedKey = '';
    this.cache = [];
    this.signature = '';
    this.cachedAt = 0;
    this.loaded = false;
    await NoticeCacheStore.clear(sid);
  }

  async load(force: boolean): Promise<NoticesResult> {
    if (this.inflight !== undefined) {
      return await this.inflight;
    }
    const pending: Promise<NoticesResult> = this.loadOnce(force);
    this.inflight = pending;
    try {
      return await pending;
    } finally {
      if (this.inflight === pending) {
        this.inflight = undefined;
      }
    }
  }

  private async loadOnce(force: boolean): Promise<NoticesResult> {
    await this.hydrate();
    const now: number = this.clock();
    if (!force && this.loaded && now - this.cachedAt < this.ttlMs) {
      return new NoticesResult(true, this.cache, true, '');
    }
    // 列表优先轻量 RPC（约 0.3MB）；只有 404/405（旧云端没有该函数）才回退旧整表。
    const metaResult: ApiResult = await this.api.post(META_PATH, '{}', '', true, META_TIMEOUT_MS);
    if (metaResult.ok) {
      if (!NoticeBodyParser.isRowsPayload(metaResult.value)) {
        return this.cacheOrFailure('通知列表格式异常');
      }
      const rows: NoticeRow[] = this.filterAudience(NoticeBodyParser.parseRows(metaResult.value));
      return await this.commitRows(rows, now, metaResult.value, NoticesRepository.signatureOfRows(rows));
    }
    const status: number = metaResult.error !== undefined ? metaResult.error.status : 0;
    if (status === 404 || status === 405) {
      return await this.loadLegacy(now, force);
    }
    return this.cacheOrFailure(metaResult.error !== undefined
      ? metaResult.error.displayMessage() : '通知加载失败');
  }

  /** 旧云端回退：轻量签名 → 整表（仅 meta 接口不存在时走这里）。 */
  private async loadLegacy(now: number, force: boolean): Promise<NoticesResult> {
    const sigResult: ApiResult = await this.api.get(SIG_PATH, true, SIG_TIMEOUT_MS);
    if (!sigResult.ok) {
      return this.cacheOrFailure(sigResult.error !== undefined
        ? sigResult.error.displayMessage() : '通知签名加载失败');
    }
    const sigRows: NoticeSigRow[] = NoticeBodyParser.parseSigRows(sigResult.value);
    const signature: string = NoticeSigRow.signatureOf(sigRows);
    if (!force && this.loaded && signature === this.signature) {
      this.cachedAt = now;
      return new NoticesResult(true, this.cache, true, '');
    }
    const fullResult: ApiResult = await this.api.get(FULL_PATH, true, FULL_TIMEOUT_MS, false);
    if (!fullResult.ok) {
      return this.cacheOrFailure(fullResult.error !== undefined
        ? fullResult.error.displayMessage() : '通知加载失败');
    }
    const rows: NoticeRow[] = this.filterAudience(NoticeBodyParser.parseRows(fullResult.value));
    return await this.commitRows(rows, now, fullResult.value, signature);
  }

  private async commitRows(rows: NoticeRow[], now: number, rawJson: string,
    signature: string): Promise<NoticesResult> {
    const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
    this.cache = entries;
    this.signature = signature;
    this.cachedAt = now;
    this.loaded = true;
    const blob: NoticeCacheBlob = new NoticeCacheBlob();
    blob.signature = signature;
    blob.savedAt = now;
    blob.rowsJson = rawJson;
    await NoticeCacheStore.save(this.sidProvider(), blob);
    return new NoticesResult(true, entries, false, '');
  }

  private cacheOrFailure(message: string): NoticesResult {
    if (this.loaded) {
      return new NoticesResult(true, this.cache, true, message);
    }
    return new NoticesResult(false, [], false, message);
  }

  /** 按需拉单条完整 body（图片/附件 data URI 只在此时下载）。 */
  async loadDetail(rowId: string): Promise<NoticeDetailResult> {
    const id: string = rowId.trim();
    if (id.length === 0) {
      return NoticeDetailResult.failure('通知不存在');
    }
    const result: ApiResult = await this.api.get(DETAIL_PATH + encodeURIComponent(id), true,
      DETAIL_TIMEOUT_MS, false);
    if (!result.ok) {
      return NoticeDetailResult.failure(result.error !== undefined
        ? result.error.displayMessage() : '通知详情加载失败');
    }
    const rows: NoticeRow[] = this.filterAudience(NoticeBodyParser.parseRows(result.value));
    if (rows.length === 0) {
      return NoticeDetailResult.failure('通知不存在或已隐藏');
    }
    const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
    if (entries.length === 0) {
      return NoticeDetailResult.failure('通知详情为空');
    }
    return NoticeDetailResult.success(entries[0]);
  }

  /** 详情加载完成后替换内存缓存中的同一行（列表顺序由 UI 重建）。 */
  applyDetail(entry: NoticeEntry): void {
    for (let i = 0; i < this.cache.length; i++) {
      if (this.cache[i].row.id === entry.row.id) {
        this.cache[i] = entry;
        return;
      }
    }
  }

  /** 与轻量签名同一口径：按 ts/id 排序后拼 id|ts|hidden|editedAt（避免 RPC 行序变化误报）。 */
  static signatureOfRows(rows: NoticeRow[]): string {
    const sorted: NoticeRow[] = rows.slice(0);
    sorted.sort((a: NoticeRow, b: NoticeRow) => {
      if (a.ts !== b.ts) {
        return a.ts - b.ts;
      }
      if (a.id === b.id) {
        return 0;
      }
      return a.id < b.id ? -1 : 1;
    });
    let out: string = '';
    for (let i = 0; i < sorted.length; i++) {
      out += sorted[i].id + '|' + sorted[i].ts + '|' + (sorted[i].hidden ? '1' : '0') + '|'
        + sorted[i].editedAt + ';';
    }
    return out;
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
        for (let j = 0; j < entry.items.length; j++) {
          if (entry.items[j].lazy) {
            entry.lazy = true;
            break;
          }
        }
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
