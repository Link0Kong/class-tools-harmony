import { describe, it, expect } from '@ohos/hypium';
import { TimetableLoginRepository, TtLoginEnqueue, TtLoginStatus } from '../main/ets/data/timetable/TimetableLoginRepository';
import { FakeApi } from './support/FakeApi';

export default function timetableLoginTest() {
  describe('TimetableLoginRepository', () => {
    it('enqueue_and_status', 0, async () => {
      const api: FakeApi = new FakeApi();
      const repo: TimetableLoginRepository = new TimetableLoginRepository(api);
      const empty = await repo.enqueue('');
      expect(empty.ok).assertFalse();
      expect(empty.message).assertEqual('请输入教务密码');

      const enqueue: TtLoginEnqueue = await repo.enqueue('secret');
      expect(enqueue.ok).assertTrue();
      expect(enqueue.jobId).assertEqual('job1');
      expect(api.postPaths[0]).assertEqual('rpc/tt_login_enqueue');
      expect(api.postBodies[0].indexOf('"p_platform":"android"') > 0).assertTrue();
      expect(api.postBodies[0].indexOf('secret') > 0).assertTrue();

      api.ttLoginEnqueueBody = '{"ok":false,"reason":"拒绝"}';
      const rejected = await repo.enqueue('x');
      expect(rejected.ok).assertFalse();
      expect(rejected.message).assertEqual('拒绝');

      api.ttLoginStatusBody = '{"ok":true,"status":"running","finished":false}';
      const running = await repo.status('job1');
      expect(running.ok).assertTrue();
      expect(running.finished).assertFalse();
      expect(running.snapshot === undefined).assertTrue();

      api.ttLoginStatusBody = '{"ok":true,"status":"done","finished":true,"result":{"t":"2026-09-01","c":[{"name":"高等数学","teacher":"张老师","room":"A101","day":0,"start":1,"end":2,"weeks":"1-16","parity":"all"}]}}';
      const done = await repo.status('job1');
      expect(done.ok).assertTrue();
      expect(done.finished).assertTrue();
      expect(done.snapshot !== undefined).assertTrue();
      expect(done.raw !== undefined).assertTrue();
      if (done.snapshot !== undefined) {
        expect(done.snapshot.c.length).assertEqual(1);
      }

      api.failPosts = true;
      const failed = await repo.enqueue('x');
      expect(failed.ok).assertFalse();
    });
  });
}
