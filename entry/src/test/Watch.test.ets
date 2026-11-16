import { describe, it, expect } from '@ohos/hypium';
import { WatchLogic } from '../main/ets/features/watch/WatchLogic';

export default function watchTest() {
  describe('WatchLogic', () => {
    it('countdown_and_clock', 0, () => {
      const now: number = new Date(2026, 10, 15, 8, 0).getTime();
      const at: number = new Date(2026, 10, 15, 8, 10).getTime();
      expect(WatchLogic.minutesUntil(at, now)).assertEqual(10);
      expect(WatchLogic.countdownText(at, now)).assertEqual('还有 10 分钟');
      expect(WatchLogic.countdownText(now - 60000, now)).assertEqual('已开始');
      const far: number = new Date(2026, 10, 15, 10, 30).getTime();
      expect(WatchLogic.countdownText(far, now)).assertEqual('还有 2 小时 30 分');
      expect(WatchLogic.clock(new Date(2026, 10, 15, 9, 5).getTime())).assertEqual('09:05');
    });

    it('due_and_short', 0, () => {
      const now: number = new Date(2026, 10, 15, 12, 0).getTime();
      expect(WatchLogic.dueText('2026-11-15', '18:00', now)).assertEqual('今天 18:00 截止');
      expect(WatchLogic.dueText('2026-11-16', '09:00', now)).assertEqual('明天 09:00 截止');
      expect(WatchLogic.dueText('2026-11-20', '23:59', now)).assertEqual('2026-11-20 23:59 截止');
      expect(WatchLogic.dueText('', '18:00', now)).assertEqual('18:00 截止');
      expect(WatchLogic.short('一二三四五六七八九十', 5)).assertEqual('一二三四…');
      expect(WatchLogic.short('短', 5)).assertEqual('短');
      expect(WatchLogic.offline(false)).assertTrue();
      expect(WatchLogic.offline(true)).assertFalse();
    });
  });
}
