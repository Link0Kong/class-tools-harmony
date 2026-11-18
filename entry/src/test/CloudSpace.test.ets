import { describe, it, expect } from '@ohos/hypium';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';
import {
  CloudSpaceDefaults,
  CloudSpaceError,
  CloudSpaceErrorKind,
  CloudSpaceErrors,
  CloudSpaceEvent,
  CloudSpaceFile,
  CloudSpaceResult,
  CloudSpaceSession,
  CloudSpaceSnapshot,
  CloudSpaceState,
  CloudSpaceUploadInit
} from '../main/ets/data/cloudspace/CloudSpaceModels';
import {
  CloudSpaceChunkPlan,
  CloudSpaceFileKind,
  CloudSpaceLogic,
  CloudSpaceMergedFiles
} from '../main/ets/data/cloudspace/CloudSpaceLogic';
import { CloudSpaceApi, CloudSpaceRequestSpec } from '../main/ets/data/cloudspace/CloudSpaceApi';

function fileOf(id: string, name: string, size: number, uploadedAt: number, url: string = 'u'): CloudSpaceFile {
  return new CloudSpaceFile(id, name, size, 'application/octet-stream', url, false, uploadedAt);
}

export default function cloudSpaceTest() {
  describe('CloudSpaceDefaults', () => {
    it('contract_constants', 0, () => {
      expect(CloudSpaceDefaults.BASE_URL).assertEqual('http://121.196.47.2/drop');
      expect(CloudSpaceDefaults.CHUNK_SIZE).assertEqual(8 * 1024 * 1024);
      expect(CloudSpaceDefaults.FILE_TTL_MS).assertEqual(72 * 60 * 60 * 1000);
      expect(CloudSpaceDefaults.MAX_FILES).assertEqual(300);
      expect(CloudSpaceDefaults.MAX_UPLOAD_CHUNKS).assertEqual(65536);
      expect(CloudSpaceDefaults.DOWNLOAD_URL_TTL_MINUTES).assertEqual(30);
    });
  });

  describe('CloudSpaceChunkPlan', () => {
    it('chunks_8mib', 0, () => {
      const zero: CloudSpaceChunkPlan = CloudSpaceLogic.chunkPlan(0);
      expect(zero.totalChunks).assertEqual(1);
      expect(zero.chunks[0].size()).assertEqual(0);
      const one: CloudSpaceChunkPlan = CloudSpaceLogic.chunkPlan(1);
      expect(one.totalChunks).assertEqual(1);
      expect(one.chunks[0].size()).assertEqual(1);
      const exact: CloudSpaceChunkPlan = CloudSpaceLogic.chunkPlan(CloudSpaceDefaults.CHUNK_SIZE);
      expect(exact.totalChunks).assertEqual(1);
      const oneMore: CloudSpaceChunkPlan = CloudSpaceLogic.chunkPlan(CloudSpaceDefaults.CHUNK_SIZE + 1);
      expect(oneMore.totalChunks).assertEqual(2);
      expect(oneMore.chunks[1].size()).assertEqual(1);
      expect(oneMore.chunks[1].start).assertEqual(CloudSpaceDefaults.CHUNK_SIZE);
      const twentyMb: CloudSpaceChunkPlan = CloudSpaceLogic.chunkPlan(20 * 1024 * 1024);
      expect(twentyMb.totalChunks).assertEqual(3);
      expect(twentyMb.chunks[2].size()).assertEqual(4 * 1024 * 1024);
      expect(CloudSpaceLogic.chunkPlan(10, 4).chunks.length).assertEqual(3);
      expect(CloudSpaceLogic.chunkPlan(10, 4).chunks[0].index).assertEqual(0);
    });
  });

  describe('CloudSpaceFormat', () => {
    it('fmt_size', 0, () => {
      expect(CloudSpaceLogic.fmtSize(0)).assertEqual('0 B');
      expect(CloudSpaceLogic.fmtSize(512)).assertEqual('512 B');
      expect(CloudSpaceLogic.fmtSize(1024)).assertEqual('1.0 KB');
      expect(CloudSpaceLogic.fmtSize(1536)).assertEqual('1.5 KB');
      expect(CloudSpaceLogic.fmtSize(2 * 1024 * 1024)).assertEqual('2.0 MB');
      expect(CloudSpaceLogic.fmtSize(20 * 1024 * 1024)).assertEqual('20 MB');
    });

    it('fmt_time_and_ttl', 0, () => {
      const millis: number = new Date(2026, 0, 2, 9, 5, 0).getTime();
      expect(CloudSpaceLogic.fmtTime(millis)).assertEqual('01-02 09:05');
      expect(CloudSpaceLogic.fmtTime(0)).assertEqual('');
      const now: number = 1000000;
      expect(CloudSpaceLogic.ttlText(now, now)).assertEqual('剩 3 天');
      expect(CloudSpaceLogic.ttlText(now, now + 24 * 3600000)).assertEqual('剩 2 天');
      expect(CloudSpaceLogic.ttlText(now, now + 47 * 3600000)).assertEqual('剩 1 天 1 小时');
      expect(CloudSpaceLogic.ttlText(now, now + 72 * 3600000)).assertEqual('已过期');
      expect(CloudSpaceLogic.ttlText(0, now)).assertEqual('已过期');
    });

    it('upload_percent_and_expired_hint', 0, () => {
      expect(CloudSpaceLogic.uploadPercent(0, 100)).assertEqual(0);
      expect(CloudSpaceLogic.uploadPercent(50, 100)).assertEqual(50);
      expect(CloudSpaceLogic.uploadPercent(100, 100)).assertEqual(99);
      expect(CloudSpaceLogic.uploadPercent(200, 100)).assertEqual(99);
      expect(CloudSpaceLogic.uploadPercent(5, 0)).assertEqual(0);
      expect(CloudSpaceLogic.expiredHint(2).indexOf('2 个文件已过期') >= 0).assertTrue();
      expect(CloudSpaceLogic.uploadStateText('waiting', '')).assertEqual('准备上传…');
      expect(CloudSpaceLogic.uploadStateText('failed', '磁盘不足')).assertEqual('磁盘不足');
    });
  });

  describe('CloudSpaceNaming', () => {
    it('safe_name', 0, () => {
      expect(CloudSpaceLogic.safeName('a/b\\c:d*e?f"g<h>i|j.png')).assertEqual('a_b_c_d_e_f_g_h_i_j.png');
      expect(CloudSpaceLogic.safeName('')).assertEqual('file');
      expect(CloudSpaceLogic.safeName('../..')).assertEqual('_');
      expect(CloudSpaceLogic.safeName('.hidden.txt')).assertEqual('hidden.txt');
      let longName: string = '';
      for (let i = 0; i < 200; i++) {
        longName += 'a';
      }
      longName += '.pdf';
      const safe: string = CloudSpaceLogic.safeName(longName);
      expect(safe.length <= 120).assertTrue();
      expect(safe.endsWith('.pdf')).assertTrue();
    });

    it('unique_name', 0, () => {
      expect(CloudSpaceLogic.uniqueName([], 'a.pdf')).assertEqual('a.pdf');
      expect(CloudSpaceLogic.uniqueName(['a.pdf'], 'a.pdf')).assertEqual('a (1).pdf');
      expect(CloudSpaceLogic.uniqueName(['a.pdf', 'a (1).pdf'], 'a.pdf')).assertEqual('a (2).pdf');
      expect(CloudSpaceLogic.uniqueName(['a'], 'a')).assertEqual('a (1)');
      expect(CloudSpaceLogic.sandboxFileName('f1', 'a.pdf')).assertEqual('f1_a.pdf');
    });

    it('mime_and_kind', 0, () => {
      expect(CloudSpaceLogic.mimeOf('a.PDF')).assertEqual('application/pdf');
      expect(CloudSpaceLogic.mimeOf('a.png')).assertEqual('image/png');
      expect(CloudSpaceLogic.mimeOf('a.unknown')).assertEqual('application/octet-stream');
      expect(CloudSpaceLogic.fileKind('', 'a.jpg')).assertEqual(CloudSpaceFileKind.IMAGE);
      expect(CloudSpaceLogic.fileKind('video/mp4', 'a.bin')).assertEqual(CloudSpaceFileKind.VIDEO);
      expect(CloudSpaceLogic.fileKind('', 'a.mp3')).assertEqual(CloudSpaceFileKind.AUDIO);
      expect(CloudSpaceLogic.fileKind('', 'a.zip')).assertEqual(CloudSpaceFileKind.ARCHIVE);
      expect(CloudSpaceLogic.fileKind('', 'a.pdf')).assertEqual(CloudSpaceFileKind.PDF);
      expect(CloudSpaceLogic.fileKind('', 'a.docx')).assertEqual(CloudSpaceFileKind.DOCUMENT);
      expect(CloudSpaceLogic.fileKind('', 'a.xyz')).assertEqual(CloudSpaceFileKind.OTHER);
      expect(CloudSpaceLogic.fileKindGlyph(CloudSpaceFileKind.IMAGE)).assertEqual('图');
      expect(CloudSpaceLogic.fileKindGlyph(CloudSpaceFileKind.PDF)).assertEqual('PDF');
      expect(CloudSpaceLogic.fileKindGlyph(CloudSpaceFileKind.OTHER)).assertEqual('件');
    });
  });

  describe('CloudSpaceEventMerge', () => {
    it('adds_sorts_and_deletes', 0, () => {
      const oldFile: CloudSpaceFile = fileOf('a', 'a.pdf', 10, 100);
      const addedEvent: CloudSpaceEvent = new CloudSpaceEvent();
      addedEvent.kind = 'file';
      addedEvent.seq = 2;
      addedEvent.file = fileOf('b', 'b.png', 20, 200);
      const deletedEvent: CloudSpaceEvent = new CloudSpaceEvent();
      deletedEvent.kind = 'filedel';
      deletedEvent.seq = 3;
      deletedEvent.fileId = 'a';
      const events: CloudSpaceEvent[] = [];
      events.push(addedEvent);
      events.push(deletedEvent);
      const merged: CloudSpaceMergedFiles = CloudSpaceLogic.applyEvents([oldFile], [], events);
      expect(merged.files.length).assertEqual(1);
      expect(merged.files[0].id).assertEqual('b');
      expect(merged.expiredCount()).assertEqual(0);
    });

    it('refreshes_url_and_handles_expired', 0, () => {
      const oldFile: CloudSpaceFile = fileOf('a', 'a.pdf', 10, 100, 'old-url');
      const refresh: CloudSpaceEvent = new CloudSpaceEvent();
      refresh.kind = 'file';
      refresh.seq = 2;
      refresh.file = fileOf('a', 'a.pdf', 10, 100, 'new-url');
      const merged: CloudSpaceMergedFiles = CloudSpaceLogic.applyEvents([oldFile], [], [refresh]);
      expect(merged.files.length).assertEqual(1);
      expect(merged.files[0].downloadUrl).assertEqual('new-url');

      const expired: CloudSpaceEvent = new CloudSpaceEvent();
      expired.kind = 'file';
      expired.seq = 3;
      expired.file = new CloudSpaceFile('a', 'a.pdf', 10, '', '', true, 100);
      const expiredMerged: CloudSpaceMergedFiles =
        CloudSpaceLogic.applyEvents(merged.files, merged.expiredIds, [expired]);
      expect(expiredMerged.files.length).assertEqual(0);
      expect(expiredMerged.expiredCount()).assertEqual(1);
    });

    it('snapshot_totals', 0, () => {
      const snapshot: CloudSpaceSnapshot = new CloudSpaceSnapshot();
      expect(snapshot.connected()).assertFalse();
      snapshot.session = new CloudSpaceSession('s1');
      snapshot.files.push(fileOf('a', 'a', 10, 1));
      snapshot.files.push(fileOf('b', 'b', 20, 2));
      expect(snapshot.connected()).assertTrue();
      expect(snapshot.count()).assertEqual(2);
      expect(snapshot.totalBytes()).assertEqual(30);
    });
  });

  describe('CloudSpaceErrors', () => {
    it('status_mapping', 0, () => {
      expect(CloudSpaceErrors.network().kind).assertEqual(CloudSpaceErrorKind.NETWORK);
      expect(CloudSpaceErrors.network().displayMessage()).assertEqual('云空间服务不可达，请检查网络后重试');
      expect(CloudSpaceErrors.http(401, '身份无效').kind).assertEqual(CloudSpaceErrorKind.TOKEN_INVALID);
      expect(CloudSpaceErrors.http(401, '身份无效').displayMessage()).assertEqual('身份无效');
      expect(CloudSpaceErrors.http(403).displayMessage().indexOf('过期') > 0).assertTrue();
      expect(CloudSpaceErrors.http(404).displayMessage().indexOf('不存在') > 0).assertTrue();
      expect(CloudSpaceErrors.http(413).displayMessage().indexOf('限制') > 0).assertTrue();
      expect(CloudSpaceErrors.http(507).displayMessage().indexOf('空间不足') > 0).assertTrue();
      expect(CloudSpaceErrors.http(500).displayMessage().indexOf('错误') > 0).assertTrue();
      expect(CloudSpaceErrors.http(418).displayMessage()).assertEqual('服务错误（HTTP 418）');
      expect(CloudSpaceErrors.rejected('').displayMessage()).assertEqual('云空间操作失败，请稍后重试');
      expect(CloudSpaceErrors.rejected('拒绝').displayMessage()).assertEqual('拒绝');
      expect(CloudSpaceErrors.parse().displayMessage().indexOf('响应异常') > 0).assertTrue();
      expect(CloudSpaceErrors.local('本地错误').displayMessage()).assertEqual('本地错误');
      const error: CloudSpaceError = CloudSpaceErrors.network();
      expect(error.displayMessage().indexOf('121.196') < 0).assertTrue();
    });

    it('reason_truncated_and_result_types', 0, () => {
      let longReason: string = '';
      for (let i = 0; i < 200; i++) {
        longReason += 'x';
      }
      expect(CloudSpaceErrors.http(500, longReason).displayMessage().length <= 120).assertTrue();
      const ok: CloudSpaceResult<number> = CloudSpaceResult.success<number>(3);
      expect(ok.ok).assertTrue();
      expect(ok.value).assertEqual(3);
      const bad: CloudSpaceResult<number> = CloudSpaceResult.failure<number>(CloudSpaceErrors.parse());
      expect(bad.ok).assertFalse();
      expect(bad.error !== undefined).assertTrue();
    });
  });

  describe('CloudSpaceApi', () => {
    it('url_and_headers', 0, () => {
      const api: CloudSpaceApi = new CloudSpaceApi('http://121.196.47.2/drop/');
      expect(api.baseUrl).assertEqual('http://121.196.47.2/drop');
      expect(api.url('/mine')).assertEqual('http://121.196.47.2/drop/mine');
      expect(api.url('state')).assertEqual('http://121.196.47.2/drop/state');
      const noToken: Record<string, string> = api.headers('');
      expect(noToken['X-Device-Id'] === undefined).assertTrue();
      const withToken: Record<string, string> = api.headers('token-1', CloudSpaceApi.APPLICATION_JSON);
      expect(withToken['X-Device-Id']).assertEqual('token-1');
      expect(withToken['Content-Type']).assertEqual('application/json');
      expect(withToken['Accept']).assertEqual('application/json');
      expect(CloudSpaceApi.normalizeBase('  http://x/drop///  ')).assertEqual('http://x/drop');
    });

    it('request_specs', 0, () => {
      const api: CloudSpaceApi = new CloudSpaceApi();
      const mine: CloudSpaceRequestSpec = api.mineSpec();
      expect(mine.method).assertEqual('GET');
      expect(mine.path).assertEqual('/mine');
      const open: CloudSpaceRequestSpec = api.openSpec();
      expect(open.method).assertEqual('POST');
      expect(open.bodyText).assertEqual('{}');
      const state: CloudSpaceRequestSpec = api.stateSpec('s 1', 7);
      expect(state.path.indexOf('sessionId=s%201') > 0).assertTrue();
      expect(state.path.indexOf('since=7') > 0).assertTrue();
      const init: CloudSpaceRequestSpec = api.initSpec('s1', 'a.pdf', 1024, 'application/pdf', 1);
      expect(init.bodyText.indexOf('"totalChunks":1') > 0).assertTrue();
      expect(init.bodyText.indexOf('"sessionId":"s1"') > 0).assertTrue();
      const chunk: CloudSpaceRequestSpec = api.chunkSpec('u1', 2);
      expect(chunk.path).assertEqual('/upload/chunk?uploadId=u1&index=2');
      expect(chunk.contentType).assertEqual('application/octet-stream');
      const finish: CloudSpaceRequestSpec = api.finishSpec('s1', 'u1');
      expect(finish.path).assertEqual('/upload/finish');
      const del: CloudSpaceRequestSpec = api.deleteSpec('f/1', 's1');
      expect(del.method).assertEqual('DELETE');
      expect(del.path.indexOf('/file/f%2F1') >= 0).assertTrue();
      const close: CloudSpaceRequestSpec = api.closeSpec('s1');
      expect(close.bodyText.indexOf('"sessionId":"s1"') > 0).assertTrue();
    });

    it('interpret_status_and_ok_false', 0, () => {
      const ok: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(200, '{"ok":true,"session":null}');
      expect(ok.ok).assertTrue();
      const rejected: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(200, '{"ok":false,"reason":"文件数超限"}');
      expect(rejected.ok).assertFalse();
      expect(rejected.error!.displayMessage()).assertEqual('文件数超限');
      const unauthorized: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(401, '{"ok":false,"reason":"身份无效"}');
      expect(unauthorized.ok).assertFalse();
      expect(unauthorized.error!.kind).assertEqual(CloudSpaceErrorKind.TOKEN_INVALID);
      const serverError: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(507, '{"ok":false,"reason":"磁盘不足"}');
      expect(serverError.error!.displayMessage()).assertEqual('磁盘不足');
      const nonJson: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(200, 'not-json');
      expect(nonJson.ok).assertFalse();
      expect(nonJson.error!.kind).assertEqual(CloudSpaceErrorKind.PARSE);
      const notFound: CloudSpaceResult<Blob> = CloudSpaceApi.interpret(404, '{"reason":"文件已过期"}');
      expect(notFound.error!.displayMessage()).assertEqual('文件已过期');
    });

    it('parse_session_state_init_file', 0, () => {
      const sessionBlob: Blob | undefined = JsonBlob.parse('{"id":"s1","code":"123456","createdAt":1,"expiresAt":2}');
      const session: CloudSpaceSession | undefined = CloudSpaceApi.parseSessionNode(sessionBlob);
      expect(session !== undefined).assertTrue();
      expect(session!.id).assertEqual('s1');
      expect(CloudSpaceApi.parseSessionNode(JsonBlob.parse('{"code":"x"}')) === undefined).assertTrue();
      expect(CloudSpaceApi.parseSessionNode(undefined) === undefined).assertTrue();

      const stateJson: string = '{"ok":true,"session":{"id":"s1"},"cursor":5,"events":['
        + '{"seq":4,"kind":"file","at":1000,"payload":{"fileId":"f1","name":"a.pdf","size":10,'
        + '"mime":"application/pdf","downloadUrl":"http://x/f/1?s=1"}},'
        + '{"seq":5,"kind":"filedel","payload":{"fileId":"f0"}},'
        + '{"seq":6,"kind":"text","payload":{"text":"hi"}}]}';
      const stateBlob: Blob = JsonBlob.parse(stateJson)!;
      const state: CloudSpaceState = CloudSpaceApi.parseState(stateBlob);
      expect(state.session !== undefined).assertTrue();
      expect(state.events.length).assertEqual(2);
      expect(state.events[0].kind).assertEqual('file');
      expect(state.events[0].file!.name).assertEqual('a.pdf');
      expect(state.events[0].file!.uploadedAt).assertEqual(1000);
      expect(state.events[0].file!.expired).assertFalse();
      expect(state.events[1].kind).assertEqual('filedel');
      expect(state.events[1].fileId).assertEqual('f0');
      expect(state.cursor).assertEqual(5);

      const expiredState: CloudSpaceState = CloudSpaceApi.parseState(
        JsonBlob.parse('{"events":[{"seq":1,"kind":"file","at":1,"payload":{"fileId":"f","name":"n","size":1}}]}')!);
      expect(expiredState.events[0].file!.expired).assertTrue();
      expect(expiredState.events[0].file!.downloadUrl).assertEqual('');
      expect(expiredState.cursor).assertEqual(1);

      const init: CloudSpaceUploadInit | undefined =
        CloudSpaceApi.parseInit(JsonBlob.parse('{"uploadId":"u1"}')!);
      expect(init !== undefined).assertTrue();
      expect(init!.chunkSize).assertEqual(CloudSpaceDefaults.CHUNK_SIZE);
      expect(CloudSpaceApi.parseInit(JsonBlob.parse('{}')!) === undefined).assertTrue();

      const finished: CloudSpaceFile | undefined = CloudSpaceApi.parseFinishedFile(
        JsonBlob.parse('{"file":{"id":"f2","name":"b.png","size":20,"mime":"image/png","downloadUrl":"http://x"}}')!);
      expect(finished !== undefined).assertTrue();
      expect(finished!.id).assertEqual('f2');
      expect(finished!.downloadUrl).assertEqual('http://x');
      expect(CloudSpaceApi.parseDeleted(JsonBlob.parse('{"deleted":true}')!)).assertTrue();
      expect(CloudSpaceApi.parseDeleted(JsonBlob.parse('{"deleted":false}')!)).assertFalse();
      expect(CloudSpaceApi.parseReceived(JsonBlob.parse('{"received":42}')!)).assertEqual(42);
    });
  });
}
