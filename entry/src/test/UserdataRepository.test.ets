import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { InMemoryUserdataLocalStore } from '../main/ets/data/sync/UserdataLocalStore';
import { UserdataRepository, UserdataPullResult, UserdataPushResult } from '../main/ets/data/sync/UserdataRepository';
import { UserdataV6 } from '../main/ets/data/sync/UserdataV6';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';
import { USERDATA_V6_WEB } from './fixtures/SyncFixtures';

const SID: string = '3260799999';

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
      rooms['1-16---305'] = room;
      const waterSection: Blob = { 'rooms': rooms };
      const update: Blob = { 'water': waterSection };
      await repo.updateCurrent(update);
      const flush: UserdataPushResult = await repo.flush();
      expect(flush.ok()).assertTrue();
      const blob: Blob = postedBlob(api);
      const water: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'water'));
      const outRooms: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(water, 'rooms'));
      const kept: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(outRooms, '1-16---305'));
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
