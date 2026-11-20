import { VisitRow } from './VisitsRepository';

/**
 * 访问统计纯逻辑（唯一口径：`web/统计多端_详细统计_契约_20261120.md` §3）。
 *
 * - 过滤：空 sid（历史匿名行）、测试账号（`3260799999` / 10 位 `9999` 段）、范围外与未来时间；
 * - `effectiveTs = ts > 0 ? ts : slot 整点`，按**本地时区**取自然日；
 * - 账号聚合：次数 / 首次 / 最近 / 最近登录端·版本·设备 / 活跃天数 / 登录端 / 版本 / 设备 / 设备数；
 * - 排序：次数降序 → 最近时间降序 → 姓名升序；
 * - 全局：摘要 4 项、趋势（今天 24 小时 / 近 7 天）、登录端 / 版本 / 设备分布（最多 6 行 + 其他）；
 * - 百分比：分母 = 当前范围过滤后的总行数，四舍五入后最后一段补齐 100%。
 *
 * 不依赖 ArkUI / 网络，hypium 可直接单测；`sid` 只作聚合键，**不展示**。
 */

/** 统计范围：今天 / 近 7 天。 */
export enum VisitRange {
  TODAY = 'today',
  WEEK = 'week'
}

/** 登录端固定中文标签 + 颜色（契约 §4，五端同一套；暗色模式只换底槽不换端颜色）。 */
export class VisitClientDef {
  key: string = '';
  label: string = '';
  color: string = '';

  constructor(key: string, label: string, color: string) {
    this.key = key;
    this.label = label;
    this.color = color;
  }
}

export class VisitClients {
  static readonly WEB: VisitClientDef = new VisitClientDef('web', '网页', '#4E9082');
  static readonly MP: VisitClientDef = new VisitClientDef('mp', '小程序', '#6E8CA8');
  static readonly ANDROID: VisitClientDef = new VisitClientDef('android', '安卓', '#5F8F5B');
  static readonly WIN: VisitClientDef = new VisitClientDef('win', 'Windows', '#B98F63');
  static readonly HARMONY: VisitClientDef = new VisitClientDef('harmony', '鸿蒙', '#8A6A92');
  static readonly UNKNOWN: VisitClientDef = new VisitClientDef('', '未记录', '#9AA5A1');
  static readonly ALL: VisitClientDef[] = [VisitClients.WEB, VisitClients.MP, VisitClients.ANDROID,
    VisitClients.WIN, VisitClients.HARMONY];

  /** 归一化 client：已知端返回小写 key，其它 / 空一律记「未记录」（key 为空串）。 */
  static key(client: string): string {
    const text: string = client.trim().toLowerCase();
    for (let i = 0; i < VisitClients.ALL.length; i++) {
      if (VisitClients.ALL[i].key === text) {
        return text;
      }
    }
    return '';
  }

  static def(client: string): VisitClientDef {
    const key: string = VisitClients.key(client);
    for (let i = 0; i < VisitClients.ALL.length; i++) {
      if (VisitClients.ALL[i].key === key) {
        return VisitClients.ALL[i];
      }
    }
    return VisitClients.UNKNOWN;
  }

  static label(client: string): string {
    return VisitClients.def(client).label;
  }

  static color(client: string): string {
    return VisitClients.def(client).color;
  }
}

/** 登录端分布一行（堆叠条 + 图例）。 */
export class VisitClientCount {
  client: string = '';
  label: string = '';
  color: string = '';
  count: number = 0;
  percent: number = 0;
}

/** 版本分布一行（最多 6 行 + 其他）。 */
export class VisitVersionCount {
  /** 原版本号（空串 = 旧行「未记录」）。 */
  version: string = '';
  label: string = '';
  count: number = 0;
  percent: number = 0;
  other: boolean = false;
}

/** 设备分布 / 账号设备明细一行（`client|dev` 分组）。 */
export class VisitDeviceGroup {
  client: string = '';
  clientLabel: string = '';
  color: string = '';
  /** 原设备标签（空串 = 旧行「未记录」）。 */
  dev: string = '';
  devLabel: string = '';
  count: number = 0;
  lastTs: number = 0;
  percent: number = 0;
  other: boolean = false;
}

/** 趋势柱一根（今天 24 小时 / 近 7 天）。 */
export class VisitTrendPoint {
  label: string = '';
  count: number = 0;
  /** count / 峰值（0..1），UI 按它算柱高。 */
  ratio: number = 0;
  highlight: boolean = false;
}

/** 摘要 4 格。 */
export class VisitStatsSummary {
  accounts: number = 0;
  visits: number = 0;
  activeToday: number = 0;
  devices: number = 0;
}

/** 账号明细一行（`key` = sid，仅内部聚合键，不渲染）。 */
export class VisitAccount {
  key: string = '';
  name: string = '';
  count: number = 0;
  firstTs: number = 0;
  lastTs: number = 0;
  lastClient: string = '';
  lastDev: string = '';
  lastVer: string = '';
  activeDays: number = 0;
  activeToday: boolean = false;
  deviceCount: number = 0;
  /** `活跃 N/7 天 · 首次 MM/dd HH:mm · 最近 MM/dd HH:mm`（今天范围省略活跃段）。 */
  detailText: string = '';
  /** count / 当前范围最大账号次数（0..1）。 */
  ratio: number = 0;
  clients: VisitClientCount[] = [];
  versions: VisitVersionCount[] = [];
  devices: VisitDeviceGroup[] = [];

  lastClientLabel(): string {
    return VisitClients.label(this.lastClient);
  }

  lastVerLabel(): string {
    return this.lastVer.length > 0 ? this.lastVer : '未记录';
  }

  lastDevLabel(): string {
    return this.lastDev.length > 0 ? this.lastDev : '未记录';
  }

  /** 登录端明细：`网页 3 · 安卓 1`。 */
  clientText(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.clients.length; i++) {
      parts.push(this.clients[i].label + ' ' + this.clients[i].count);
    }
    return parts.join(' · ');
  }

  /** 版本明细：`2.0.0 ×2 · 未记录 ×1`。 */
  versionText(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.versions.length; i++) {
      parts.push(this.versions[i].label + ' ×' + this.versions[i].count);
    }
    return parts.join(' · ');
  }
}

/** 一次聚合的完整视图（页面只渲染，不再算数）。 */
export class VisitStatsReport {
  range: VisitRange = VisitRange.TODAY;
  empty: boolean = true;
  emptyText: string = '今天暂无访问';
  totalRows: number = 0;
  summary: VisitStatsSummary = new VisitStatsSummary();
  accounts: VisitAccount[] = [];
  trend: VisitTrendPoint[] = [];
  trendTitle: string = '今天 24 小时';
  trendPeak: string = '';
  clients: VisitClientCount[] = [];
  versions: VisitVersionCount[] = [];
  devices: VisitDeviceGroup[] = [];
}

/** 过滤后的一条记录（row + 有效时间 + 本地自然日）。 */
class VisitEntry {
  row: VisitRow = new VisitRow();
  sid: string = '';
  ts: number = 0;
  day: string = '';
  index: number = 0;

  constructor(row: VisitRow, sid: string, ts: number, day: string, index: number) {
    this.row = row;
    this.sid = sid;
    this.ts = ts;
    this.day = day;
    this.index = index;
  }
}

/** 单账号聚合中间态。 */
class AccountBucket {
  sid: string = '';
  name: string = '';
  nameTs: number = -1;
  count: number = 0;
  firstTs: number = 0;
  lastTs: number = 0;
  lastClient: string = '';
  lastDev: string = '';
  lastVer: string = '';
  days: Set<string> = new Set<string>();
  clients: Map<string, number> = new Map<string, number>();
  versions: Map<string, number> = new Map<string, number>();
  devices: Map<string, number> = new Map<string, number>();
  deviceLast: Map<string, number> = new Map<string, number>();
  deviceClient: Map<string, string> = new Map<string, string>();
  deviceDev: Map<string, string> = new Map<string, string>();
  dids: Set<string> = new Set<string>();
  devFallback: Set<string> = new Set<string>();

  add(entry: VisitEntry): void {
    this.count = this.count + 1;
    if (this.firstTs === 0 || entry.ts < this.firstTs) {
      this.firstTs = entry.ts;
    }
    // 最近一行：同一时间取输入顺序靠后者（`>=`）。
    if (entry.ts >= this.lastTs) {
      this.lastTs = entry.ts;
      this.lastClient = entry.row.client;
      this.lastDev = entry.row.dev;
      this.lastVer = entry.row.ver;
    }
    // 姓名：最近一条有姓名的行。
    const name: string = entry.row.name.trim();
    if (name.length > 0 && entry.ts >= this.nameTs) {
      this.name = name;
      this.nameTs = entry.ts;
    }
    this.days.add(entry.day);
    const clientKey: string = VisitClients.key(entry.row.client);
    const version: string = VisitStats.cleanVersion(entry.row.ver);
    const dev: string = VisitStats.cleanDev(entry.row.dev);
    const devKey: string = clientKey + '|' + dev;
    VisitStats.addCount(this.clients, clientKey);
    VisitStats.addCount(this.versions, version);
    VisitStats.addCount(this.devices, devKey);
    const previous: number | undefined = this.deviceLast.get(devKey);
    if (previous === undefined || entry.ts > previous) {
      this.deviceLast.set(devKey, entry.ts);
    }
    this.deviceClient.set(devKey, clientKey);
    this.deviceDev.set(devKey, dev);
    const did: string = entry.row.did.trim();
    if (did.length > 0) {
      this.dids.add(did);
    } else {
      this.devFallback.add(devKey);
    }
  }
}

export class VisitStats {
  static readonly OFFICIAL_TEST_SID: string = '3260799999';
  static readonly UNKNOWN_NAME: string = '班级成员';
  static readonly UNKNOWN_LABEL: string = '未记录';
  static readonly OTHER_LABEL: string = '其他';
  /** 版本 / 设备分布最多展示 6 组，其余合并「其他」。 */
  static readonly MAX_GROUPS: number = 6;

  /** 官方测试身份或 10 位 9999 段临时 QA 身份。 */
  static isTestAccount(sid: string): boolean {
    const text: string = sid.trim();
    if (text === VisitStats.OFFICIAL_TEST_SID) {
      return true;
    }
    return text.length === 10 && text.startsWith('9999');
  }

  /** 毫秒时间；旧行 `ts=0` 回退 slot 的整点（非法 slot → 0）。 */
  static effectiveTs(row: VisitRow): number {
    return row.ts > 0 ? row.ts : VisitStats.slotToTs(row.slot);
  }

  /** `YYYY-MM-DD-HH`（本地时区）→ 毫秒；格式 / 数值非法返回 0。 */
  static slotToTs(slot: string): number {
    const text: string = slot.trim();
    if (text.length < 13) {
      return 0;
    }
    if (text.charAt(4) !== '-' || text.charAt(7) !== '-' || text.charAt(10) !== '-') {
      return 0;
    }
    const year: number = Number(text.substring(0, 4));
    const month: number = Number(text.substring(5, 7));
    const day: number = Number(text.substring(8, 10));
    const hour: number = Number(text.substring(11, 13));
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)
      || !Number.isFinite(hour)) {
      return 0;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23) {
      return 0;
    }
    const date: Date = new Date(year, month - 1, day, hour, 0, 0, 0);
    const ts: number = date.getTime();
    return Number.isFinite(ts) ? ts : 0;
  }

  /** 本地自然日 key：`YYYY-MM-DD`。 */
  static dayKey(date: Date): string {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  /** 本地时间 `MM/dd HH:mm`（ts<=0 → 空串）。 */
  static formatTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const date: Date = new Date(ts);
    if (!Number.isFinite(date.getTime())) {
      return '';
    }
    return pad2(date.getMonth() + 1) + '/' + pad2(date.getDate()) + ' '
      + pad2(date.getHours()) + ':' + pad2(date.getMinutes());
  }

  /**
   * 构建统计视图。
   *
   * @param rows 原始 visits 行（可含匿名 / 测试行，内部过滤）
   * @param range 今天 / 近 7 天
   * @param nowMs 当前时间（测试可注入）
   * @param nameOf 名单姓名兜底（visits 行没有姓名时用，默认无名单）
   */
  static build(rows: VisitRow[], range: VisitRange, nowMs: number,
    nameOf: (sid: string) => string = () => ''): VisitStatsReport {
    const report: VisitStatsReport = new VisitStatsReport();
    report.range = range;

    const now: Date = new Date(nowMs);
    const todayKey: string = VisitStats.dayKey(now);
    const weekKeys: string[] = VisitStats.weekKeys(now);

    const entries: VisitEntry[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: VisitRow = rows[i];
      const sid: string = row.sid.trim();
      if (sid.length === 0 || VisitStats.isTestAccount(sid)) {
        continue;
      }
      const ts: number = VisitStats.effectiveTs(row);
      if (ts <= 0) {
        continue;
      }
      const day: string = VisitStats.dayKey(new Date(ts));
      const inRange: boolean = range === VisitRange.WEEK ? weekKeys.indexOf(day) >= 0 : day === todayKey;
      if (!inRange) {
        continue;
      }
      entries.push(new VisitEntry(row, sid, ts, day, i));
    }

    const buckets: Map<string, AccountBucket> = new Map<string, AccountBucket>();
    const globalClients: Map<string, number> = new Map<string, number>();
    const globalVersions: Map<string, number> = new Map<string, number>();
    const globalDevices: Map<string, number> = new Map<string, number>();
    const globalDeviceLast: Map<string, number> = new Map<string, number>();
    const globalDeviceClient: Map<string, string> = new Map<string, string>();
    const globalDeviceDev: Map<string, string> = new Map<string, string>();
    const globalDids: Set<string> = new Set<string>();
    const globalDevFallback: Set<string> = new Set<string>();

    for (let i = 0; i < entries.length; i++) {
      const entry: VisitEntry = entries[i];
      let bucket: AccountBucket | undefined = buckets.get(entry.sid);
      if (bucket === undefined) {
        bucket = new AccountBucket();
        bucket.sid = entry.sid;
        buckets.set(entry.sid, bucket);
      }
      bucket.add(entry);

      const clientKey: string = VisitClients.key(entry.row.client);
      const version: string = VisitStats.cleanVersion(entry.row.ver);
      const dev: string = VisitStats.cleanDev(entry.row.dev);
      const devKey: string = clientKey + '|' + dev;
      VisitStats.addCount(globalClients, clientKey);
      VisitStats.addCount(globalVersions, version);
      VisitStats.addCount(globalDevices, devKey);
      const previous: number | undefined = globalDeviceLast.get(devKey);
      if (previous === undefined || entry.ts > previous) {
        globalDeviceLast.set(devKey, entry.ts);
      }
      globalDeviceClient.set(devKey, clientKey);
      globalDeviceDev.set(devKey, dev);
      const did: string = entry.row.did.trim();
      if (did.length > 0) {
        globalDids.add(did);
      } else {
        globalDevFallback.add(devKey);
      }
    }

    const accounts: VisitAccount[] = [];
    buckets.forEach((bucket: AccountBucket) => {
      accounts.push(VisitStats.finishAccount(bucket, range, todayKey, nameOf));
    });
    accounts.sort((a: VisitAccount, b: VisitAccount) => {
      if (a.count !== b.count) {
        return b.count - a.count;
      }
      if (a.lastTs !== b.lastTs) {
        return b.lastTs - a.lastTs;
      }
      if (a.name === b.name) {
        return 0;
      }
      return a.name < b.name ? -1 : 1;
    });
    let maxCount: number = 1;
    for (let i = 0; i < accounts.length; i++) {
      if (accounts[i].count > maxCount) {
        maxCount = accounts[i].count;
      }
    }
    for (let i = 0; i < accounts.length; i++) {
      accounts[i].ratio = accounts[i].count / maxCount;
    }

    report.accounts = accounts;
    report.totalRows = entries.length;
    report.summary.accounts = accounts.length;
    report.summary.visits = entries.length;
    let activeToday: number = 0;
    for (let i = 0; i < accounts.length; i++) {
      if (accounts[i].activeToday) {
        activeToday = activeToday + 1;
      }
    }
    report.summary.activeToday = activeToday;
    report.summary.devices = globalDids.size + globalDevFallback.size;
    report.clients = VisitStats.buildClientCounts(globalClients, entries.length);
    report.versions = VisitStats.buildVersionCounts(globalVersions, entries.length);
    report.devices = VisitStats.buildDeviceGroups(globalDevices, globalDeviceLast, globalDeviceClient,
      globalDeviceDev, entries.length, VisitStats.MAX_GROUPS);
    report.trend = VisitStats.buildTrend(entries, range, now);
    report.trendTitle = range === VisitRange.TODAY ? '今天 24 小时' : '近 7 天';
    report.trendPeak = VisitStats.peakText(report.trend, range);
    report.empty = accounts.length === 0;
    report.emptyText = range === VisitRange.TODAY ? '今天暂无访问' : '近 7 天暂无访问';
    return report;
  }

  /** 账号明细文案（今天范围省略活跃段）。 */
  static detailText(range: VisitRange, activeDays: number, firstTs: number, lastTs: number): string {
    const parts: string[] = [];
    if (range === VisitRange.WEEK) {
      parts.push('活跃 ' + activeDays + '/7 天');
    }
    const first: string = VisitStats.formatTime(firstTs);
    if (first.length > 0) {
      parts.push('首次 ' + first);
    }
    const last: string = VisitStats.formatTime(lastTs);
    if (last.length > 0) {
      parts.push('最近 ' + last);
    }
    return parts.join(' · ');
  }

  /** 版本号降序（数字段逐段比较；空串「未记录」排在数值版本之后）。 */
  static compareVersionDesc(a: string, b: string): number {
    const left: number[] = VisitStats.versionNumbers(a);
    const right: number[] = VisitStats.versionNumbers(b);
    const length: number = Math.max(left.length, right.length);
    for (let i = 0; i < length; i++) {
      const x: number = i < left.length ? left[i] : 0;
      const y: number = i < right.length ? right[i] : 0;
      if (x !== y) {
        return y - x;
      }
    }
    if (a.length === 0 && b.length > 0) {
      return 1;
    }
    if (b.length === 0 && a.length > 0) {
      return -1;
    }
    if (a === b) {
      return 0;
    }
    return a < b ? 1 : -1;
  }

  /** 版本号里的数字段：`1.0.0-beta14` → `[1,0,0,14]`。 */
  static versionNumbers(version: string): number[] {
    const out: number[] = [];
    let current: string = '';
    for (let i = 0; i < version.length; i++) {
      const code: number = version.charCodeAt(i);
      if (code >= 48 && code <= 57) {
        current += version.charAt(i);
      } else if (current.length > 0) {
        out.push(Number(current));
        current = '';
      }
    }
    if (current.length > 0) {
      out.push(Number(current));
    }
    return out;
  }

  /** 四舍五入百分比；最后一段补齐到 100%（契约 §3.4）。 */
  static percents(counts: number[], total: number): number[] {
    const out: number[] = [];
    if (counts.length === 0) {
      return out;
    }
    if (total <= 0) {
      for (let i = 0; i < counts.length; i++) {
        out.push(0);
      }
      return out;
    }
    let sum: number = 0;
    for (let i = 0; i < counts.length; i++) {
      if (i === counts.length - 1) {
        let rest: number = 100 - sum;
        if (rest < 0) {
          rest = 0;
        }
        if (rest > 100) {
          rest = 100;
        }
        out.push(rest);
      } else {
        let percent: number = Math.round(counts[i] * 100 / total);
        if (percent < 0) {
          percent = 0;
        }
        if (percent > 100) {
          percent = 100;
        }
        out.push(percent);
        sum = sum + percent;
      }
    }
    return out;
  }

  /** 名称归一：行内最近姓名 → 名单兜底 → 「班级成员」。 */
  private static resolveName(bucket: AccountBucket, nameOf: (sid: string) => string): string {
    if (bucket.name.length > 0) {
      return bucket.name;
    }
    const fallback: string = nameOf(bucket.sid).trim();
    return fallback.length > 0 ? fallback : VisitStats.UNKNOWN_NAME;
  }

  private static finishAccount(bucket: AccountBucket, range: VisitRange, todayKey: string,
    nameOf: (sid: string) => string): VisitAccount {
    const account: VisitAccount = new VisitAccount();
    account.key = bucket.sid;
    account.name = VisitStats.resolveName(bucket, nameOf);
    account.count = bucket.count;
    account.firstTs = bucket.firstTs;
    account.lastTs = bucket.lastTs;
    account.lastClient = VisitClients.key(bucket.lastClient);
    account.lastDev = VisitStats.cleanDev(bucket.lastDev);
    account.lastVer = VisitStats.cleanVersion(bucket.lastVer);
    account.activeDays = bucket.days.size;
    account.activeToday = bucket.days.has(todayKey);
    account.deviceCount = bucket.dids.size + bucket.devFallback.size;
    account.detailText = VisitStats.detailText(range, account.activeDays, account.firstTs, account.lastTs);
    account.clients = VisitStats.buildClientCounts(bucket.clients, bucket.count);
    account.versions = VisitStats.buildVersionCounts(bucket.versions, bucket.count);
    account.devices = VisitStats.buildDeviceGroups(bucket.devices, bucket.deviceLast, bucket.deviceClient,
      bucket.deviceDev, bucket.count, VisitStats.MAX_GROUPS);
    return account;
  }

  private static buildClientCounts(counts: Map<string, number>, total: number): VisitClientCount[] {
    const keys: string[] = [];
    counts.forEach((count: number, key: string) => {
      keys.push(key);
    });
    keys.sort((a: string, b: string) => {
      const left: number = counts.get(a) ?? 0;
      const right: number = counts.get(b) ?? 0;
      if (left !== right) {
        return right - left;
      }
      const labelA: string = VisitClients.label(a);
      const labelB: string = VisitClients.label(b);
      if (labelA === labelB) {
        return 0;
      }
      return labelA < labelB ? -1 : 1;
    });
    const out: VisitClientCount[] = [];
    const numbers: number[] = [];
    for (let i = 0; i < keys.length; i++) {
      const item: VisitClientCount = new VisitClientCount();
      item.client = keys[i];
      item.label = VisitClients.label(keys[i]);
      item.color = VisitClients.color(keys[i]);
      item.count = counts.get(keys[i]) ?? 0;
      out.push(item);
      numbers.push(item.count);
    }
    VisitStats.assignPercents(out.length, numbers, total, (index: number, percent: number) => {
      out[index].percent = percent;
    });
    return out;
  }

  private static buildVersionCounts(counts: Map<string, number>, total: number): VisitVersionCount[] {
    const keys: string[] = [];
    counts.forEach((count: number, key: string) => {
      keys.push(key);
    });
    keys.sort((a: string, b: string) => {
      const left: number = counts.get(a) ?? 0;
      const right: number = counts.get(b) ?? 0;
      if (left !== right) {
        return right - left;
      }
      return VisitStats.compareVersionDesc(a, b);
    });
    const out: VisitVersionCount[] = [];
    let rest: number = 0;
    for (let i = 0; i < keys.length; i++) {
      const count: number = counts.get(keys[i]) ?? 0;
      if (i < VisitStats.MAX_GROUPS) {
        const item: VisitVersionCount = new VisitVersionCount();
        item.version = keys[i];
        item.label = keys[i].length > 0 ? keys[i] : VisitStats.UNKNOWN_LABEL;
        item.count = count;
        out.push(item);
      } else {
        rest = rest + count;
      }
    }
    if (rest > 0) {
      const other: VisitVersionCount = new VisitVersionCount();
      other.version = '';
      other.label = VisitStats.OTHER_LABEL;
      other.count = rest;
      other.other = true;
      out.push(other);
    }
    const numbers: number[] = [];
    for (let i = 0; i < out.length; i++) {
      numbers.push(out[i].count);
    }
    VisitStats.assignPercents(out.length, numbers, total, (index: number, percent: number) => {
      out[index].percent = percent;
    });
    return out;
  }

  private static buildDeviceGroups(counts: Map<string, number>, lastTs: Map<string, number>,
    clients: Map<string, string>, devs: Map<string, string>, total: number,
    limit: number): VisitDeviceGroup[] {
    const keys: string[] = [];
    counts.forEach((count: number, key: string) => {
      keys.push(key);
    });
    keys.sort((a: string, b: string) => {
      const leftCount: number = counts.get(a) ?? 0;
      const rightCount: number = counts.get(b) ?? 0;
      if (leftCount !== rightCount) {
        return rightCount - leftCount;
      }
      const leftTs: number = lastTs.get(a) ?? 0;
      const rightTs: number = lastTs.get(b) ?? 0;
      if (leftTs !== rightTs) {
        return rightTs - leftTs;
      }
      const leftKey: string = (clients.get(a) ?? '') + '|' + (devs.get(a) ?? '');
      const rightKey: string = (clients.get(b) ?? '') + '|' + (devs.get(b) ?? '');
      if (leftKey === rightKey) {
        return 0;
      }
      return leftKey < rightKey ? -1 : 1;
    });
    const out: VisitDeviceGroup[] = [];
    let rest: number = 0;
    let restLastTs: number = 0;
    for (let i = 0; i < keys.length; i++) {
      const count: number = counts.get(keys[i]) ?? 0;
      if (i < limit) {
        const item: VisitDeviceGroup = new VisitDeviceGroup();
        item.client = clients.get(keys[i]) ?? '';
        item.clientLabel = VisitClients.label(item.client);
        item.color = VisitClients.color(item.client);
        item.dev = devs.get(keys[i]) ?? '';
        item.devLabel = item.dev.length > 0 ? item.dev : VisitStats.UNKNOWN_LABEL;
        item.count = count;
        item.lastTs = lastTs.get(keys[i]) ?? 0;
        out.push(item);
      } else {
        rest = rest + count;
        const ts: number = lastTs.get(keys[i]) ?? 0;
        if (ts > restLastTs) {
          restLastTs = ts;
        }
      }
    }
    if (rest > 0) {
      const other: VisitDeviceGroup = new VisitDeviceGroup();
      other.client = '';
      other.clientLabel = VisitStats.OTHER_LABEL;
      other.color = VisitClients.UNKNOWN.color;
      other.dev = '';
      other.devLabel = VisitStats.OTHER_LABEL;
      other.count = rest;
      other.lastTs = restLastTs;
      other.other = true;
      out.push(other);
    }
    const numbers: number[] = [];
    for (let i = 0; i < out.length; i++) {
      numbers.push(out[i].count);
    }
    VisitStats.assignPercents(out.length, numbers, total, (index: number, percent: number) => {
      out[index].percent = percent;
    });
    return out;
  }

  private static buildTrend(entries: VisitEntry[], range: VisitRange, now: Date): VisitTrendPoint[] {
    const out: VisitTrendPoint[] = [];
    if (range === VisitRange.TODAY) {
      const counts: number[] = [];
      for (let hour = 0; hour < 24; hour++) {
        counts.push(0);
      }
      for (let i = 0; i < entries.length; i++) {
        const hour: number = new Date(entries[i].ts).getHours();
        if (hour >= 0 && hour < 24) {
          counts[hour] = counts[hour] + 1;
        }
      }
      let max: number = 1;
      for (let hour = 0; hour < 24; hour++) {
        if (counts[hour] > max) {
          max = counts[hour];
        }
      }
      for (let hour = 0; hour < 24; hour++) {
        const point: VisitTrendPoint = new VisitTrendPoint();
        point.label = pad2(hour);
        point.count = counts[hour];
        point.ratio = counts[hour] / max;
        out.push(point);
      }
      return out;
    }

    const todayKey: string = VisitStats.dayKey(now);
    const counts: Map<string, number> = new Map<string, number>();
    const keys: string[] = [];
    for (let i = 6; i >= 0; i--) {
      const day: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
      const key: string = VisitStats.dayKey(day);
      keys.push(key);
      counts.set(key, 0);
    }
    for (let i = 0; i < entries.length; i++) {
      const key: string = entries[i].day;
      const previous: number | undefined = counts.get(key);
      if (previous !== undefined) {
        counts.set(key, previous + 1);
      }
    }
    let max: number = 1;
    for (let i = 0; i < keys.length; i++) {
      const count: number = counts.get(keys[i]) ?? 0;
      if (count > max) {
        max = count;
      }
    }
    for (let i = 0; i < keys.length; i++) {
      const day: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (6 - i));
      const point: VisitTrendPoint = new VisitTrendPoint();
      point.label = pad2(day.getMonth() + 1) + '/' + pad2(day.getDate());
      point.count = counts.get(keys[i]) ?? 0;
      point.ratio = point.count / max;
      point.highlight = keys[i] === todayKey;
      out.push(point);
    }
    return out;
  }

  private static peakText(points: VisitTrendPoint[], range: VisitRange): string {
    let max: number = 0;
    let label: string = '';
    for (let i = 0; i < points.length; i++) {
      if (points[i].count > max) {
        max = points[i].count;
        label = points[i].label;
      }
    }
    if (max <= 0) {
      return '';
    }
    return range === VisitRange.TODAY ? '峰值 ' + max + ' · ' + label + ' 时' : '峰值 ' + max + ' · ' + label;
  }

  /** 近 7 天（今天 - 6 … 今天）的本地自然日 key，升序。 */
  private static weekKeys(now: Date): string[] {
    const keys: string[] = [];
    for (let i = 6; i >= 0; i--) {
      keys.push(VisitStats.dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)));
    }
    return keys;
  }

  /** 设备标签：去空白、连续空白合并（分组 / 展示同一口径；空串留给「未记录」）。 */
  static cleanDev(dev: string): string {
    if (dev.length === 0) {
      return '';
    }
    let out: string = '';
    let pendingSpace: boolean = false;
    for (let i = 0; i < dev.length; i++) {
      const code: number = dev.charCodeAt(i);
      const isSpace: boolean = code === 32 || code === 9 || code === 10 || code === 13
        || code === 0x00A0 || code === 0x3000;
      if (isSpace) {
        pendingSpace = out.length > 0;
      } else {
        if (pendingSpace) {
          out += ' ';
          pendingSpace = false;
        }
        out += dev.charAt(i);
      }
    }
    return out;
  }

  static cleanVersion(version: string): string {
    return version.trim();
  }

  static addCount(counts: Map<string, number>, key: string): void {
    const previous: number | undefined = counts.get(key);
    counts.set(key, previous === undefined ? 1 : previous + 1);
  }

  private static assignPercents(length: number, counts: number[], total: number,
    assign: (index: number, percent: number) => void): void {
    const percents: number[] = VisitStats.percents(counts, total);
    for (let i = 0; i < length; i++) {
      assign(i, i < percents.length ? percents[i] : 0);
    }
  }
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
