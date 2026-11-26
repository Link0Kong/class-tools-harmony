import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { ApiResult } from '../main/ets/data/net/ApiResult';
import { InMemoryUserdataLocalStore } from '../main/ets/data/sync/UserdataLocalStore';
import { UserdataRepository, UserdataPullResult, UserdataPushResult, UserdataSyncConfig } from '../main/ets/data/sync/UserdataRepository';
import { UserdataV6 } from '../main/ets/data/sync/UserdataV6';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';
import { USERDATA_V6_WEB } from './fixtures/SyncFixtures';

const SID: string = '3260799999';

class ResponseGate {
  private signal: () => void = () => {};
  private resume: () => void = () => {};
  started: Promise<void> = new Promise<void>((resolve: () => void) => { this.signal = resolve; });
  private released: Promise<void> = new Promise<void>((resolve: () => void) => { this.resume = resolve; });

  wait(): Promise<void> {
    this.signal();
    return this.released;
  }

  release(): void { this.resume(); }
}

class HeldUserdataApi extends FakeApi {
  getGate?: ResponseGate;
  postGate?: ResponseGate;

  async get(path: string, authenticated: boolean = true, readTimeoutMs: number = 0,
    retryOnNetworkFailure: boolean = true): Promise<ApiResult> {
    const result = await super.get(path, authenticated, readTimeoutMs, retryOnNetworkFailure);
    if (this.getGate) await this.getGate.wait();
    return result;
  }

  async post(path: string, body: string, prefer: string = '', authenticated: boolean = true,
    readTimeoutMs: number = 0): Promise<ApiResult> {
    const result = await super.post(path, body, prefer, authenticated, readTimeoutMs);
    if (this.postGate) await this.postGate.wait();
    return result;
  }
}

class HeldReadStore extends InMemoryUserdataLocalStore {
  gate: ResponseGate = new ResponseGate();

  async readCurrent(): Promise<Blob> {
    const sections = await super.readCurrent();
    await this.gate.wait();
    return sections;
  }
}

function nick(blob: Blob | undefined): string {
  return JsonBlob.asString(JsonBlob.get(blob, 'nick'), '');
}

function remoteV6(nick: string, at: number): string {
  const blob: Blob = UserdataV6.empty();
  blob['nick'] = nick;
  const atMap: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'at'));
  if (atMap !== undefined) {
    atMap['nick'] = at;
  }
  return JsonBlob.encode(blob);
}

function postedBlob(api: FakeApi): Blob {
  const body: string = api.lastPostBody();
  const rows: Object[] | undefined = JsonBlob.asArray(JSON.parse(body) as JsonValue);
  if (rows === undefined || rows.length === 0) {
    return {};
  }
  const row: Blob | undefined = JsonBlob.asBlob(rows[0]);
  const blobText: string = JsonBlob.asString(JsonBlob.get(row, 'blob'), '');
  const decoded: Blob | undefined = UserdataV6.decode(blobText);
  return decoded !== undefined ? decoded : {};
}

export default function userdataRepositoryTest() {
  describe('UserdataRepository', () => {
    it('retired_hydration_cannot_repopulate_memory_and_anonymous_store_is_inert', 0, async () => {
      const disk = new HeldReadStore();
      const api = new FakeApi();
      await disk.writeCurrent({ 'nick': 'old-local' });
      const old = new UserdataRepository(api, disk, () => SID);
      let count = 0;
      old.onSectionsChanged(() => { count++; });
      const reading = old.hydrateFromLocal();
      await disk.gate.started;
      old.endSession();
      const signedOut = new UserdataRepository(api, disk, () => '');
      await signedOut.updateCurrent({ 'nick': 'anonymous-write' });
      await signedOut.clearLocal();
      expect((await signedOut.flush()).status).assertEqual('disabled');
      disk.gate.release();
      await reading;
      expect(nick(await disk.readCurrent())).assertEqual('old-local');
      expect(nick(old.currentSections())).assertEqual('');
      expect(count).assertEqual(0);
      expect(api.getPaths.length).assertEqual(0);
    });

    it('late_pull_after_switch_cannot_publish_or_persist_into_other_account', 0, async () => {
      const sidB = 'test-b';
      const apiA = new HeldUserdataApi();
      const apiB = new FakeApi();
      apiA.userdataBlob = remoteV6('A-only', 10);
      apiB.userdataBlob = remoteV6('B-only', 20);
      const diskA = new InMemoryUserdataLocalStore();
      const diskB = new InMemoryUserdataLocalStore();
      const a = new UserdataRepository(apiA, diskA, () => SID);
      let oldEvents = 0;
      a.onSectionsChanged(() => { oldEvents++; });
      const gate = new ResponseGate();
      apiA.getGate = gate;
      const inFlight = a.pull(true);
      await gate.started;
      a.endSession();
      const b = new UserdataRepository(apiB, diskB, () => sidB);
      let visible = '';
      b.onSectionsChanged((sections: Blob) => { visible = nick(sections); });
      await b.pull(true);
      gate.release();
      expect((await inFlight).status).assertEqual('disabled');
      expect(oldEvents).assertEqual(0);
      expect(visible).assertEqual('B-only');
      expect(nick(await b.cachedBlob())).assertEqual('B-only');
      expect(nick(await diskB.readCurrent())).assertEqual('B-only');
      expect(nick(a.currentSections())).assertEqual('');
      expect(await diskA.lastPullAt()).assertEqual(0);
      // 下一次跨端修改和手动刷新仍能收敛，接着保存只命中乙。
      apiB.userdataBlob = remoteV6('B-from-another-device', 30);
      await b.pull(true);
      expect(visible).assertEqual('B-from-another-device');
      await b.updateCurrent({ 'nick': 'B-edit' });
      expect((await b.flush()).pushed).assertTrue();
      expect(apiB.lastPostBody().indexOf('B-edit') >= 0).assertTrue();
      expect(apiB.lastPostBody().indexOf('"id":"test-b"') >= 0).assertTrue();
      expect(apiB.lastPostBody().indexOf('A-only')).assertEqual(-1);
    });

    it('renewed_sid_drops_previous_queued_get_failure_and_preserves_own_pending', 0, async () => {
      const disk = new InMemoryUserdataLocalStore();
      const oldApi = new HeldUserdataApi();
      const old = new UserdataRepository(oldApi, disk, () => SID);
      const gate = new ResponseGate();
      oldApi.getGate = gate;
      oldApi.failGets = true;
      const running = old.push(true, new Set<string>(['nick']));
      await gate.started;
      const queued = old.push(true, new Set<string>(['power']));
      old.endSession();
      // 甲退出、乙退出、甲以新角色登录；底层文件名和旧甲相同。
      const b = new UserdataRepository(new FakeApi(), new InMemoryUserdataLocalStore(), () => 'test-b');
      b.endSession();
      const newApi = new FakeApi();
      newApi.userdataBlob = remoteV6('renewed', 90);
      const fresh = new UserdataRepository(newApi, disk, () => SID);
      await fresh.pull(true);
      await disk.markPending(['tt']);
      gate.release();
      expect((await running).status).assertEqual('disabled');
      expect((await queued).status).assertEqual('disabled');
      expect(oldApi.getPaths.length).assertEqual(1);
      expect(oldApi.postBodies.length).assertEqual(0);
      expect((await disk.pendingKeys()).size).assertEqual(1);
      expect((await disk.pendingKeys()).has('tt')).assertTrue();
      expect(nick(await disk.readCache())).assertEqual('renewed');
      expect(nick(fresh.currentSections())).assertEqual('renewed');
    });

    it('late_post_success_or_failure_does_not_clear_or_add_pending_in_renewed_sid', 0, async () => {
      for (let i = 0; i < 2; i++) {
        const disk = new InMemoryUserdataLocalStore();
        const api = new HeldUserdataApi();
        api.failPosts = i === 1;
        const old = new UserdataRepository(api, disk, () => SID);
        await old.pull(true);
        await old.updateCurrent({ 'nick': 'old-post' });
        const gate = new ResponseGate();
        api.postGate = gate;
        const running = old.flush();
        await gate.started;
        old.endSession();
        const newApi = new FakeApi();
        const fresh = new UserdataRepository(newApi, disk, () => SID);
        await disk.clear();
        newApi.userdataBlob = remoteV6('new', 30);
        await fresh.pull(true);
        await disk.markPending(['tt']);
        gate.release();
        expect((await running).status).assertEqual('disabled');
        expect(nick(await fresh.cachedBlob())).assertEqual('new');
        expect(nick(await disk.readCurrent())).assertEqual('new');
        expect(await disk.pend()).assertTrue();
        expect((await disk.pendingKeys()).size).assertEqual(1);
        expect((await disk.pendingKeys()).has('tt')).assertTrue();
        await old.clearLocal();
        expect(nick(await disk.readCurrent())).assertEqual('new');
      }
    });

    it('expiry_keeps_owner_file_and_cancels_debounce_explicit_logout_clears_owner', 0, async () => {
      const disk = new InMemoryUserdataLocalStore();
      const other = new InMemoryUserdataLocalStore();
      await other.writeCurrent({ 'nick': 'untouched' });
      const api = new FakeApi();
      const old = new UserdataRepository(api, disk, () => SID, () => 1000, new UserdataSyncConfig(100, 10));
      await old.pull(true);
      await old.updateCurrent({ 'nick': 'recover-on-reauth' });
      old.endSession();
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 30); });
      expect(api.getPaths.length).assertEqual(1);
      expect(api.postBodies.length).assertEqual(0);
      const fresh = new UserdataRepository(new FakeApi(), disk, () => SID);
      await fresh.hydrateFromLocal();
      expect(nick(fresh.currentSections())).assertEqual('recover-on-reauth');
      await fresh.clearLocal();
      fresh.endSession();
      expect(nick(await disk.readCurrent())).assertEqual('');
      expect(nick(await other.readCurrent())).assertEqual('untouched');
    });

    it('pull_empty_cloud_builds_baseline_without_push', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 1000);
      const result: UserdataPullResult = await repo.pull(true);
      expect(result.ok()).assertTrue();
      expect(api.postBodies.length).assertEqual(0);
      expect(await store.lastPullAt()).assertEqual(1000);
      const base: Blob | undefined = await store.readCache();
      expect(base !== undefined).assertTrue();
    });

    it('pull_applies_remote_sections', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.userdataBlob = remoteV6('云端昵称', 500);
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 1000);
      const result: UserdataPullResult = await repo.pull(true);
      expect(result.ok()).assertTrue();
      expect(JsonBlob.asString(JsonBlob.get(repo.currentSections(), 'nick'), '')).assertEqual('云端昵称');
    });

    it('flush_pushes_dirty_section_with_new_timestamp', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.userdataBlob = remoteV6('云端', 500);
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      await repo.pull(true);
      const local: Blob = { 'nick': '本机' };
      await repo.updateCurrent(local);
      const flush: UserdataPushResult = await repo.flush();
      expect(flush.ok()).assertTrue();
      expect(flush.pushed).assertTrue();
      const blob: Blob = postedBlob(api);
      expect(JsonBlob.asString(JsonBlob.get(blob, 'nick'), '')).assertEqual('本机');
      expect(UserdataV6.atValue(blob, 'nick')).assertEqual(2000);
      expect(await store.pend()).assertFalse();
    });

    it('push_failure_marks_pending_and_retry_succeeds', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.userdataBlob = remoteV6('云端', 500);
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      await repo.pull(true);
      await repo.updateCurrent({ 'nick': '本机' });
      api.failPosts = true;
      const failed: UserdataPushResult = await repo.flush();
      expect(failed.ok()).assertFalse();
      expect(await store.pend()).assertTrue();

      api.failPosts = false;
      const retried: UserdataPushResult = await repo.flush();
      expect(retried.ok()).assertTrue();
      expect(retried.pushed).assertTrue();
      expect(await store.pend()).assertFalse();
    });

    it('push_without_baseline_and_not_forced_is_skipped', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      const result: UserdataPushResult = await repo.push(false, new Set<string>());
      expect(result.status).assertEqual('skipped');
      expect(api.postBodies.length).assertEqual(0);
    });

    it('hold_period_blocks_push', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      await store.setHoldUntil(999999);
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      const result: UserdataPushResult = await repo.push(true, new Set<string>());
      expect(result.status).assertEqual('held');
    });

    it('disabled_sync_returns_disabled', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      await store.setSyncEnabled(false);
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      const pull: UserdataPullResult = await repo.pull(true);
      expect(pull.status).assertEqual('disabled');
      const push: UserdataPushResult = await repo.push(true, new Set<string>());
      expect(push.status).assertEqual('disabled');
    });

    it('v5_cloud_is_migrated_and_pushed_back_as_v6', 0, async () => {
      const api: FakeApi = new FakeApi();
      const at: Blob = {};
      const homeTools: Object[] = ['hw', 'nt'];
      const fit: Blob = { 'sex': 'm' };
      const v5: Blob = { 'v': 5, 'homeToolsAt': 111, 'homeTools': homeTools, 'fit': fit, 'at': at };
      api.userdataBlob = JsonBlob.encode(v5);
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 2000);
      const result: UserdataPullResult = await repo.pull(true);
      expect(result.ok()).assertTrue();
      expect(result.migratedV5).assertTrue();
      expect(api.postBodies.length).assertEqual(1);
      const blob: Blob = postedBlob(api);
      expect(JsonBlob.numMs(JsonBlob.get(blob, 'v'))).assertEqual(6);
      expect(JsonBlob.numMs(JsonBlob.get(blob, 'homeToolsAt'))).assertEqual(111);
      expect(UserdataV6.atValue(blob, 'fit')).assertEqual(0);
    });

    it('pull_within_ttl_skips_network', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      let now: number = 1000;
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => now);
      await repo.pull(true);
      const getsAfterFirst: number = api.getPaths.length;
      now = 2000;
      const second: UserdataPullResult = await repo.pull(false);
      expect(second.ok()).assertTrue();
      expect(second.fresh).assertTrue();
      expect(api.getPaths.length).assertEqual(getsAfterFirst);
    });

    it('water_section_is_normalized_before_push', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 3000);
      await repo.pull(true);
      const rooms: Blob = {};
      const recs: Object[] = [];
      const oct: Blob = { 'm': '2026-10', 'r': 93.555, 'ts': 2 };
      const sep: Blob = { 'm': '2026-09', 'r': 80, 'ts': 1 };
      recs.push(oct);
      recs.push(sep);
      const room: Blob = { 'p': 5, 'recs': recs };
      rooms['1-16---303'] = room;
      const waterSection: Blob = { 'rooms': rooms };
      const update: Blob = { 'water': waterSection };
      await repo.updateCurrent(update);
      const flush: UserdataPushResult = await repo.flush();
      expect(flush.ok()).assertTrue();
      const blob: Blob = postedBlob(api);
      const water: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'water'));
      const outRooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(water, 'rooms'));
      const kept: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(outRooms, '1-16---303'));
      expect(JsonBlob.asNumber(JsonBlob.get(kept, 'p'), 0)).assertEqual(4);
      const outRecs: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(kept, 'recs'));
      if (outRecs !== undefined) {
        expect(outRecs.length).assertEqual(2);
        const first: Blob | undefined = JsonBlob.asBlob(outRecs[0]);
        expect(JsonBlob.asString(JsonBlob.get(first, 'm'), '')).assertEqual('2026-09');
      }
    });

    it('pull_uses_full_fixture_blob_without_error', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.userdataBlob = USERDATA_V6_WEB;
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => SID, () => 4000);
      const result: UserdataPullResult = await repo.pull(true);
      expect(result.ok()).assertTrue();
      const base: Blob | undefined = await store.readCache();
      expect(base !== undefined).assertTrue();
      if (base !== undefined) {
        expect(UserdataV6.atValue(base, 'homeTools')).assertEqual(1762300000000);
      }
    });
  });
}
