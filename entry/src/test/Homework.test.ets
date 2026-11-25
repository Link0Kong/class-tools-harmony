import { describe, it, expect } from '@ohos/hypium';
import {
  HomeworkAttachments,
  HomeworkAttachmentKind,
  HomeworkDueCalculator,
  HomeworkDueTone,
  HomeworkFilter,
  HomeworkItem,
  HomeworkRow
} from '../main/ets/data/homework/HomeworkModels';
import { HomeworkRepository, HomeworkResult } from '../main/ets/data/homework/HomeworkRepository';
import { FakeApi } from './support/FakeApi';

const HOUR: number = 60 * 60 * 1000;
const DAY: number = 24 * HOUR;

function rowWith(date: string, time: string): HomeworkRow {
  const row: HomeworkRow = new HomeworkRow();
  row.id = 'hw_' + date + '_' + time;
  row.date = date;
  row.time = time;
  return row;
}

function rowJson(id: string, subject: string, date: string, time: string): string {
  return '{"id":"' + id + '","subject":"' + subject + '","content":"' + subject + ' 内容",'
    + '"date":"' + date + '","time":"' + time + '","author":"老师","archived":false,"ts":1}';
}

export default function homeworkTest() {
  describe('HomeworkDue', () => {
    it('parse_date_and_optional_time', 0, () => {
      const withTime: number | undefined = HomeworkDueCalculator.parseDue('2026-11-20', '18:30');
      expect(withTime !== undefined).assertTrue();
      const midnight: number | undefined = HomeworkDueCalculator.parseDue('2026-11-20', '');
      if (withTime !== undefined && midnight !== undefined) {
        expect(withTime - midnight).assertEqual(18 * HOUR + 30 * 60 * 1000);
      }
      expect(HomeworkDueCalculator.parseDue('', '') === undefined).assertTrue();
      expect(HomeworkDueCalculator.parseDue('2026/11/20', '') === undefined).assertTrue();
    });

    it('hours_left_is_urgent', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      const due = HomeworkDueCalculator.evaluate(rowWith('2026-11-14', '15:00'), now);
      expect(due !== undefined).assertTrue();
      if (due !== undefined) {
        expect(due.label).assertEqual('还剩 3 小时');
        expect(due.tone).assertEqual(HomeworkDueTone.URGENT);
        expect(due.expired).assertFalse();
        expect(due.prunable).assertFalse();
      }
    });

    it('days_left_tone_by_distance', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      const near = HomeworkDueCalculator.evaluate(rowWith('2026-11-17', '12:00'), now);
      const far = HomeworkDueCalculator.evaluate(rowWith('2026-12-01', '12:00'), now);
      if (near !== undefined && far !== undefined) {
        expect(near.label).assertEqual('还剩 3 天');
        expect(near.tone).assertEqual(HomeworkDueTone.WARN);
        expect(far.tone).assertEqual(HomeworkDueTone.SAFE);
      }
    });

    it('overdue_hours_and_days', 0, () => {
      const now: number = new Date(2026, 10, 14, 12, 0).getTime();
      const hours = HomeworkDueCalculator.evaluate(rowWith('2026-11-14', '07:00'), now);
      const days = HomeworkDueCalculator.evaluate(rowWith('2026-11-12', '12:00'), now);
      if (hours !== undefined && days !== undefined) {
        expect(hours.label).assertEqual('已过期 5 小时');
        expect(hours.tone).assertEqual(HomeworkDueTone.OVERDUE);
        expect(days.label).assertEqual('已过期 2 天');
        expect(days.expired).assertTrue();
        expect(days.prunable).assertFalse();
      }
    });

    it('prunable_after_three_days', 0, () => {
      const now: number = new Date(2026, 10, 20, 12, 0).getTime();
      const due = HomeworkDueCalculator.evaluate(rowWith('2026-11-15', '12:00'), now);
      expect(due !== undefined).assertTrue();
      if (due !== undefined) {
        expect(due.prunable).assertTrue();
      }
    });

    it('due_text_formats', 0, () => {
      const at: number = new Date(2026, 10, 20, 18, 5).getTime();
      expect(HomeworkDueCalculator.dueText(at)).assertEqual('11-20 18:05');
      expect(HomeworkDueCalculator.dueText(0)).assertEqual('—');
    });

    it('no_date_means_no_due', 0, () => {
      expect(HomeworkDueCalculator.evaluate(rowWith('', ''), Date.now()) === undefined).assertTrue();
    });
  });

  describe('HomeworkAttachments', () => {
    it('parses_data_uri_and_url', 0, () => {
      const raw: string = '[{"n":"图.png","t":"image/png","d":"data:image/png;base64,AAAA","s":123},'
        + '{"n":"链接","t":"image/jpeg","d":"https://example.com/a.jpg"}]';
      const metas = HomeworkAttachments.parse(raw);
      expect(metas.length).assertEqual(2);
      expect(metas[0].name).assertEqual('图.png');
      expect(metas[0].sizeBytes).assertEqual(123);
      expect(metas[0].kind).assertEqual(HomeworkAttachmentKind.DATA_URI);
      expect(metas[0].isImage()).assertTrue();
      expect(metas[1].kind).assertEqual(HomeworkAttachmentKind.URL);
      expect(metas[1].sizeBytes).assertEqual(0);
    });

    it('estimates_size_without_explicit_size', 0, () => {
      const raw: string = '[{"n":"a","t":"image/png","d":"data:image/png;base64,AAAAAAAA"}]';
      const metas = HomeworkAttachments.parse(raw);
      expect(metas[0].sizeBytes).assertEqual(6);
    });

    it('bad_json_returns_empty', 0, () => {
      expect(HomeworkAttachments.parse('not-json').length).assertEqual(0);
      expect(HomeworkAttachments.parse('{"a":1}').length).assertEqual(0);
      expect(HomeworkAttachments.parse('').length).assertEqual(0);
    });

    it('data_of_returns_raw_payload', 0, () => {
      const raw: string = '[{"n":"a","d":"data:image/png;base64,AAAA"}]';
      expect(HomeworkAttachments.dataOf(raw, 0)).assertEqual('data:image/png;base64,AAAA');
      expect(HomeworkAttachments.dataOf(raw, 5)).assertEqual('');
    });
  });

  describe('HomeworkItem', () => {
    it('title_falls_back_to_first_line', 0, () => {
      const item: HomeworkItem = new HomeworkItem();
      item.row = new HomeworkRow();
      item.row.content = '第一行标题\n第二行';
      expect(item.title()).assertEqual('第一行标题');
      item.row.subject = '数学作业';
      expect(item.title()).assertEqual('数学作业');
      expect(item.bodyPreview().length > 0).assertTrue();
    });
  });

  describe('HomeworkRepository', () => {
    it('parses_rows_and_caches', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.homeworkBody = '[' + rowJson('hw_1', '数学', '2026-11-20', '18:00') + ','
        + rowJson('hw_2', '英语', '2026-11-21', '12:00') + ']';
      const repo: HomeworkRepository = new HomeworkRepository(api, () => 1000, 600000);
      const first: HomeworkResult = await repo.load(false);
      expect(first.ok).assertTrue();
      expect(first.rows.length).assertEqual(2);
      expect(first.rows[0].subject).assertEqual('数学');
      expect(first.rows[0].date).assertEqual('2026-11-20');
      const second: HomeworkResult = await repo.load(false);
      expect(second.fromCache).assertTrue();
      expect(api.getPaths.length).assertEqual(1);
      expect(api.getPaths[0].indexOf('archived=eq.false') > 0).assertTrue();
      expect(api.getPaths[0].indexOf('order=ts.asc') > 0).assertTrue();
    });

    it('malformed_success_keeps_assignments_until_a_valid_empty_result', 0, async () => {
      const api = new FakeApi();
      const repo = new HomeworkRepository(api);
      api.homeworkBody = '[' + rowJson('hw_1', '数学', '2026-11-20', '18:00') + ']';
      await repo.load(true);
      api.homeworkBody = '[bad gateway]';
      const fallback = await repo.load(true);
      expect(fallback.fromCache).assertTrue();
      expect(fallback.rows[0].id).assertEqual('hw_1');
      api.homeworkBody = '[]';
      expect((await repo.load(true)).rows.length).assertEqual(0);
    });

    it('failure_falls_back_to_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.homeworkBody = '[' + rowJson('hw_1', '数学', '2026-11-20', '18:00') + ']';
      let now: number = 1000;
      const repo: HomeworkRepository = new HomeworkRepository(api, () => now, 1000);
      await repo.load(false);
      now = 5000;
      api.failGets = true;
      const second: HomeworkResult = await repo.load(true);
      expect(second.ok).assertTrue();
      expect(second.fromCache).assertTrue();
      expect(second.rows.length).assertEqual(1);
    });

    it('coalesces_concurrent_loads', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.homeworkBody = '[' + rowJson('hw_1', '数学', '2026-11-20', '18:00') + ']';
      const repo: HomeworkRepository = new HomeworkRepository(api, () => 1000, 600000);
      const first = repo.load(false);
      const second = repo.load(false);
      const a: HomeworkResult = await first;
      const b: HomeworkResult = await second;
      expect(a.ok).assertTrue();
      expect(b.ok).assertTrue();
      expect(a.rows.length).assertEqual(1);
      expect(b.rows.length).assertEqual(1);
      expect(api.getPaths.length).assertEqual(1);
    });

    it('skips_rows_without_id', 0, () => {
      const raw: string = '[{"subject":"无 id"},{"id":"hw_1","subject":"有 id"}]';
      const rows = HomeworkRepository.parseRows(raw);
      expect(rows.length).assertEqual(1);
      expect(rows[0].subject).assertEqual('有 id');
      expect(HomeworkRepository.parseRows('bad').length).assertEqual(0);
    });
  });

  describe('HomeworkFilter', () => {
    it('labels', 0, () => {
      expect(HomeworkFilter.ALL).assertEqual('全部');
      expect(HomeworkFilter.UNFINISHED).assertEqual('未完成');
      expect(HomeworkFilter.DONE).assertEqual('已完成');
    });
  });
}
