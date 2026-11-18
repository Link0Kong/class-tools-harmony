import { describe, it, expect } from '@ohos/hypium';
import { NotifyPlanner } from '../main/ets/features/notify/NotifyPlanner';
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
      const events: NotifyEvent[] = NotifyPlanner.plan(inputWith([cls]), s, new NotifySnapshot());
      expect(events.length).assertEqual(1);
      expect(events[0].kind).assertEqual('class_remind');
      expect(events[0].fireAt).assertEqual(NOW + 10 * 60 * 1000);
      expect(events[0].title.indexOf('高等数学') >= 0).assertTrue();
      expect(events[0].text.indexOf('A101') >= 0).assertTrue();
    });

    it('class_reminder_disabled_or_too_late', 0, () => {
      const s: NotifySettings = new NotifySettings();
      s.master = true;
      s.classRemind = false;
      const later: SessionInfo = session('大学英语', 'B202', NOW + 60 * 60 * 1000);
      expect(NotifyPlanner.plan(inputWith([later]), s, new NotifySnapshot()).length).assertEqual(0);

      const on: NotifySettings = new NotifySettings();
      on.master = true;
      const soon: SessionInfo = session('体育', '', NOW + 30 * 1000);
      expect(NotifyPlanner.plan(inputWith([soon]), on, new NotifySnapshot()).length).assertEqual(0);
    });
  });
}
