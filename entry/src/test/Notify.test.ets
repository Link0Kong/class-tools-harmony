import { NoticeEntry } from '../main/ets/data/notices/NoticesRepository';
import { NotifyStore } from '../main/ets/data/notify/NotifyStore';
import { PersonalTask } from '../main/ets/data/tasks/TaskModels';
import { describe, it, expect } from '@ohos/hypium';
import { CourseWindow, NotifyPlanner } from '../main/ets/features/notify/NotifyPlanner';
import { NotifyInput, NotifySnapshot, NotifyEvent } from '../main/ets/features/notify/NotifyModels';
import { NotifySettings } from '../main/ets/features/notify/NotifySettings';
import { SessionInfo } from '../main/ets/data/timetable/TimetableModels';

const NOW: number = 1700000000000;

function session(name: string, room: string, startAt: number): SessionInfo {
  const info: SessionInfo = new SessionInfo();
  info.name = name;
  info.room = room;
  info.startText = '09:00';
  info.endText = '09:45';
  info.startAt = startAt;
  info.endAt = startAt + 45 * 60 * 1000;
  return info;
}

function inputWith(list: SessionInfo[]): NotifyInput {
  const input: NotifyInput = new NotifyInput();
  input.now = NOW;
  input.classes = list;
  return input;
}

export default function localUnitTest() {
  describe('NotifyTest', () => {
    it('course_countdown_enters_at_lead_and_exits_at_bell', 0, () => {
      const start = NOW + 10 * 60000;
      const math = session('数学', '101', start);
      expect(CourseWindow.select([math], 5, NOW).nextAt).assertEqual(NOW + 5 * 60000);
      expect(CourseWindow.select([math], 10, NOW).session?.name).assertEqual('数学');
      expect(CourseWindow.select([math], 10, start).session === undefined).assertTrue();
    });

    it('schedule_keys_survive_punctuation_and_migrate_previous_records', 0, () => {
      const map = new Map<string, number>();
      map.set('hw:数学;练习', 123);
      map.set('task:done', -1);
      const decoded = NotifyStore.decode(NotifyStore.encode(map));
      expect(decoded.get('hw:数学;练习')).assertEqual(123);
      expect(decoded.get('task:done')).assertEqual(-1);
      expect(NotifyStore.decode('old:19').get('old')).assertEqual(19);
    });

    it('repeated_class_scan_keeps_same_trigger_inside_lead_window', 0, () => {
      const s = new NotifySettings();
      const input = inputWith([session('数学', '101', NOW + 5 * 60000)]);
      const a = NotifyPlanner.plan(input, s, new NotifySnapshot())[0].signature();
      input.now += 10000;
      expect(NotifyPlanner.plan(input, s, new NotifySnapshot())[0].signature()).assertEqual(a);
      s.classLeadMinutes = 15;
      expect(NotifyPlanner.plan(input, s, new NotifySnapshot())[0].signature() !== a).assertTrue();
    });

    it('task_snooze_edit_completion_and_past_delivery', 0, () => {
      const task = new PersonalTask();
      task.id = 'task:1';
      task.title = '复习';
      task.remindAt = NOW + 120000;
      task.snoozeUntil = NOW + 180000;
      const first = NotifyPlanner.tasks([task], NOW)[0];
      expect(first.fireAt).assertEqual(task.snoozeUntil);
      task.title = '整理笔记';
      expect(NotifyPlanner.tasks([task], NOW)[0].signature() !== first.signature()).assertTrue();
      task.done = true;
      expect(NotifyPlanner.tasks([task], NOW).length).assertEqual(0);
      task.done = false;
      expect(NotifyPlanner.tasks([task], task.snoozeUntil + 2 * 3600000)[0].fireAt).assertEqual(task.snoozeUntil);
      expect(NotifyPlanner.tasks([task], task.snoozeUntil + 6 * 3600000 + 1).length).assertEqual(0);
      task.lastNotifyAt = task.snoozeUntil;
      expect(NotifyPlanner.tasks([task], NOW).length).assertEqual(0);
    });

    it('failed_initial_load_keeps_baseline_pending_for_that_source', 0, () => {
      const input = inputWith([]);
      input.unavailable = ['hw'];
      const snapshot = NotifyPlanner.nextSnapshot(input, new NotifySnapshot());
      expect(snapshot.homeworkReady).assertFalse();
      expect(snapshot.pollsReady).assertTrue();
      expect(NotifySnapshot.fromJson('{"initialized":true}').homeworkReady).assertTrue();
    });

    it('manual_notice_delivery_merges_sender_deduplicates_and_retries_only_failures', 0, () => {
      const settings = new NotifySettings();
      settings.noticeNew = true;
      const first = new NoticeEntry();
      first.row.id = 'one';
      first.row.author = '班长';
      first.row.title = '周末活动';
      const second = new NoticeEntry();
      second.row.id = 'two';
      second.row.title = '轮值表';
      const hidden = new NoticeEntry();
      hidden.row.id = 'old';
      hidden.row.hidden = true;
      const input = inputWith([]);
      input.notices = [first, second, first, hidden];
      const known = new NotifySnapshot();
      known.noticesReady = true;
      const events = NotifyPlanner.plan(input, settings, known);
      expect(events.length).assertEqual(2);
      expect(events[0].text).assertEqual('班长 · 周末活动');
      const next = NotifyPlanner.nextSnapshot(input, known, [events[1]]);
      expect(NotifyPlanner.plan(input, settings, next)[0].key).assertEqual('ntnew:two');
      expect(next.ntIds.includes('old')).assertFalse();
      input.unavailable = ['ntd', 'nts'];
      expect(NotifyPlanner.plan(input, settings, next).length).assertEqual(0);
      expect(NotifyPlanner.nextSnapshot(input, next).ntIds.includes('two')).assertFalse();
    });

    it('all_active_notice_ids_survive_the_history_limit', 0, () => {
      const settings = new NotifySettings();
      settings.noticeNew = true;
      const input = inputWith([]);
      for (let i = 0; i < 330; i++) {
        const item = new NoticeEntry();
        item.row.id = 'n' + i;
        input.notices.push(item);
      }
      const known = NotifyPlanner.nextSnapshot(input, new NotifySnapshot());
      expect(NotifyPlanner.plan(input, settings, known).length).assertEqual(0);
    });

    it('settings_class_roundtrip', 0, () => {
      const s: NotifySettings = new NotifySettings();
      s.master = true;
      s.classRemind = false;
      s.classLeadMinutes = 15;
      const back: NotifySettings = NotifySettings.fromJson(s.toJson());
      expect(back.classRemind).assertFalse();
      expect(back.classLeadMinutes).assertEqual(15);
      expect(back.master).assertTrue();
    });

    it('class_reminder_scheduled_before_start', 0, () => {
      const s: NotifySettings = new NotifySettings();
      s.master = true;
      s.classLeadMinutes = 10;
      const cls: SessionInfo = session('高等数学', 'A101', NOW + 20 * 60 * 1000);
      cls.fullRoom = '一号教学楼 A101';
      const events: NotifyEvent[] = NotifyPlanner.plan(inputWith([cls]), s, new NotifySnapshot());
      expect(events.length).assertEqual(1);
      expect(events[0].kind).assertEqual('class_remind');
      expect(events[0].fireAt).assertEqual(NOW + 10 * 60 * 1000);
      expect(events[0].title.indexOf('高等数学') >= 0).assertTrue();
      expect(events[0].text.indexOf('09:00–09:45 · 一号教学楼 A101') >= 0).assertTrue();
    });

    it('class_reminder_disabled_or_already_started', 0, () => {
      const s: NotifySettings = new NotifySettings();
      s.master = true;
      s.classRemind = false;
      const later: SessionInfo = session('大学英语', 'B202', NOW + 60 * 60 * 1000);
      expect(NotifyPlanner.plan(inputWith([later]), s, new NotifySnapshot()).length).assertEqual(0);

      const on: NotifySettings = new NotifySettings();
      on.master = true;
      const soon: SessionInfo = session('体育', '', NOW);
      expect(NotifyPlanner.plan(inputWith([soon]), on, new NotifySnapshot()).length).assertEqual(0);
    });
  });
}
