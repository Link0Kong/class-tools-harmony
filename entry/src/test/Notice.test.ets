import { describe, it, expect } from '@ohos/hypium';
import {
  NOTICE_BODY_PREFIX,
  NoticeFilter,
  NoticeGroup,
  NoticeRow,
  NoticeSegment,
  NoticeSigRow
} from '../main/ets/data/notices/NoticeModels';
import { NoticeBodyParser } from '../main/ets/data/notices/NoticeParser';
import { NoticeEntry, NoticesRepository, NoticesResult } from '../main/ets/data/notices/NoticesRepository';
import { FakeApi } from './support/FakeApi';

const AUTO_BODY: string = NOTICE_BODY_PREFIX + '{"id":"g1","title":"关于班会","cat":"班会",'
  + '"summary":"本周五开班会","aiSummary":"周五 19:00 班会","aiPoints":["带笔记本","提前 10 分钟到"],'
  + '"aiSegments":[{"type":"时间","text":"周五 19:00"},{"type":"地点","text":"A101"}],'
  + '"deadline":"2026-11-20 18:00","timeLabel":"周五 19:00","items":['
  + '{"kind":"text","text":"原通知正文","fromName":"班长","time":"11-14 10:00"},'
  + '{"kind":"img","caption":"座位表","src":"data:image/png;base64,AAAAAAAA"},'
  + '{"kind":"file","name":"材料.zip","size":"2.0 MB"},'
  + '{"kind":"form","realTitle":"报名表","close":"11-19"},'
  + '{"kind":"link","name":"在线文档","url":"https://example.com/doc"}]}';

function rowJson(id: string, title: string, ts: number, pin: boolean, hidden: boolean, body: string): string {
  const escaped: string = body.replace(new RegExp('\\\\', 'g'), '\\\\')
    .replace(new RegExp('"', 'g'), '\\"');
  return '{"id":"' + id + '","title":"' + title + '","body":"' + escaped + '","pin":' + pin
    + ',"imp":false,"hidden":' + hidden + ',"ts":' + ts + ',"attachments":""}';
}

export default function noticeTest() {
  describe('NoticeBodyParser', () => {
    it('detects_auto_and_parses_group', 0, () => {
      expect(NoticeBodyParser.isAuto(AUTO_BODY)).assertTrue();
      expect(NoticeBodyParser.isAuto('普通人工通知')).assertFalse();
      const group: NoticeGroup | undefined = NoticeBodyParser.parseGroup(AUTO_BODY);
      expect(group !== undefined).assertTrue();
      if (group !== undefined) {
        expect(group.id).assertEqual('g1');
        expect(group.title).assertEqual('关于班会');
        expect(group.aiPoints.length).assertEqual(2);
        expect(group.aiSegments.length).assertEqual(2);
        expect(group.aiSegments[0].type).assertEqual('时间');
        expect(group.deadline).assertEqual('2026-11-20 18:00');
        expect(group.items.length).assertEqual(5);
      }
    });

    it('bad_json_returns_undefined', 0, () => {
      expect(NoticeBodyParser.parseGroup(NOTICE_BODY_PREFIX + '{bad') === undefined).assertTrue();
      expect(NoticeBodyParser.parseGroup('普通人工通知') === undefined).assertTrue();
      expect(NoticeBodyParser.parseGroup(NOTICE_BODY_PREFIX + '') === undefined).assertTrue();
    });

    it('parses_items_meta', 0, () => {
      const items = NoticeBodyParser.parseItems([
        { 'kind': 'text', 'text': '正文一' },
        { 'kind': 'text', 'text': '正文二' },
        { 'kind': 'follow', 'text': '补充' },
        { 'kind': 'img', 'caption': '图', 'src': 'data:image/png;base64,AAAAAAAA' },
        { 'kind': 'file', 'name': 'a.zip', 'size': '1.5 MB' },
        { 'kind': 'form', 'realTitle': '报名', 'close': '11-19' },
        { 'kind': 'link', 'name': '文档', 'url': 'https://x' }
      ]);
      expect(items.length).assertEqual(7);
      expect(items[0].label).assertEqual('原始消息');
      expect(items[1].label).assertEqual('补充通知');
      expect(items[2].isFollow).assertTrue();
      expect(items[3].text).assertEqual('图片 · 图');
      expect(items[4].name).assertEqual('a.zip');
      expect(items[4].sizeText).assertEqual('1.5 MB');
      expect(items[5].statusText).assertEqual('11-19 截止');
      expect(items[6].name).assertEqual('文档');
    });

    it('applies_override_whitelist', 0, () => {
      const group: NoticeGroup = NoticeBodyParser.parseGroup(AUTO_BODY)!;
      const overridden: NoticeGroup = NoticeBodyParser.applyOverride(group,
        '{"title":"改过的标题","summary":"","unknown":"x"}');
      expect(overridden.title).assertEqual('改过的标题');
      expect(overridden.summary).assertEqual('');
      expect(overridden.aiSummary).assertEqual('周五 19:00 班会');
    });

    it('parses_sig_rows_and_signature', 0, () => {
      const raw: string = '[{"id":"a","ts":1,"hidden":false,"edited_at":0},{"id":"b","ts":2,"hidden":true,"edited_at":3}]';
      const rows: NoticeSigRow[] = NoticeBodyParser.parseSigRows(raw);
      expect(rows.length).assertEqual(2);
      const sig: string = NoticeSigRow.signatureOf(rows);
      expect(sig.indexOf('a|1|0|0') === 0).assertTrue();
      expect(NoticeSigRow.signatureOf(NoticeBodyParser.parseSigRows(raw))).assertEqual(sig);
      expect(NoticeSigRow.signatureOf(NoticeBodyParser.parseSigRows('[]')) !== sig).assertTrue();
    });

    it('parses_rows_and_skips_bad', 0, () => {
      const raw: string = '[' + rowJson('n1', '标题', 100, false, false, AUTO_BODY) + ',{"title":"无 id"}]';
      const rows: NoticeRow[] = NoticeBodyParser.parseRows(raw);
      expect(rows.length).assertEqual(1);
      expect(rows[0].id).assertEqual('n1');
      expect(rows[0].ts).assertEqual(100);
      expect(NoticeBodyParser.isAuto(rows[0].body)).assertTrue();
    });
  });

  describe('NoticesRepository', () => {
    it('builds_entries_hides_hidden_and_sorts', 0, () => {
      const rows: NoticeRow[] = NoticeBodyParser.parseRows('[' + rowJson('n1', '普通', 100, false, false, '人工通知')
        + ',' + rowJson('n2', '置顶', 50, true, false, '人工通知')
        + ',' + rowJson('n3', '隐藏', 200, false, true, '人工通知') + ']');
      const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
      expect(entries.length).assertEqual(2);
      expect(entries[0].id()).assertEqual('n2');
      expect(entries[1].id()).assertEqual('n1');
      expect(entries[0].row.pin).assertTrue();
    });

    it('entry_title_and_summary_prefer_group', 0, () => {
      const rows: NoticeRow[] = NoticeBodyParser.parseRows('[' + rowJson('n1', '行标题', 1, false, false, AUTO_BODY) + ']');
      const entry: NoticeEntry = NoticesRepository.buildEntries(rows)[0];
      expect(entry.title()).assertEqual('关于班会');
      expect(entry.summary()).assertEqual('周五 19:00 班会');
      expect(entry.items.length).assertEqual(5);
      expect(entry.timeLabel()).assertEqual('周五 19:00');
    });

    it('manual_notice_uses_row_fields', 0, () => {
      const rows: NoticeRow[] = NoticeBodyParser.parseRows('[' + rowJson('n2', '人工标题', 1700000000000, false, false,
        '第一行正文 第二行') + ']');
      const entry: NoticeEntry = NoticesRepository.buildEntries(rows)[0];
      expect(entry.title()).assertEqual('人工标题');
      expect(entry.summary()).assertEqual('第一行正文 第二行');
      expect(entry.group === undefined).assertTrue();
    });

    it('dedupes_same_title_and_summary_keeps_newest', 0, () => {
      const rows: NoticeRow[] = NoticeBodyParser.parseRows('[' + rowJson('n1', '班会', 100, false, false, '同一内容')
        + ',' + rowJson('n2', '班会', 300, false, false, '同一内容')
        + ',' + rowJson('n3', '班会', 200, false, false, '不同内容') + ']');
      const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
      expect(entries.length).assertEqual(2);
      expect(entries[0].id()).assertEqual('n2');
    });

    it('filters_by_done_ids', 0, () => {
      const rows: NoticeRow[] = NoticeBodyParser.parseRows('[' + rowJson('n1', 'a', 2, false, false, 'x')
        + ',' + rowJson('n2', 'b', 1, false, false, 'y') + ']');
      const entries: NoticeEntry[] = NoticesRepository.buildEntries(rows);
      expect(NoticesRepository.filterEntries(entries, NoticeFilter.ALL, ['n1']).length).assertEqual(2);
      expect(NoticesRepository.filterEntries(entries, NoticeFilter.UNREAD, ['n1']).length).assertEqual(1);
      expect(NoticesRepository.filterEntries(entries, NoticeFilter.DONE, ['n1']).length).assertEqual(1);
    });

    it('signature_short_circuits_full_fetch', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.noticesSigBody = '[{"id":"n1","ts":100,"hidden":false,"edited_at":0}]';
      api.noticesBody = '[' + rowJson('n1', '标题', 100, false, false, '正文') + ']';
      let now: number = 1000;
      // TTL = 0：强制每次都先拉签名，才能验证「签名未变就不再拉整表」
      const repo: NoticesRepository = new NoticesRepository(api, () => now, 0);
      const first: NoticesResult = await repo.load(false);
      expect(first.ok).assertTrue();
      expect(first.entries.length).assertEqual(1);
      const getsAfterFirst: number = api.getPaths.length;
      expect(getsAfterFirst).assertEqual(2);
      now = 2000;
      const second: NoticesResult = await repo.load(false);
      expect(second.fromCache).assertTrue();
      expect(api.getPaths.length).assertEqual(getsAfterFirst + 1);
    });

    it('signature_change_refetches_full_table', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.noticesSigBody = '[{"id":"n1","ts":100,"hidden":false,"edited_at":0}]';
      api.noticesBody = '[' + rowJson('n1', '标题', 100, false, false, '正文') + ']';
      let now: number = 1000;
      const repo: NoticesRepository = new NoticesRepository(api, () => now, 0);
      await repo.load(false);
      const before: number = api.getPaths.length;
      api.noticesSigBody = '[{"id":"n1","ts":200,"hidden":false,"edited_at":0}]';
      now = 5000;
      const second: NoticesResult = await repo.load(false);
      expect(second.ok).assertTrue();
      expect(api.getPaths.length).assertEqual(before + 2);
    });

    it('failure_falls_back_to_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.noticesSigBody = '[{"id":"n1","ts":100,"hidden":false,"edited_at":0}]';
      api.noticesBody = '[' + rowJson('n1', '标题', 100, false, false, '正文') + ']';
      let now: number = 1000;
      const repo: NoticesRepository = new NoticesRepository(api, () => now, 0);
      await repo.load(false);
      now = 5000;
      api.failGets = true;
      const second: NoticesResult = await repo.load(true);
      expect(second.ok).assertTrue();
      expect(second.fromCache).assertTrue();
      expect(second.entries.length).assertEqual(1);
    });
  });

  describe('NoticeSegmentModel', () => {
    it('segment_fields', 0, () => {
      const seg: NoticeSegment = new NoticeSegment();
      seg.type = '地点';
      seg.text = 'A101';
      expect(seg.type + seg.text).assertEqual('地点A101');
    });
  });
}
