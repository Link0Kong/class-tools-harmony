import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { MarkKind, MarkRow, MarksSnapshot } from '../main/ets/data/marks/Marks';
import {
  InMemoryMarksLocalStore,
  MarksRefreshResult,
  MarksRepository,
  MarksUpdateResult,
  parseRows
} from '../main/ets/data/marks/MarksRepository';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';

const SID: string = '3260799999';

function rowJson(ref: string, kind: string, value: boolean): Blob {
  const row: Blob = {
    'id': SID + '|' + kind + '|' + ref,
    'seat': SID,
    'kind': kind,
    'ref': ref,
    'val': value,
    'ts': 1
  };
  return row;
}

function marksBody(rows: Blob[]): string {
  const arr: Object[] = [];
  for (let i = 0; i < rows.length; i++) {
    arr.push(rows[i]);
  }
  return JSON.stringify(arr);
}

export default function marksRepositoryTest() {
  describe('MarksSnapshot', () => {
    it('replace_rows_collects_only_true', 0, () => {
      const snapshot: MarksSnapshot = new MarksSnapshot();
      const rows: MarkRow[] = [
        new MarkRow('a', SID, 'hw', 'hw_1', true, 1),
        new MarkRow('b', SID, 'hw', 'hw_2', false, 2),
        new MarkRow('c', SID, 'nt', 'nt_1', true, 3),
        new MarkRow('d', SID, 'ntdone', 'nt_2', true, 4),
        new MarkRow('e', SID, 'unknown', 'x', true, 5)
      ];
      const next: MarksSnapshot = snapshot.replaceRows(rows);
      expect(next.hwDone.has('hw_1')).assertTrue();
      expect(next.hwDone.has('hw_2')).assertFalse();
      expect(next.ntPin.has('nt_1')).assertTrue();
      expect(next.ntDone.has('nt_2')).assertTrue();
      expect(next.isDone(MarkKind.HW, 'hw_1')).assertTrue();
      expect(next.isDone(MarkKind.NT_DONE, 'nt_2')).assertTrue();
      expect(next.counts()).assertEqual(3);
    });

    it('with_false_removes_and_keeps_immutability', 0, () => {
      const snapshot: MarksSnapshot = new MarksSnapshot().with(MarkKind.HW, 'hw_1', true);
      const next: MarksSnapshot = snapshot.with(MarkKind.HW, 'hw_1', false);
      expect(snapshot.isDone(MarkKind.HW, 'hw_1')).assertTrue();
      expect(next.isDone(MarkKind.HW, 'hw_1')).assertFalse();
    });

    it('apply_pending_overrides_remote', 0, () => {
      const remote: MarkRow[] = [new MarkRow('a', SID, 'hw', 'hw_1', false, 1)];
      const pending: MarkRow[] = [new MarkRow('a2', SID, 'hw', 'hw_1', true, 2)];
      const snapshot: MarksSnapshot = new MarksSnapshot().replaceRows(remote).applyPending(pending);
      expect(snapshot.isDone(MarkKind.HW, 'hw_1')).assertTrue();
    });
  });

  describe('MarksRepository', () => {
    it('refresh_parses_rows_and_caches', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.marksBody = marksBody([rowJson('hw_1', 'hw', true), rowJson('nt_1', 'nt', true)]);
      const repo: MarksRepository = new MarksRepository(api, () => SID, new InMemoryMarksLocalStore(), () => 1000, 120000);
      const result: MarksRefreshResult = await repo.refresh(true);
      expect(result.ok).assertTrue();
      expect(result.snapshot.hwDone.has('hw_1')).assertTrue();
      expect(result.snapshot.ntPin.has('nt_1')).assertTrue();
      expect(api.getPaths[0].indexOf('seat=eq.' + SID) >= 0).assertTrue();
    });

    it('refresh_within_ttl_skips_network', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.marksBody = marksBody([]);
      let now: number = 1000;
      const repo: MarksRepository = new MarksRepository(api, () => SID, new InMemoryMarksLocalStore(), () => now, 120000);
      await repo.refresh(true);
      const count: number = api.getPaths.length;
      now = 2000;
      const second: MarksRefreshResult = await repo.refresh(false);
      expect(second.ok).assertTrue();
      expect(api.getPaths.length).assertEqual(count);
    });

    it('set_mark_is_optimistic_and_posts_val', 0, async () => {
      const api: FakeApi = new FakeApi();
      const repo: MarksRepository = new MarksRepository(api, () => SID, new InMemoryMarksLocalStore(), () => 1000, 120000);
      const result: MarksUpdateResult = await repo.setMark(MarkKind.HW, 'hw_9', true);
      expect(result.ok).assertTrue();
      expect(repo.marks().isDone(MarkKind.HW, 'hw_9')).assertTrue();
      const body: string = api.lastPostBody();
      expect(body.indexOf('"val":true') >= 0).assertTrue();
      expect(body.indexOf('hw_9') >= 0).assertTrue();
      expect(await repo.pendingCount()).assertEqual(0);
    });

    it('failed_mark_is_pending_and_flush_clears', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.failPosts = true;
      const repo: MarksRepository = new MarksRepository(api, () => SID, new InMemoryMarksLocalStore(), () => 1000, 120000);
      const result: MarksUpdateResult = await repo.setMark(MarkKind.NT_DONE, 'nt_5', true);
      expect(result.ok).assertFalse();
      expect(repo.marks().isDone(MarkKind.NT_DONE, 'nt_5')).assertTrue();
      expect(await repo.pendingCount()).assertEqual(1);

      api.failPosts = false;
      const flushed: number = await repo.flushPending();
      expect(flushed).assertEqual(1);
      expect(await repo.pendingCount()).assertEqual(0);
    });

    it('invalid_marks_response_is_parse_error', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.marksBody = '{"not":"array"}';
      const repo: MarksRepository = new MarksRepository(api, () => SID, new InMemoryMarksLocalStore(), () => 1000, 120000);
      const result: MarksRefreshResult = await repo.refresh(true);
      expect(result.ok).assertFalse();
      expect(result.error !== undefined).assertTrue();
    });

    it('parse_rows_skips_bad_items', 0, () => {
      const good: Blob = rowJson('hw_1', 'hw', true);
      const noRef: Blob = { 'id': 'x', 'seat': SID, 'kind': 'hw', 'ref': '', 'val': true };
      const arr: Object[] = [good, noRef, 'junk'];
      const rows: MarkRow[] | undefined = parseRows(JSON.stringify(arr));
      expect(rows !== undefined).assertTrue();
      if (rows !== undefined) {
        expect(rows.length).assertEqual(1);
        expect(rows[0].ref).assertEqual('hw_1');
      }
      expect(parseRows('not-json') === undefined).assertTrue();
    });

    it('model_roundtrip_preserves_fields', 0, () => {
      const row: MarkRow = new MarkRow('id1', SID, 'hw', 'hw_1', true, 123);
      const back: MarkRow | undefined = MarkRow.fromJson(row.toJson());
      expect(back !== undefined).assertTrue();
      if (back !== undefined) {
        expect(back.value).assertTrue();
        expect(back.ts).assertEqual(123);
        expect(back.id).assertEqual('id1');
        expect(JsonBlob.asBoolean(JsonBlob.get(row.toJson(), 'val'), false)).assertTrue();
      }
    });
  });
}
