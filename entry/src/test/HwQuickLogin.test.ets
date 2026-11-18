import { describe, it, expect } from '@ohos/hypium';
import { Session } from '../main/ets/data/session/Session';
import { HwLoginResult } from '../main/ets/data/account/AccountBindingRepository';
import { HwQuickLoginDeps, HwQuickLoginFlow, HwQuickLoginResult } from '../main/ets/features/account/HwQuickLogin';

function sessionOf(token: string, sid: string): Session {
  return new Session(sid, '测试账号', token);
}

function successLogin(token: string, sid: string): HwLoginResult {
  const r: HwLoginResult = new HwLoginResult();
  r.session = sessionOf(token, sid);
  return r;
}

function failureLogin(reason: string): HwLoginResult {
  const r: HwLoginResult = new HwLoginResult();
  r.reason = reason;
  return r;
}

function baseDeps(): HwQuickLoginDeps {
  const deps: HwQuickLoginDeps = new HwQuickLoginDeps();
  deps.openId = () => Promise.resolve('openid-1');
  deps.login = (id: string) => Promise.resolve(successLogin('token-1', '3260799999'));
  deps.save = (s: Session) => Promise.resolve();
  deps.describeError = (e: Object) => '华为账号登录失败';
  return deps;
}

export default function hwQuickLoginTest() {
  describe('HwQuickLoginFlow', () => {
    it('success_trims_openid_and_saves_once', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      let seen: string = '';
      let saves: number = 0;
      deps.openId = () => Promise.resolve('  openid-1  ');
      deps.login = (id: string) => {
        seen = id;
        return Promise.resolve(successLogin('token-1', '3260799999'));
      };
      deps.save = (s: Session) => {
        saves += 1;
        return Promise.resolve();
      };
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertTrue();
      expect(out.session !== undefined).assertTrue();
      expect(seen).assertEqual('openid-1');
      expect(saves).assertEqual(1);
    });

    it('provider_cancel_is_not_manual_fallback', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.openId = () => Promise.reject(new Error('cancel'));
      deps.describeError = (e: Object) => '已取消华为账号授权';
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.cancelled).assertTrue();
      expect(out.fallbackManual).assertFalse();
      expect(out.message).assertEqual('已取消华为账号授权');
    });

    it('provider_error_falls_back_to_manual', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.openId = () => Promise.reject(new Error('not logged in'));
      deps.describeError = (e: Object) => '未登录华为账号';
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.cancelled).assertFalse();
      expect(out.fallbackManual).assertTrue();
      expect(out.message).assertEqual('未登录华为账号');
    });

    it('empty_openid_does_not_call_login', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      let called: boolean = false;
      deps.openId = () => Promise.resolve('   ');
      deps.login = (id: string) => {
        called = true;
        return Promise.resolve(successLogin('t', 's'));
      };
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.fallbackManual).assertTrue();
      expect(called).assertFalse();
      expect(out.message.indexOf('华为账号标识') >= 0).assertTrue();
    });

    it('unbound_account_returns_reason', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.login = (id: string) => Promise.resolve(failureLogin('该华为账号尚未绑定学号'));
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.fallbackManual).assertTrue();
      expect(out.message).assertEqual('该华为账号尚未绑定学号');
    });

    it('empty_reason_uses_default_message', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.login = (id: string) => Promise.resolve(failureLogin(''));
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.message).assertEqual('该华为账号尚未绑定学号');
    });

    it('rejects_empty_token_or_sid', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.login = (id: string) => Promise.resolve(successLogin('   ', '3260799999'));
      let out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.message.indexOf('身份凭证') >= 0).assertTrue();

      deps.login = (id: string) => Promise.resolve(successLogin('token-1', '  '));
      out = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.message.indexOf('学号') >= 0).assertTrue();
    });

    it('login_throw_is_handled', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.login = (id: string) => Promise.reject(new Error('network'));
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.fallbackManual).assertTrue();
      expect(out.message).assertEqual('登录请求失败，请稍后重试');
    });

    it('save_throw_does_not_return_session', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.save = (s: Session) => Promise.reject(new Error('io'));
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.ok).assertFalse();
      expect(out.session === undefined).assertTrue();
      expect(out.message.indexOf('保存本机会话失败') >= 0).assertTrue();
    });

    it('token_never_appears_in_failure_message', 0, async () => {
      const deps: HwQuickLoginDeps = baseDeps();
      deps.login = (id: string) => Promise.resolve(successLogin('secret-token', '3260799999'));
      deps.save = (s: Session) => Promise.reject(new Error('io'));
      const out: HwQuickLoginResult = await HwQuickLoginFlow.run(deps);
      expect(out.message.indexOf('secret-token') < 0).assertTrue();
    });
  });
}
