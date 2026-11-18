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
      const ok = await AccountBindingRepository.login('openid-12345678', api, () => 1000);
      expect(ok.reason).assertEqual('');
      expect(ok.session !== undefined).assertTrue();
      if (ok.session !== undefined) {
        expect(ok.session.sid).assertEqual('3260799999');
        expect(ok.session.token).assertEqual('t0');
        expect(ok.session.issuedAt).assertEqual(1000);
        expect(ok.session.expiresAt).assertEqual(0);
        expect(ok.session.isLikelyValid(2000)).assertTrue();
      }

      api.hwLoginBody = '{"ok":false,"reason":"该华为账号尚未绑定学号"}';
      const unbound = await AccountBindingRepository.login('openid-12345678', api);
      expect(unbound.session === undefined).assertTrue();
      expect(unbound.reason).assertEqual('该华为账号尚未绑定学号');

      const empty = await AccountBindingRepository.login('', api);
      expect(empty.session === undefined).assertTrue();
      const blank = await AccountBindingRepository.login('   ', api);
      expect(blank.session === undefined).assertTrue();
    });

    it('login_validates_and_maps_fields', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.hwLoginBody = '{"ok":true,"sid":" 3260799999 ","name":" 测试账号 ",'
        + '"token":"t9","role":"班长","badge":"B","is_admin":true}';
      const admin = await AccountBindingRepository.login('  openid-x  ', api, () => 5000);
      expect(admin.session !== undefined).assertTrue();
      if (admin.session !== undefined) {
        expect(admin.session.sid).assertEqual('3260799999');
        expect(admin.session.name).assertEqual('测试账号');
        expect(admin.session.role).assertEqual('班长');
        expect(admin.session.badge).assertEqual('B');
        expect(admin.session.isAdmin).assertTrue();
      }

      api.hwLoginBody = '{"ok":true,"sid":"3260799999","token":"   "}';
      const noToken = await AccountBindingRepository.login('openid-x', api);
      expect(noToken.session === undefined).assertTrue();
      expect(noToken.reason.indexOf('身份凭证') >= 0).assertTrue();

      api.hwLoginBody = '{"ok":true,"sid":"  ","token":"t9"}';
      const noSid = await AccountBindingRepository.login('openid-x', api);
      expect(noSid.session === undefined).assertTrue();
      expect(noSid.reason.indexOf('学号') >= 0).assertTrue();

      api.hwLoginBody = 'not-json';
      const bad = await AccountBindingRepository.login('openid-x', api);
      expect(bad.session === undefined).assertTrue();
      expect(bad.reason).assertEqual('登录服务返回异常');

      api.hwLoginBody = '{"ok":true,"sid":"3260799999"}';
      const missingToken = await AccountBindingRepository.login('openid-x', api);
      expect(missingToken.session === undefined).assertTrue();

      api.failPosts = true;
      const failed = await AccountBindingRepository.login('openid-x', api);
      expect(failed.session === undefined).assertTrue();
      expect(failed.reason.length > 0).assertTrue();
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
