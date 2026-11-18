import { Api } from '../net/Api';
import { ApiError, ApiErrorKind, ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob, JsonValue } from './JsonBlob';
import { UserdataV6 } from './UserdataV6';
import { UserdataMerge } from './UserdataMerge';
import { UserdataLocalStore } from './UserdataLocalStore';
import { WaterNormalizer } from './WaterNormalizer';
import { AsyncLock } from '../../common/AsyncLock';
import { Log } from '../../common/Log';

const TAG: string = 'UserdataRepo';
const USERDATA_PATH: string = 'userdata';
const UPSERT_PREFER: string = 'return=representation,resolution=merge-duplicates';

/** 同步节奏常量（契约 §4.3：拉取 TTL 60s、推送防抖 1200ms、清除后抑制期 30 天）。 */
export class UserdataSyncConfig {
  ttlMs: number;
  debounceMs: number;
  holdMs: number;

  constructor(ttlMs: number = 60000, debounceMs: number = 1200, holdMs: number = 30 * 24 * 60 * 60 * 1000) {
    this.ttlMs = ttlMs;
    this.debounceMs = debounceMs;
    this.holdMs = holdMs;
  }
}

/** 拉取结果。`status`：success / disabled / failure。 */
export class UserdataPullResult {
  status: string;
  changed: boolean;
  pushed: boolean;
  fresh: boolean;
  migratedV5: boolean;
  error: ApiError | undefined;

  constructor(status: string, changed: boolean, pushed: boolean, fresh: boolean, migratedV5: boolean,
    error: ApiError | undefined) {
    this.status = status;
    this.changed = changed;
    this.pushed = pushed;
    this.fresh = fresh;
    this.migratedV5 = migratedV5;
    this.error = error;
  }

  static success(changed: boolean, pushed: boolean, fresh: boolean, migratedV5: boolean): UserdataPullResult {
    return new UserdataPullResult('success', changed, pushed, fresh, migratedV5, undefined);
  }

  static disabled(): UserdataPullResult {
    return new UserdataPullResult('disabled', false, false, false, false, undefined);
  }

  static failure(error: ApiError): UserdataPullResult {
    return new UserdataPullResult('failure', false, false, false, false, error);
  }

  ok(): boolean {
    return this.status === 'success';
  }
}

/** 推送结果。`status`：success / skipped / disabled / held / failure。 */
export class UserdataPushResult {
  status: string;
  pushed: boolean;
  error: ApiError | undefined;

  constructor(status: string, pushed: boolean, error: ApiError | undefined) {
    this.status = status;
    this.pushed = pushed;
    this.error = error;
  }

  static success(pushed: boolean): UserdataPushResult {
    return new UserdataPushResult('success', pushed, undefined);
  }

  static skipped(): UserdataPushResult {
    return new UserdataPushResult('skipped', false, undefined);
  }

  static disabled(): UserdataPushResult {
    return new UserdataPushResult('disabled', false, undefined);
  }

  static held(): UserdataPushResult {
    return new UserdataPushResult('held', false, undefined);
  }

  static failure(error: ApiError): UserdataPushResult {
    return new UserdataPushResult('failure', false, error);
  }

  ok(): boolean {
    return this.status === 'success';
  }
}

class RemoteFetch {
  ok: boolean;
  value: Blob | undefined;
  error: ApiError | undefined;

  constructor(ok: boolean, value: Blob | undefined, error: ApiError | undefined) {
    this.ok = ok;
    this.value = value;
    this.error = error;
  }
}

/**
 * userdata v6 双向同步仓库（契约：BACKEND_CONTRACT.md §4 + `USERDATA_V6.md`）。
 *
 * 关键规则（照抄契约，勿简化）：
 * - 脏 section 抢时间戳 `max(now, base.at+1, remote.at+1)`（[UserdataMerge.localView]）；
 * - 无基线不盲推：先 pull 建基线；用户先改动则 markPending 保证本地赢；
 * - push：GET→merge→POST upsert（`Prefer: return=representation,resolution=merge-duplicates`）；
 * - 失败保留 pend 待补发；云端 v5 → 合并后立即写回 v6（迁移幂等）。
 */
export class UserdataRepository {
  private api: Api;
  private local: UserdataLocalStore;
  private sidProvider: () => string;
  private clock: () => number;
  private config: UserdataSyncConfig;
  private owned: Set<string>;

  private lock: AsyncLock = new AsyncLock();
  private sections: Blob = {};
  private listener: ((sections: Blob) => void) | undefined = undefined;
  private debounceTimer: number = -1;
  private recovering: boolean = false;

  constructor(api: Api, local: UserdataLocalStore, sidProvider: () => string,
    clock: () => number = () => Date.now(),
    config: UserdataSyncConfig = new UserdataSyncConfig(),
    ownedSections: Set<string> = defaultOwnedSections()) {
    this.api = api;
    this.local = local;
    this.sidProvider = sidProvider;
    this.clock = clock;
    this.config = config;
    this.owned = ownedSections;
  }

  /** 注册本机 section 变化监听（UI 刷新用）。 */
  onSectionsChanged(listener: (sections: Blob) => void): void {
    this.listener = listener;
  }

  currentSections(): Blob {
    return this.sections;
  }

  private sid(): string {
    return this.sidProvider().trim();
  }

  private emit(sections: Blob): void {
    this.sections = sections;
    if (this.listener !== undefined) {
      this.listener(sections);
    }
  }

  // ---------------------------------------------------------------- 本机变更

  /** 业务层保存本机 section 后调用：持久化 → 更新内存 → 脏检测 → 防抖推送。 */
  async updateCurrent(sections: Blob): Promise<void> {
    const normalized: Blob = UserdataV6.sectionsOf(sections);
    await this.local.writeCurrent(normalized);
    this.emit(normalized);
    await this.onLocalChanged();
  }

  /** 非阻塞通知（业务层已自行写盘时用）。 */
  touch(): void {
    this.onLocalChanged();
  }

  private async onLocalChanged(): Promise<void> {
    if (this.sid().length === 0) {
      return;
    }
    if (!(await this.local.syncEnabled())) {
      return;
    }
    const current: Blob = await this.normalizedCurrent();
    this.emit(current);
    const base: Blob | undefined = await this.local.readCache();

    if (base === undefined) {
      // 无基线：只把「与默认值不同的 section」记为待补发，并先 pull 一次建基线（防默认值覆盖云端）
      const changed: Set<string> = UserdataMerge.changedKeysVsDefaults(current, this.owned);
      if (changed.size === 0) {
        return;
      }
      await this.local.markPending(setToArray(changed));
      if (!this.recovering) {
        this.recovering = true;
        try {
          await this.pull(true);
        } finally {
          this.recovering = false;
        }
      }
      return;
    }

    const dirty: Set<string> = UserdataMerge.dirtySections(base, current, this.owned);
    if (dirty.size > 0) {
      this.schedulePush();
    }
  }

  private schedulePush(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.push(false, new Set<string>());
    }, this.config.debounceMs);
  }

  private async normalizedCurrent(): Promise<Blob> {
    const raw: Blob = await this.local.readCurrent();
    const out: Blob = {};
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      if (!this.owned.has(key)) {
        continue;
      }
      const rawValue: JsonValue | undefined = JsonBlob.get(raw, key);
      if (key === 'water') {
        out[key] = WaterNormalizer.normalize(rawValue);
      } else if (rawValue === null || rawValue === undefined) {
        out[key] = UserdataV6.defaultSection(key);
      } else {
        out[key] = rawValue;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- 拉取

  async pull(force: boolean): Promise<UserdataPullResult> {
    const sid: string = this.sid();
    if (sid.length === 0) {
      return UserdataPullResult.disabled();
    }
    if (!(await this.local.syncEnabled())) {
      return UserdataPullResult.disabled();
    }
    const now: number = this.clock();
    if (!force && now - (await this.local.lastPullAt()) < this.config.ttlMs) {
      return UserdataPullResult.success(false, false, true, false);
    }

    const remoteFetch: RemoteFetch = await this.fetchRemote(sid);
    if (!remoteFetch.ok) {
      const err: ApiError = remoteFetch.error !== undefined
        ? remoteFetch.error
        : new ApiError(ApiErrorKind.Parse, 0, 'parse', 'userdata 响应异常');
      return UserdataPullResult.failure(err);
    }
    const remote: Blob | undefined = remoteFetch.value;
    const wasV5: boolean = remote !== undefined && UserdataV6.numMs(JsonBlob.get(remote, 'v')) === 5;

    const base: Blob | undefined = await this.local.readCache();
    const current: Blob = await this.normalizedCurrent();
    let wasDirty: Set<string> = new Set<string>();
    if (base !== undefined) {
      wasDirty = UserdataMerge.dirtySections(base, current, this.owned);
    }

    const pending: Set<string> = await this.local.pendingKeys();
    const pendFlag: boolean = await this.local.pend();
    const forceKeys: Set<string> = new Set<string>();
    if (pendFlag || pending.size > 0) {
      pending.forEach((key: string) => {
        forceKeys.add(key);
      });
      // 竞态加固：无基线但用户已产生改动时至少保住 power（契约 §4.3 web 同款兜底）
      if (base === undefined) {
        forceKeys.add('power');
      }
      forceKeys.delete('prefs');
    }

    const localView: Blob = UserdataMerge.localView(base, current, remote, forceKeys, now, this.owned);
    const merged: Blob = UserdataMerge.merge(remote, localView);
    const changed: boolean = this.sectionsDiffer(current, merged);

    await this.persistApplied(merged);
    await this.local.setLastPullAt(now);

    const afterCurrent: Blob = await this.normalizedCurrent();
    const dirtyAfter: Set<string> = UserdataMerge.dirtySections(merged, afterCurrent, this.owned);
    const shouldPush: boolean = wasV5 || wasDirty.size > 0 || dirtyAfter.size > 0 || pendFlag || pending.size > 0;
    if (shouldPush) {
      const pushResult: UserdataPushResult = await this.push(true, forceKeys);
      return UserdataPullResult.success(changed || wasV5, pushResult.ok() && pushResult.pushed, false, wasV5);
    }
    return UserdataPullResult.success(changed, false, false, false);
  }

  // ---------------------------------------------------------------- 推送

  async push(force: boolean, forceKeys: Set<string>): Promise<UserdataPushResult> {
    const sid: string = this.sid();
    if (sid.length === 0) {
      return UserdataPushResult.disabled();
    }
    if (!(await this.local.syncEnabled())) {
      return UserdataPushResult.disabled();
    }
    if (this.clock() < (await this.local.holdUntil())) {
      return UserdataPushResult.held();
    }
    return await this.lock.run<UserdataPushResult>(async () => {
      const base: Blob | undefined = await this.local.readCache();
      if (base === undefined && !force && forceKeys.size === 0) {
        return UserdataPushResult.skipped();
      }

      const remoteFetch: RemoteFetch = await this.fetchRemote(sid);
      if (!remoteFetch.ok) {
        await this.local.setPend(true);
        const err: ApiError = remoteFetch.error !== undefined
          ? remoteFetch.error
          : new ApiError(ApiErrorKind.Parse, 0, 'parse', 'userdata 响应异常');
        return UserdataPushResult.failure(err);
      }
      const remote: Blob | undefined = remoteFetch.value;

      const now: number = this.clock();
      const current: Blob = await this.normalizedCurrent();
      const localView: Blob = UserdataMerge.localView(base, current, remote, forceKeys, now, this.owned);
      const merged: Blob = UserdataMerge.merge(remote, localView);
      const remoteNormalized: Blob = UserdataMerge.merge(remote, undefined);
      const mustWrite: boolean = force || remote === undefined || !JsonBlob.deepEqual(merged, remoteNormalized);

      if (!mustWrite) {
        await this.persistApplied(merged);
        await this.local.clearPending();
        return UserdataPushResult.success(false);
      }

      const row: Blob = { 'id': sid, 'blob': UserdataV6.encode(merged), 'ts': now };
      const bodyRows: Object[] = [row];
      const body: string = JSON.stringify(bodyRows);
      const result: ApiResult = await this.api.post(USERDATA_PATH, body, UPSERT_PREFER, true);
      if (!result.ok) {
        const dirty: Set<string> = base !== undefined
          ? UserdataMerge.dirtySections(base, current, this.owned)
          : new Set<string>();
        await this.local.markPending(setToArray(forceKeys.size > 0 ? forceKeys : dirty));
        await this.local.setPend(true);
        const err: ApiError = result.error !== undefined
          ? result.error
          : new ApiError(ApiErrorKind.Network, 0, 'network', '网络连接失败，请检查网络后重试');
        Log.w(TAG, '推送 userdata 失败：' + err.kind);
        return UserdataPushResult.failure(err);
      }
      await this.persistApplied(merged);
      await this.local.clearPending();
      return UserdataPushResult.success(true);
    });
  }

  /** 立即冲刷待推送（页面隐藏/退出前）。 */
  async flush(): Promise<UserdataPushResult> {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.sid().length === 0) {
      return UserdataPushResult.disabled();
    }
    const base: Blob | undefined = await this.local.readCache();
    const current: Blob = await this.normalizedCurrent();
    const dirty: Set<string> = base !== undefined
      ? UserdataMerge.dirtySections(base, current, this.owned)
      : new Set<string>();
    const pendFlag: boolean = await this.local.pend();
    if (!pendFlag && dirty.size === 0) {
      return UserdataPushResult.skipped();
    }
    // web 同款特例：power 变更时强制带上 power（选完宿舍立刻退出也不丢）
    const forceKeys: Set<string> = new Set<string>();
    if (dirty.has('power')) {
      forceKeys.add('power');
    }
    return await this.push(true, forceKeys);
  }

  // ---------------------------------------------------------------- 开关 / 恢复

  async setSyncEnabled(enabled: boolean): Promise<void> {
    await this.local.setSyncEnabled(enabled);
    if (!enabled) {
      if (this.debounceTimer >= 0) {
        clearTimeout(this.debounceTimer);
        this.debounceTimer = -1;
      }
      return;
    }
    // 恢复：先补推待发，再拉一次（契约 §4.3）
    if (await this.local.pend()) {
      await this.push(true, new Set<string>());
    } else {
      await this.pull(true);
    }
  }

  async syncEnabled(): Promise<boolean> {
    return await this.local.syncEnabled();
  }

  /** 最近一次成功合并的基线 blob（调试/清除云端用）。 */
  async cachedBlob(): Promise<Blob | undefined> {
    return await this.local.readCache();
  }

  /** 退出登录/切换账号：清空本 sid 的本机数据桶（合规要求，与安卓一致）。 */
  async clearLocal(): Promise<void> {
    await this.local.clear();
    this.sections = {};
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.listener !== undefined) {
      this.listener({});
    }
  }

  /** 从本机持久化的 current 恢复内存镜像（登录/启动时、pull 之前调用）。 */
  async hydrateFromLocal(): Promise<void> {
    if (this.sid().length === 0) {
      return;
    }
    if (JsonBlob.keys(this.sections).length > 0) {
      return;
    }
    const stored: Blob = await this.local.readCurrent();
    if (JsonBlob.keys(stored).length === 0) {
      return;
    }
    this.emit(UserdataV6.sectionsOf(stored));
  }

  // ---------------------------------------------------------------- 内部

  private async persistApplied(merged: Blob): Promise<void> {
    const sections: Blob = UserdataV6.sectionsOf(merged);
    await this.local.writeCache(merged);
    await this.local.writeCurrent(sections);
    this.emit(sections);
  }

  private async fetchRemote(sid: string): Promise<RemoteFetch> {
    const path: string = USERDATA_PATH + '?select=*&id=eq.' + encodeURIComponent(sid);
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      return new RemoteFetch(false, undefined, result.error);
    }
    const parsed: JsonValue | undefined = tryParse(result.value);
    if (parsed === undefined) {
      return new RemoteFetch(false, undefined,
        new ApiError(ApiErrorKind.Parse, 0, 'parse', 'userdata 响应不是合法 JSON'));
    }
    const rows: Object[] | undefined = JsonBlob.asArray(parsed);
    if (rows === undefined) {
      // 非数组（例如空响应）视为「云端无数据」，不覆盖本机
      return new RemoteFetch(true, undefined, undefined);
    }
    if (rows.length === 0) {
      return new RemoteFetch(true, undefined, undefined);
    }
    const row: Blob | undefined = JsonBlob.asBlob(rows[0]);
    if (row === undefined) {
      return new RemoteFetch(true, undefined, undefined);
    }
    const blobText: string = JsonBlob.asString(JsonBlob.get(row, 'blob'), '');
    const blob: Blob | undefined = UserdataV6.decode(blobText);
    return new RemoteFetch(true, blob, undefined);
  }

  private sectionsDiffer(current: Blob, merged: Blob): boolean {
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      if (!this.owned.has(key)) {
        continue;
      }
      const currentRaw: JsonValue | undefined = JsonBlob.get(current, key);
      const currentValue: JsonValue = currentRaw !== null && currentRaw !== undefined
        ? currentRaw
        : UserdataV6.defaultSection(key);
      if (!JsonBlob.deepEqual(currentValue, JsonBlob.get(merged, key))) {
        return true;
      }
    }
    return false;
  }
}

function tryParse(text: string): JsonValue | undefined {
  if (text.length === 0) {
    return undefined;
  }
  try {
    return JSON.parse(text) as JsonValue;
  } catch (e) {
    return undefined;
  }
}

export function setToArray(set: Set<string>): string[] {
  const out: string[] = [];
  set.forEach((value: string) => {
    out.push(value);
  });
  return out;
}

export function defaultOwnedSections(): Set<string> {
  const set: Set<string> = new Set<string>();
  for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
    set.add(UserdataV6.SECTION_KEYS[i]);
  }
  return set;
}
