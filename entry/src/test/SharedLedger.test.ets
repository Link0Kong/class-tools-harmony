import { describe, it, expect } from '@ohos/hypium';
import { Api } from '../main/ets/data/net/Api';
import { ApiError, ApiErrorKind, ApiResult } from '../main/ets/data/net/ApiResult';
import { SharedLedger, LedgerData } from '../main/ets/features/water/SharedLedger';
import { Blob } from '../main/ets/data/sync/JsonBlob';

const ROOM: string = 'synthetic-room';
class WaterServer {
  rows: Blob[] = [];
  persons: Blob[] = [];
  writes: number = 0;
}
class TestWaterApi implements Api {
  sid: string;
  server: WaterServer;
  offline: boolean = false;
  denied: boolean = false;
  failPeople: boolean = false;
  loseWrite: boolean = false;
  constructor(sid: string, server: WaterServer) { this.sid = sid; this.server = server; }
  failed(): ApiResult {
    return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, '', 'fake offline'));
  }
  async get(path: string): Promise<ApiResult> {
    if (this.offline || (this.failPeople && path.startsWith('water_room'))) return this.failed();
    if (path.startsWith('water_room')) return ApiResult.success(JSON.stringify(this.server.persons));
    const after = path.split('month=gt.')[1] || '';
    return ApiResult.success(JSON.stringify(this.server.rows.filter((r: Blob) => String(r['month']) > after).slice(0, 1)));
  }
  async post(path: string, body: string): Promise<ApiResult> {
    if (this.offline) return this.failed();
    if (path.startsWith('rpc/')) {
      const who: Blob = { 'sid': this.denied ? '' : this.sid };
      return ApiResult.success(JSON.stringify(who));
    }
    this.server.writes++;
    const row = JSON.parse(body) as Blob;
    if (path.startsWith('water_room')) this.server.persons = [row];
    else this.server.rows.push(row);
    if (this.loseWrite) this.offline = true;
    return this.offline ? this.failed() : ApiResult.success('[]');
  }
  async patch(path: string, body: string): Promise<ApiResult> {
    this.server.writes++;
    if (path.startsWith('water_room')) this.server.persons = [JSON.parse(body) as Blob];
    else {
      const updated = JSON.parse(body) as Blob;
      this.server.rows = this.server.rows.map((r: Blob) => r['month'] === updated['month'] ? updated : r);
    }
    return ApiResult.success('[]');
  }
  async delete(path: string): Promise<ApiResult> {
    this.server.writes++;
    this.server.rows = this.server.rows.filter((r: Blob) => path.indexOf('month=eq.' + String(r['month'])) < 0);
    return ApiResult.success('[]');
  }
}
function make(api: TestWaterApi, state: LedgerData = new LedgerData()): SharedLedger {
  return new SharedLedger(api, api.sid, ROOM, state, () => true, (v: LedgerData) => {});
}
export default function sharedLedgerTest() {
  describe('SharedWaterLedger', () => {
    it('two_members_read_write_delete_no_resurrection', 0, async () => {
      const server = new WaterServer();
      const a = make(new TestWaterApi('test-A', server));
      const b = make(new TestWaterApi('test-B', server));
      await a.refresh();
      a.prepare('persons', '', 0, 3);
      await a.submit();
      a.prepare('save', '2030-01', 12.34, 3);
      await a.submit();
      await b.refresh();
      expect(b.roomState().persons).assertEqual(3);
      expect(b.roomState().records[0].reading).assertEqual(12.34);
      b.prepare('save', '2030-01', 14, 3);
      a.prepare('delete', '2030-01', 0, 3);
      await a.submit();
      const writes = server.writes;
      await b.submit();
      expect(server.writes).assertEqual(writes);
      expect(b.roomState().records.length).assertEqual(0);
      expect(b.data.pending !== null).assertTrue();
      await b.submit(true);
      expect(server.rows.length).assertEqual(1);
    });
    it('lost_reply_waits_for_explicit_decision', 0, async () => {
      const server = new WaterServer();
      const api = new TestWaterApi('test-A', server);
      const a = make(api);
      await a.refresh();
      a.prepare('save', '2030-02', 20.5, 3);
      api.loseWrite = true;
      await a.submit();
      expect(a.data.pending !== null).assertTrue();
      api.offline = false;
      api.loseWrite = false;
      server.rows = [];
      const resumed = make(api, JSON.parse(JSON.stringify(a.data)) as LedgerData);
      await resumed.submit();
      expect(server.writes).assertEqual(1);
      expect(resumed.data.pending !== null).assertTrue();
      resumed.discard();
      await resumed.refresh();
      expect(server.writes).assertEqual(1);
    });
    it('independent_people_pages_denial_and_session_generation', 0, async () => {
      const server = new WaterServer();
      const api = new TestWaterApi('test-B', server);
      const a = make(api);
      server.rows = [{ 'roomverify': ROOM, 'month': '2030-01', 'reading': '12.34', 'persons': 4 },
        { 'roomverify': ROOM, 'month': '2030-02', 'reading': 19, 'persons': 3 }];
      api.failPeople = true;
      await a.refresh();
      expect(a.roomState().records.length).assertEqual(2);
      expect(a.peopleFresh).assertFalse();
      api.failPeople = false;
      server.persons = [{ 'roomverify': ROOM, 'persons': 7 }];
      await a.refresh();
      expect(a.peopleFresh).assertFalse();
      api.denied = true;
      await a.refresh();
      expect(a.data.denied).assertTrue();
      expect(a.roomState().records.length).assertEqual(0);
      let active = true;
      let writes = 0;
      const scoped = new SharedLedger(api, api.sid, ROOM, new LedgerData(), () => active, (d: LedgerData) => { writes++; });
      const late = scoped.refresh();
      active = false;
      try { await late; } catch (e) {}
      expect(writes).assertEqual(0);
    });
    it('offline_known_absence_and_unknown_baseline', 0, async () => {
      const api = new TestWaterApi('test-A', new WaterServer());
      const a = make(api);
      await a.refresh();
      api.offline = true;
      a.prepare('save', '2030-02', 21, 4);
      await a.submit();
      api.offline = false;
      await a.submit();
      expect(api.server.writes).assertEqual(1);
      const fresh = make(api);
      fresh.prepare('save', '2030-03', 23, 4);
      await fresh.submit();
      expect(api.server.writes).assertEqual(1);
      expect(fresh.data.pending !== null).assertTrue();
    });
  });
}
