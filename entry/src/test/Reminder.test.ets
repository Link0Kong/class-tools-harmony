import { describe, it, expect } from '@ohos/hypium';
import { HomeworkRow } from '../main/ets/data/homework/HomeworkModels';
import { ReminderPlanner, ReminderPrefs } from '../main/ets/features/reminder/ReminderModels';
import { ReminderRecord, ReminderStore } from '../main/ets/data/reminder/ReminderStore';

function row(subject: string, date: string, time: string): HomeworkRow {
  const item: HomeworkRow = new HomeworkRow();
  item.id = 'hw1';
  item.subject = subject;
  item.content = subject + ' 的内容\n第二行';
  item.date = date;
  item.time = time;
  return item;
}

const NOW: number = new Date(2026, 10, 15, 10, 0).getTime();

export default function reminderTest() {
  describe('ReminderPlanner', () => {
    it('plans_before_deadline', 0, () => {
      const plan = ReminderPlanner.plan(row('数学', '2026-11-20', '18:00'), NOW, 30);
      expect(plan !== undefined).assertTrue();
      if (plan !== undefined) {
        expect(plan.homeworkId).assertEqual('hw1');
        expect(plan.dueAt).assertEqual(new Date(2026, 10, 20, 18, 0).getTime());
        expect(plan.triggerAt).assertEqual(new Date(2026, 10, 20, 17, 30).getTime());
        expect(plan.title).assertEqual('数学 作业截止');
        expect(plan.content.indexOf('提前 30 分钟') > 0).assertTrue();
      }
    });

    it('clamps_trigger_after_now', 0, () => {
      // 截止 10 分钟后，提前 30 分钟 → 触发时间压到 now+1 分钟
      const plan = ReminderPlanner.plan(row('英语', '2026-11-15', '10:10'), NOW, 30);
      expect(plan !== undefined).assertTrue();
      if (plan !== undefined) {
        expect(plan.triggerAt).assertEqual(NOW + 60 * 1000);
      }
    });

    it('skips_past_and_missing_due', 0, () => {
      expect(ReminderPlanner.plan(row('过期', '2026-11-10', '18:00'), NOW, 30) === undefined).assertTrue();
      expect(ReminderPlanner.plan(row('无日期', '', ''), NOW, 30) === undefined).assertTrue();
    });

    it('title_fallback_and_advance', 0, () => {
      const plan = ReminderPlanner.plan(row('', '2026-11-20', '18:00'), NOW, 60);
      if (plan !== undefined) {
        expect(plan.title).assertEqual('的内容 截止');
        expect(plan.content.indexOf('提前 1 小时') > 0).assertTrue();
      }
      expect(ReminderPlanner.normalizeAdvance(10)).assertEqual(10);
      expect(ReminderPlanner.normalizeAdvance(45)).assertEqual(30);
      expect(ReminderPlanner.ADVANCE_OPTIONS.length).assertEqual(4);
    });

    it('urgency_labels', 0, () => {
      expect(ReminderPlanner.urgency(undefined, NOW)).assertEqual('');
      expect(ReminderPlanner.urgency(NOW - 1, NOW)).assertEqual('已过期');
      expect(ReminderPlanner.urgency(NOW + 60 * 60 * 1000, NOW)).assertEqual('今日到期');
      expect(ReminderPlanner.urgency(NOW + 3 * 24 * 60 * 60 * 1000, NOW)).assertEqual('');
    });

    it('prefs_default', 0, () => {
      const prefs: ReminderPrefs = new ReminderPrefs();
      expect(prefs.enabled).assertTrue();
      expect(prefs.advanceMinutes).assertEqual(30);
    });
  });

  describe('ReminderStoreCodec', () => {
    it('encodes_and_decodes_ids', 0, () => {
      const ids: Map<string, number> = new Map<string, number>();
      ids.set('hw1', 12);
      ids.set('hw2', 34);
      const raw: string = ReminderStore.encodeIds(ids);
      expect(raw).assertEqual('hw1:12;hw2:34');
      const decoded: Map<string, number> = ReminderStore.decodeIds(raw);
      expect(decoded.get('hw1')).assertEqual(12);
      expect(decoded.get('hw2')).assertEqual(34);
      expect(ReminderStore.decodeIds('').size).assertEqual(0);
      expect(ReminderStore.decodeIds('bad').size).assertEqual(0);
      expect(ReminderStore.decodeIds('hw3:-1').size).assertEqual(0);
    });

    it('skips_invalid_keys_and_values', 0, () => {
      const ids: Map<string, number> = new Map<string, number>();
      ids.set('a;b', 1);
      ids.set('c:d', 2);
      ids.set('ok', 3);
      ids.set('neg', -5);
      expect(ReminderStore.encodeIds(ids)).assertEqual('ok:3');
    });

    it('record_defaults', 0, () => {
      const record: ReminderRecord = new ReminderRecord();
      expect(record.advance).assertEqual(30);
      expect(record.ids.size).assertEqual(0);
    });
  });
}
