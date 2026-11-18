import { describe, it, expect } from '@ohos/hypium';
import { NoticeBodyParser } from '../main/ets/data/notices/NoticeParser';
import { NOTICE_BODY_PREFIX, NoticeGroup, NoticeOccurrence } from '../main/ets/data/notices/NoticeModels';
import { NoticeEntry, NoticesRepository } from '../main/ets/data/notices/NoticesRepository';
import { NoticeCards, NoticeCard } from '../main/ets/features/notices/NoticeCards';
import { NoticeRecurrenceLogic, NoticeSection } from '../main/ets/features/notices/NoticeRecurrence';

const NOW: number = new Date(2026, 10, 15, 10, 0).getTime(); // 周日 10:00

function bodyWith(title: string, extra: string): string {
  return NOTICE_BODY_PREFIX + '{"id":"g1","title":"' + title + '","summary":"' + title
    + '","items":[],' + extra + '}';
}

function entryFromJson(id: string, body: string, ts: number): NoticeEntry {
  const escaped: string = body.replace(new RegExp('"', 'g'), '\\"');
  const json: string = '[{"id":"' + id + '","title":"行标题","ts":' + ts + ',"body":"' + escaped + '"}]';
  const rows = NoticeBodyParser.parseRows(json);
  return NoticesRepository.buildEntries(rows)[0];
}

export default function noticeParityTest() {
  describe('NoticeRecurrenceLogic', () => {
    it('parses_time_formats', 0, () => {
      expect(NoticeRecurrenceLogic.parseTs('2026-11-18T00:00:00+08:00'))
        .assertEqual(new Date(2026, 10, 18, 0, 0).getTime());
      expect(NoticeRecurrenceLogic.parseTs('2026-11-18 09:30'))
        .assertEqual(new Date(2026, 10, 18, 9, 30).getTime());
      const mdhm: number = NoticeRecurrenceLogic.parseTs('11-18 09:30');
      expect(new Date(mdhm).getMonth()).assertEqual(10);
      expect(new Date(mdhm).getDate()).assertEqual(18);
      expect(NoticeRecurrenceLogic.parseTs('')).assertEqual(0);
      expect(NoticeRecurrenceLogic.parseTs('not-a-date')).assertEqual(0);
    });

    it('daily_next', 0, () => {
      const group: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('日常', '"recurrence":{"freq":"daily","time":"19:00"}'));
      expect(group !== undefined).assertTrue();
      if (group !== undefined) {
        expect(NoticeRecurrenceLogic.recurNext(group, NOW))
          .assertEqual(new Date(2026, 10, 15, 19, 0).getTime());
        expect(NoticeRecurrenceLogic.recurNext(group, new Date(2026, 10, 15, 20, 0).getTime()))
          .assertEqual(new Date(2026, 10, 16, 19, 0).getTime());
      }
    });

    it('weekly_next', 0, () => {
      const group: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('每周一', '"recurrence":{"freq":"weekly","weekday":1,"time":"19:00"}'));
      if (group !== undefined) {
        expect(NoticeRecurrenceLogic.recurNext(group, NOW))
          .assertEqual(new Date(2026, 10, 16, 19, 0).getTime());
      }
    });

    it('monthly_day_and_invalid', 0, () => {
      const monthly: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('每月', '"recurrence":{"freq":"monthly_day","day":20,"time":"08:00"}'));
      if (monthly !== undefined) {
        expect(NoticeRecurrenceLogic.recurNext(monthly, NOW))
          .assertEqual(new Date(2026, 10, 20, 8, 0).getTime());
      }
      const badTime: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('坏时间', '"recurrence":{"freq":"daily","time":"7pm"}'));
      if (badTime !== undefined) {
        expect(NoticeRecurrenceLogic.isLongterm(badTime)).assertFalse();
      }
      const badFreq: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('坏频率', '"recurrence":{"freq":"yearly","time":"09:00"}'));
      if (badFreq !== undefined) {
        expect(NoticeRecurrenceLogic.isLongterm(badFreq)).assertFalse();
      }
    });

    it('occurrence_window_and_key', 0, () => {
      const entry: NoticeEntry = entryFromJson('g1',
        bodyWith('每周一', '"recurrence":{"freq":"weekly","weekday":1,"time":"19:00"}'), 1);
      const next: number = new Date(2026, 10, 16, 19, 0).getTime();
      const inside: NoticeOccurrence | undefined = NoticeRecurrenceLogic.occurrenceOf(
        entry, next - 12 * 3600 * 1000);
      expect(inside !== undefined).assertTrue();
      if (inside !== undefined) {
        expect(inside.key).assertEqual('g1@occ:20261116');
        expect(inside.nextMillis).assertEqual(next);
        expect(inside.windowStartMillis).assertEqual(next - 24 * 3600 * 1000);
      }
      expect(NoticeRecurrenceLogic.occurrenceOf(entry, next - 30 * 3600 * 1000) === undefined).assertTrue();
      expect(NoticeRecurrenceLogic.occurrenceOf(entry, next) === undefined).assertTrue();
      expect(NoticeRecurrenceLogic.occurrenceKey('g2', next)).assertEqual('g2@occ:20261116');
    });

    it('until_and_ended', 0, () => {
      const entry: NoticeEntry = entryFromJson('g1',
        bodyWith('已结束', '"recurrence":{"freq":"daily","time":"19:00","until":"2026-11-14"}'), 1);
      const group: NoticeGroup | undefined = entry.group;
      if (group !== undefined) {
        expect(NoticeRecurrenceLogic.recurUntil(group))
          .assertEqual(new Date(2026, 10, 14, 23, 59, 59, 999).getTime());
        expect(NoticeRecurrenceLogic.sectionOf(entry, NOW)).assertEqual(NoticeSection.EXPIRED);
        expect(NoticeRecurrenceLogic.occurrenceOf(entry, NOW) === undefined).assertTrue();
      }
    });

    it('sections_primary_material_expired', 0, () => {
      const withDeadline: NoticeEntry = entryFromJson('a1',
        bodyWith('交作业', '"deadline":"2026-11-20 18:00"'), 1);
      expect(NoticeRecurrenceLogic.sectionOf(withDeadline, NOW)).assertEqual(NoticeSection.PRIMARY);
      const expired: NoticeEntry = entryFromJson('a2',
        bodyWith('过期通知', '"deadline":"2026-11-10 18:00"'), 2);
      expect(NoticeRecurrenceLogic.sectionOf(expired, NOW)).assertEqual(NoticeSection.EXPIRED);
      const material: NoticeEntry = entryFromJson('a3', bodyWith('资料通知', ''), 3);
      expect(NoticeRecurrenceLogic.sectionOf(material, NOW)).assertEqual(NoticeSection.MATERIAL);
    });

    it('deadline_text_formats', 0, () => {
      const group: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('截止', '"deadline":"2026-11-20T18:00:00+08:00"'));
      if (group !== undefined) {
        expect(NoticeRecurrenceLogic.deadlineText(group)).assertEqual('11-20 18:00');
      }
      const raw: NoticeGroup | undefined = NoticeBodyParser.parseGroup(
        bodyWith('文字截止', '"deadline":"另行通知"'));
      if (raw !== undefined) {
        expect(NoticeRecurrenceLogic.deadlineText(raw)).assertEqual('另行通知');
      }
    });
  });

  describe('NoticeCards', () => {
    it('builds_occurrence_and_sections', 0, () => {
      const longterm: NoticeEntry = entryFromJson('g1',
        bodyWith('长期安排', '"recurrence":{"freq":"weekly","weekday":1,"time":"19:00"}'), 1);
      const expired: NoticeEntry = entryFromJson('e1',
        bodyWith('过期通知', '"deadline":"2026-11-10 18:00"'), 2);
      const material: NoticeEntry = entryFromJson('m1', bodyWith('资料通知', ''), 3);
      const next: number = new Date(2026, 10, 16, 19, 0).getTime();
      const now: number = next - 12 * 3600 * 1000;
      const cards: NoticeCard[] = NoticeCards.build([longterm, expired, material], now);
      expect(cards.length).assertEqual(3);
      const primary: NoticeCard[] = NoticeCards.ofSection(cards, NoticeSection.PRIMARY);
      expect(primary.length).assertEqual(1);
      expect(primary[0].occurrence).assertTrue();
      expect(primary[0].key).assertEqual('g1@occ:20261116');
      expect(NoticeCards.ofSection(cards, NoticeSection.EXPIRED).length).assertEqual(1);
      expect(NoticeCards.ofSection(cards, NoticeSection.MATERIAL).length).assertEqual(1);
    });

    it('definition_card_when_no_occurrence', 0, () => {
      const longterm: NoticeEntry = entryFromJson('g1',
        bodyWith('长期安排', '"recurrence":{"freq":"monthly_day","day":0,"time":"09:00"}'), 1);
      const cards: NoticeCard[] = NoticeCards.build([longterm], NOW);
      expect(cards.length).assertEqual(1);
      expect(cards[0].definition).assertTrue();
      expect(cards[0].occurrence).assertFalse();
      expect(cards[0].label.indexOf('长期安排') === 0).assertTrue();
    });

    it('pending_count_excludes_definition', 0, () => {
      const normal: NoticeEntry = entryFromJson('n1',
        bodyWith('普通通知', '"deadline":"2026-11-20 18:00"'), 2);
      const cards: NoticeCard[] = NoticeCards.build([normal], NOW);
      expect(NoticeCards.pendingCount(cards, [])).assertEqual(1);
      expect(NoticeCards.pendingCount(cards, [cards[0].key])).assertEqual(0);
      const definition: NoticeCard = new NoticeCard();
      definition.definition = true;
      expect(NoticeCards.pendingCount([definition], [])).assertEqual(0);
    });
  });
}
