import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { formatSlot, InMemoryVisitsStore, VisitsReporter } from '../main/ets/data/visits/VisitsReporter';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';

const SID: string = '3260799999';

function payload(api: FakeApi): Blob {
  const rows: Object[] | undefined = JsonBlob.asArray(JSON.parse(api.lastPostBody()) as JsonValue);
  if (rows === undefined || rows.length === 0) {
    return {};
  }
  const row: Blob | undefined = JsonBlob.asBlob(rows[0]);
  return row !== undefined ? row : {};
}

export default function visitsTest() {
  describe('VisitsReporter', () => {
    it('slot_format_is_yyyy_mm_dd_hh', 0, () => {
      const slot: string = formatSlot(new Date(2026, 10, 14, 9, 30, 0));
      expect(slot).assertEqual('2026-11-14-09');
    });

    it('reports_once_per_slot', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryVisitsStore = new InMemoryVisitsStore('aabbccddeeff0011');
      const reporter: VisitsReporter = new VisitsReporter(api, store, () => SID, () => '测试账号',
        () => new Date(2026, 10, 14, 9, 30, 0).getTime());
      const first: boolean = await reporter.reportOnce();
      expect(first).assertTrue();
      const second: boolean = await reporter.reportOnce();
      expect(second).assertFalse();
      expect(api.postPaths.length).assertEqual(1);
      expect(api.postPaths[0]).assertEqual('visits');
      const row: Blob = payload(api);
      expect(JsonBlob.asString(JsonBlob.get(row, 'slot'), '')).assertEqual('2026-11-14-09');
      expect(JsonBlob.asString(JsonBlob.get(row, 'sid'), '')).assertEqual(SID);
      expect(JsonBlob.asString(JsonBlob.get(row, 'did'), '')).assertEqual('aabbccddeeff0011');
    });

    it('new_hour_reports_again', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryVisitsStore = new InMemoryVisitsStore('aabbccddeeff0011');
      let now: number = new Date(2026, 10, 14, 9, 30, 0).getTime();
      const reporter: VisitsReporter = new VisitsReporter(api, store, () => SID, () => '测试账号', () => now);
      await reporter.reportOnce();
      now = new Date(2026, 10, 14, 10, 5, 0).getTime();
      const second: boolean = await reporter.reportOnce();
      expect(second).assertTrue();
      expect(api.postPaths.length).assertEqual(2);
    });

    it('failure_does_not_mark_slot', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.failPosts = true;
      const store: InMemoryVisitsStore = new InMemoryVisitsStore('aabbccddeeff0011');
      const reporter: VisitsReporter = new VisitsReporter(api, store, () => SID, () => '测试账号',
        () => new Date(2026, 10, 14, 9, 30, 0).getTime());
      const failed: boolean = await reporter.reportOnce();
      expect(failed).assertFalse();
      api.failPosts = false;
      const retried: boolean = await reporter.reportOnce();
      expect(retried).assertTrue();
    });

    it('no_sid_skips_report', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryVisitsStore = new InMemoryVisitsStore();
      const reporter: VisitsReporter = new VisitsReporter(api, store, () => '', () => '', () => 1000);
      expect(await reporter.reportOnce()).assertFalse();
      expect(api.postPaths.length).assertEqual(0);
    });
  });
}
