import { describe, it, expect } from '@ohos/hypium';
import { Session } from '../main/ets/data/session/Session';

export default function localUnitTest() {
  describe('SessionTest', () => {
    it('maskedSid_hides_middle', 0, () => {
      const s: Session = new Session('3260799999', '测试账号', 'tok');
      expect(s.maskedSid()).assertEqual('32***99');
    });

    it('isLikelyValid_keeps_login_forever', 0, () => {
      const now: number = 1700000000000;
      const s: Session = new Session('3260799999', '测试账号', 'tok');
      s.issuedAt = now;
      s.expiresAt = now + 1000;
      expect(s.isLikelyValid(now + 10)).assertTrue();
      expect(s.isLikelyValid(now + 5000)).assertTrue();
      expect(s.isLikelyValid(now + 3650 * 24 * 60 * 60 * 1000)).assertTrue();
      const empty: Session = new Session('3260799999', '测试账号', '');
      expect(empty.isLikelyValid(now)).assertFalse();
    });

    it('json_roundtrip', 0, () => {
      const s: Session = new Session('3260799999', '测试账号', 'tok');
      s.isAdmin = true;
      s.role = '班长';
      const back: Session | undefined = Session.fromJson(s.toJson());
      expect(back !== undefined).assertTrue();
      expect(back!.name).assertEqual('测试账号');
      expect(back!.isAdmin).assertTrue();
    });
  });
}
