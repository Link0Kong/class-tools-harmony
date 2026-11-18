import { describe, it, expect } from '@ohos/hypium';
import {
  PptDeck,
  PptDeckDetail,
  PptDetailResult,
  PptFileInfo,
  PptListResult,
  downloadName,
  fileUrl,
  formatBytes,
  resolveUrl,
  pptStatusColor,
  pptStatusLabel
} from '../main/ets/data/ppt/PptModels';
import { PptRepository } from '../main/ets/data/ppt/PptRepository';
import { PptUploadPlanner } from '../main/ets/features/ppt/PptUploadPlanner';
import { PptUploadRepository } from '../main/ets/data/ppt/PptUploadRepository';
import { FakeApi } from './support/FakeApi';

const LIST_JSON: string = '['
  + '{"id":"deck_1","title":"开学第一课","owner_name":"班长","status":"ready","progress":100,'
  + '"slide_count":12,"step_count":24,"aspect":"16:9","cover_url":"https://x/cover.webp",'
  + '"source_name":"a.pptx","source_size":1048576,"created_at":1794600000000,'
  + '"converted_at":1794610000000,"files":{"compat":{"src":"https://x/compat.pptx","size":1100000},'
  + '"pdf":{"src":"https://x/preview.pdf","size":800000}}},'
  + '{"id":"deck_2","title":"未转换","status":"processing","progress":40,"slide_count":3,"created_at":1794500000000}'
  + ']';

const DETAIL_JSON: string = '[{"id":"deck_1","title":"开学第一课","status":"ready","owner_name":"班长","slide_count":12,'
  + '"manifest":{"files":{"compat":{"src":"https://x/compat.pptx","size":1100000,"ext":"pptx",'
  + '"name":"开学第一课_兼容版.pptx"},"pdf":{"src":"https://x/preview.pdf","size":800000,"ext":"pdf","pages":12},'
  + '"source":{"src":"https://x/source.pptx","size":1048576,"ext":"pptx"}},'
  + '"compat":{"warnings":["外链媒体无法随包","字体未嵌入"]},"media_files":[{"n":"v1.mp4"},{"n":"v2.mp4"}]}}]';

const AGENT_JSON: string = '[{"body":{"at":"' + '__RECENT__' + '"},"updated_at":"2026-11-15T00:00:00+08:00"}]';

export default function pptTest() {
  describe('PptRepository', () => {
    it('parses_list_rows', 0, () => {
      const decks: PptDeck[] = PptRepository.parseList(LIST_JSON);
      expect(decks.length).assertEqual(2);
      expect(decks[0].id).assertEqual('deck_1');
      expect(decks[0].title).assertEqual('开学第一课');
      expect(decks[0].status).assertEqual('ready');
      expect(decks[0].slideCount).assertEqual(12);
      expect(decks[0].hasCompat).assertTrue();
      expect(decks[0].hasPdf).assertTrue();
      expect(decks[1].hasCompat).assertFalse();
      expect(PptRepository.parseList('bad').length).assertEqual(0);
      expect(PptRepository.parseList('[]').length).assertEqual(0);
    });

    it('parses_detail_manifest', 0, () => {
      const detail: PptDeckDetail | undefined = PptRepository.parseDetail(DETAIL_JSON);
      expect(detail !== undefined).assertTrue();
      if (detail !== undefined) {
        expect(detail.deck.title).assertEqual('开学第一课');
        expect(detail.files.compat !== undefined).assertTrue();
        expect(detail.files.pdf !== undefined).assertTrue();
        expect(detail.files.source !== undefined).assertTrue();
        if (detail.files.pdf !== undefined) {
          expect(detail.files.pdf.pages).assertEqual(12);
        }
        expect(detail.warnings.length).assertEqual(2);
        expect(detail.mediaCount).assertEqual(2);
      }
      expect(PptRepository.parseDetail('[]') === undefined).assertTrue();
    });

    it('agent_online_window', 0, () => {
      const now: number = Date.now();
      const recent: string = '[{"body":{"at":' + (now - 60 * 1000) + '}}]';
      const stale: string = '[{"body":{"at":' + (now - 10 * 60 * 1000) + '}}]';
      expect(PptRepository.agentOnline(recent)).assertTrue();
      expect(PptRepository.agentOnline(stale)).assertFalse();
      expect(PptRepository.agentOnline('[]')).assertFalse();
      const seen: string = '[{"body":{"online":true,"seen_at":' + now
        + '},"updated_at":"2026-11-09T22:30:22+08:00"}]';
      expect(PptRepository.agentOnline(seen)).assertTrue();
      const off: string = '[{"body":{"online":false,"seen_at":' + now + '}}]';
      expect(PptRepository.agentOnline(off)).assertFalse();
    });

    it('list_and_detail_via_api', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.pptListBody = LIST_JSON;
      api.pptDetailBody = DETAIL_JSON;
      api.pptAgentBody = '[{"body":{"at":' + Date.now() + '}}]';
      const repo: PptRepository = new PptRepository(api);
      const list: PptListResult = await repo.list();
      expect(list.ok).assertTrue();
      expect(list.decks.length).assertEqual(2);
      expect(list.agentOnline).assertTrue();
      expect(api.getPaths[0].indexOf('ppt_decks?select=id,title') === 0).assertTrue();
      expect(api.getPaths[0].indexOf('deleted=eq.false') > 0).assertTrue();
      expect(api.getPaths[0].indexOf('order=created_at.desc') > 0).assertTrue();
      const detail: PptDetailResult = await repo.detail('deck_1');
      expect(detail.ok).assertTrue();
      expect(detail.detail.files.compat !== undefined).assertTrue();
      expect(api.getPaths[2].indexOf('id=eq.deck_1') > 0).assertTrue();
    });

    it('list_failure_surfaces_message', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.failGets = true;
      const repo: PptRepository = new PptRepository(api);
      const list: PptListResult = await repo.list();
      expect(list.ok).assertFalse();
      expect(list.message.length > 0).assertTrue();
    });
  });

  describe('PptHelpers', () => {
    it('formats_bytes', 0, () => {
      expect(formatBytes(0)).assertEqual('—');
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(2048)).assertEqual('2.0 KB');
      expect(formatBytes(1048576)).assertEqual('1.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024)).assertEqual('3.00 GB');
    });

    it('download_names', 0, () => {
      const deck: PptDeck = new PptDeck();
      deck.title = '开学/第一课';
      const compat: PptFileInfo = new PptFileInfo();
      compat.ext = 'pptx';
      expect(downloadName(deck, compat, 'compat')).assertEqual('开学_第一课_兼容版.pptx');
      compat.ext = 'pdf';
      expect(downloadName(deck, compat, 'pdf')).assertEqual('开学_第一课_预览.pdf');
      compat.ext = 'ppt';
      expect(downloadName(deck, compat, 'source')).assertEqual('开学_第一课_原始文件.ppt');
    });

    it('resolves_relative_urls', 0, () => {
      const base: string = 'https://x/ppt/a/deck/c0e5/';
      const rel: PptFileInfo = new PptFileInfo();
      rel.s = 'preview.pdf';
      expect(fileUrl(base, rel)).assertEqual('https://x/ppt/a/deck/c0e5/preview.pdf');
      expect(fileUrl('https://x/base', rel)).assertEqual('https://x/base/preview.pdf');
      const abs: PptFileInfo = new PptFileInfo();
      abs.s = 'compat.pptx';
      abs.src = 'https://cdn/compat.pptx';
      expect(fileUrl(base, abs)).assertEqual('https://cdn/compat.pptx');
      const empty: PptFileInfo = new PptFileInfo();
      expect(fileUrl(base, empty)).assertEqual('');
    });

    it('parses_relative_manifest_files', 0, () => {
      const raw: string = '[{"id":"deck_2","title":"t","manifest":{"base":"https://x/ppt/a/deck_2/abc/",'
        + '"files":{"pdf":{"s":"preview.pdf","size":1105861,"pages":16,"name":"preview_cn.pdf"},'
        + '"compat":{"s":"compat.pptx","ext":"pptx","size":39063744}}}}]';
      const detail: PptDeckDetail | undefined = PptRepository.parseDetail(raw);
      expect(detail !== undefined).assertTrue();
      if (detail !== undefined) {
        expect(detail.base).assertEqual('https://x/ppt/a/deck_2/abc/');
        expect(detail.files.pdf !== undefined).assertTrue();
        if (detail.files.pdf !== undefined) {
          expect(detail.files.pdf.s).assertEqual('preview.pdf');
          expect(detail.files.pdf.name).assertEqual('preview_cn.pdf');
          expect(fileUrl(detail.base, detail.files.pdf))
            .assertEqual('https://x/ppt/a/deck_2/abc/preview.pdf');
        }
        expect(detail.files.source === undefined).assertTrue();
      }
    });

    it('soft_delete_and_owner_parse', 0, async () => {
      const api: FakeApi = new FakeApi();
      const repo: PptRepository = new PptRepository(api);
      const ok: boolean = await repo.softDelete('d1abc23def45', 1763200000000);
      expect(ok).assertTrue();
      expect(api.patchPaths[0].indexOf('ppt_decks?id=eq.d1abc23def45') === 0).assertTrue();
      expect(api.patchBodies[0].indexOf('"deleted":true') > 0).assertTrue();
      const list: PptDeck[] = PptRepository.parseList('[{"id":"d1","title":"t","owner_sid":"sid123","owner_name":"n","status":"ready"}]');
      expect(list.length).assertEqual(1);
      expect(list[0].ownerSid).assertEqual('sid123');
      api.failPosts = true;
      expect(await repo.softDelete('d1', 1)).assertFalse();
    });

    it('upload_repository_requests', 0, async () => {
      const api: FakeApi = new FakeApi();
      const repo: PptUploadRepository = new PptUploadRepository(api);
      const okCreate: boolean = await repo.createDeck('d1abc23def45', 'QA', 1024, 'pptx', 'QA.pptx', 'sid123', '测试账号', 1763200000000);
      expect(okCreate).assertTrue();
      expect(api.postPaths[0]).assertEqual('ppt_decks');
      expect(api.lastPostBody().indexOf('"id":"d1abc23def45"') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"status":"uploading"') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"owner_sid":"sid123"') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"client":"harmony"') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"source_name":"QA.pptx"') > 0).assertTrue();
      const okChunk: boolean = await repo.putChunk('d1abc23def45', 'sid123', 1, 'QUJD', 1763200000001);
      expect(okChunk).assertTrue();
      expect(api.postPaths[1]).assertEqual('ppt_upload_chunks');
      expect(api.lastPostBody().indexOf('"idx":1') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"data":"QUJD"') > 0).assertTrue();
      expect(api.lastPostBody().indexOf('"owner_sid":"sid123"') > 0).assertTrue();
      const okQueue: boolean = await repo.queue('d1abc23def45', 2, 1024, 1763200000002);
      expect(okQueue).assertTrue();
      expect(api.patchPaths[0].indexOf('ppt_decks?id=eq.d1abc23def45') === 0).assertTrue();
      expect(api.patchBodies[0].indexOf('"status":"queued"') > 0).assertTrue();
      expect(api.patchBodies[0].indexOf('"chunk_count":2') > 0).assertTrue();
      api.failPosts = true;
      expect(await repo.createDeck('d2', 'x', 1, 'pptx', 'x.pptx', 'sid123', 'n', 1)).assertFalse();
    });

    it('upload_planner_rules', 0, () => {
      expect(PptUploadPlanner.chunkCount(0)).assertEqual(0);
      expect(PptUploadPlanner.chunkCount(512 * 1024)).assertEqual(1);
      expect(PptUploadPlanner.chunkCount(512 * 1024 + 1)).assertEqual(2);
      expect(PptUploadPlanner.chunkRange(0, 512 * 1024 + 10)[1]).assertEqual(512 * 1024);
      expect(PptUploadPlanner.chunkRange(1, 512 * 1024 + 10)[0]).assertEqual(512 * 1024);
      expect(PptUploadPlanner.chunkRange(1, 512 * 1024 + 10)[1]).assertEqual(10);
      const id: string = PptUploadPlanner.deckId(1763200000000, 987654);
      expect(id.startsWith('d')).assertTrue();
      expect(id.length).assertEqual(13);
      expect(PptUploadPlanner.isSupported('a.pptx')).assertTrue();
      expect(PptUploadPlanner.isSupported('a.PPT')).assertTrue();
      expect(PptUploadPlanner.isSupported('a.pdf')).assertFalse();
      expect(PptUploadPlanner.titleOf('演示 文件.pptx')).assertEqual('演示 文件');
      expect(PptUploadPlanner.extOf('A.PPTX')).assertEqual('pptx');
      expect(PptUploadPlanner.validate('a.pdf', 1).length > 0).assertTrue();
      expect(PptUploadPlanner.validate('a.pptx', 0).length > 0).assertTrue();
      expect(PptUploadPlanner.validate('a.pptx', PptUploadPlanner.MAX_SIZE + 1).length > 0).assertTrue();
      expect(PptUploadPlanner.validate('a.pptx', 1024)).assertEqual('');
    });

    it('parses_slides_video_media', 0, () => {
      const raw: string = '[{"id":"d1","title":"t","manifest":{"base":"https://x/ppt/a/d1/b1/",'
        + '"slides":[{"steps":[{"img":"s1-1.webp"},{"img":"s1-2.webp","media":[{"src":"media1.mp4"}]}]},'
        + '{"steps":[{"img":"s2-1.webp"}]}],'
        + '"video":{"src":"deck.mp4","dur":303.6,"w":1280,"h":720,"chapters":[{"i":0,"t":0},{"i":1,"t":12}]},'
        + '"media_files":[{"s":"media/v1.mp4","name":"视频1.mp4","size":20158796,"kind":"video","slides":[7]}]}}]';
      const detail: PptDeckDetail | undefined = PptRepository.parseDetail(raw);
      expect(detail !== undefined).assertTrue();
      if (detail !== undefined) {
        expect(detail.slides.length).assertEqual(2);
        expect(detail.slides[0].steps.length).assertEqual(2);
        expect(detail.slides[0].steps[0].img).assertEqual('s1-1.webp');
        expect(detail.slides[0].steps[1].hasMedia).assertTrue();
        expect(detail.video !== undefined).assertTrue();
        if (detail.video !== undefined) {
          expect(detail.video.src).assertEqual('deck.mp4');
          expect(detail.video.chapters).assertEqual(2);
          expect(detail.video.width).assertEqual(1280);
          expect(detail.video.chapterList.length).assertEqual(2);
          expect(detail.video.chapterList[1].startSec).assertEqual(12);
        }
        expect(detail.mediaFiles.length).assertEqual(1);
        expect(detail.mediaFiles[0].name).assertEqual('视频1.mp4');
        expect(detail.mediaFiles[0].slides[0]).assertEqual(7);
        expect(resolveUrl(detail.base, detail.slides[0].steps[0].img))
          .assertEqual('https://x/ppt/a/d1/b1/s1-1.webp');
      }
    });

    it('status_labels', 0, () => {
      expect(pptStatusLabel('ready')).assertEqual('就绪');
      expect(pptStatusLabel('processing')).assertEqual('转换中');
      expect(pptStatusLabel('failed')).assertEqual('转换失败');
      expect(pptStatusLabel('weird')).assertEqual('上传中');
      expect(pptStatusColor('ready')).assertEqual('#4E9082');
    });
  });
}
