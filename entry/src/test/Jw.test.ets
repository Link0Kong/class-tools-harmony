import { describe, it, expect } from '@ohos/hypium';
import { JW_URL, JwCardDef, JwEntries, JwLogic } from '../main/ets/features/jw/JwModels';

export default function jwTest() {
  describe('JwEntries', () => {
    it('official_url_matches_web', 0, () => {
      expect(JwEntries.url()).assertEqual('http://210.34.74.77/sso.jsp');
      expect(JW_URL.indexOf('http://') === 0).assertTrue();
    });

    it('four_cards', 0, () => {
      expect(JwEntries.CARDS.length).assertEqual(4);
      expect(JwEntries.cardNames().join(',')).assertEqual('成绩,考试,选课,公告');
      const grades: JwCardDef = JwEntries.CARDS[0];
      expect(grades.id).assertEqual('grades');
      expect(grades.hint.indexOf('成绩') >= 0).assertTrue();
    });
  });

  describe('JwLogic', () => {
    it('week_text', 0, () => {
      expect(JwLogic.weekText(13, true)).assertEqual('第 13 周');
      expect(JwLogic.weekText(undefined, true)).assertEqual('学期未开始');
      expect(JwLogic.weekText(undefined, false)).assertEqual('—');
      expect(JwLogic.weekText(0, true)).assertEqual('学期未开始');
    });

    it('next_text', 0, () => {
      expect(JwLogic.nextText('周一', '11-23', '08:10', '思想道德与法治'))
        .assertEqual('周一 11-23 08:10 思想道德与法治');
      expect(JwLogic.nextText('今天', '', '14:30', '英语1')).assertEqual('今天 14:30 英语1');
      expect(JwLogic.nextText('', '', '', '')).assertEqual('暂无后续课程');
    });

    it('today_text', 0, () => {
      expect(JwLogic.todayText(0, '', '')).assertEqual('今天没有课');
      expect(JwLogic.todayText(4, '14:30', '英语1')).assertEqual('4 节 · 下一节 14:30 英语1');
      expect(JwLogic.todayText(2, '', '')).assertEqual('2 节 · 今日已结束');
    });

    it('login_hint_no_password_storage', 0, () => {
      const hint: string = JwLogic.loginHint();
      expect(hint.indexOf('保存密码') > 0).assertTrue();
      expect(hint.indexOf('浏览器') > 0).assertTrue();
    });
  });
}
