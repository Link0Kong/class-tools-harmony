import { describe, it, expect } from '@ohos/hypium';
import { AccountBindingRepository, BindItem } from '../main/ets/data/account/AccountBindingRepository';
import { FakeApi } from './support/FakeApi';

export default function accountBindingTest() {
  describe('AccountBinding', () => {
    it('masked_and_empty', 0, () => {
      const item: BindItem = new BindItem();
      item.openId = 'abcdefghijklmnop';
      expect(item.masked()).assertEqual('abcd…mnop');
      const short: BindItem = new BindItem();
      short.openId = 'short';
      expect(short.masked()).assertEqual('已绑定账号');
    });

    it('bind_ok_and_reason', 0, async () => {
      const api: FakeApi = new FakeApi();
      const err: string = await AccountBindingRepository.bind('openid-12345678', 'phone', api);
      expect(err).assertEqual('');
      expect(api.postPaths[0]).assertEqual('rpc/hw_bind');
      expect(api.postBodies[0].indexOf('openid-12345678') > 0).assertTrue();

      const empty: string = await AccountBindingRepository.bind('', 'phone', api);
      expect(empty.length > 0).assertTrue();

      api.hwActionBody = '{"ok":false,"reason":"一个学号最多绑定 3 个华为账号"}';
      const limited: string = await AccountBindingRepository.bind('openid-99999999', 'phone', api);
      expect(limited).assertEqual('一个学号最多绑定 3 个华为账号');

      api.failPosts = true;
      const failed: string = await AccountBindingRepository.bind('openid-99999999', 'phone', api);
      expect(failed.length > 0).assertTrue();
    });

    it('list_parse', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.hwListBody = '[{"open_id":"abcdefgh12345678","device":"watch","created_at":"2026-11-15T20:00:00+08:00"}]';
      const list: BindItem[] = await AccountBindingRepository.list(api);
      expect(list.length).assertEqual(1);
      expect(list[0].device).assertEqual('watch');
      expect(list[0].masked()).assertEqual('abcd…5678');

      api.hwListBody = 'not-json';
      const bad: BindItem[] = await AccountBindingRepository.list(api);
      expect(bad.length).assertEqual(0);
    });

    it('login_session_and_reason', 0, async () => {
      const api: FakeApi = new FakeApi();
      const ok = await AccountBindingRepository.login('openid-12345678', api);
      expect(ok.reason).assertEqual('');
      expect(ok.session !== undefined).assertTrue();
      if (ok.session !== undefined) {
        expect(ok.session.sid).assertEqual('3260799999');
        expect(ok.session.token).assertEqual('t0');
      }

      api.hwLoginBody = '{"ok":false,"reason":"该华为账号尚未绑定学号"}';
      const unbound = await AccountBindingRepository.login('openid-12345678', api);
      expect(unbound.session === undefined).assertTrue();
      expect(unbound.reason).assertEqual('该华为账号尚未绑定学号');

      const empty = await AccountBindingRepository.login('', api);
      expect(empty.session === undefined).assertTrue();
    });

    it('unbind', 0, async () => {
      const api: FakeApi = new FakeApi();
      expect(await AccountBindingRepository.unbind('abcdefgh12345678', api)).assertTrue();
      api.hwActionBody = '{"ok":false}';
      expect(await AccountBindingRepository.unbind('abcdefgh12345678', api)).assertFalse();
      api.failPosts = true;
      expect(await AccountBindingRepository.unbind('abcdefgh12345678', api)).assertFalse();
    });
  });
}
