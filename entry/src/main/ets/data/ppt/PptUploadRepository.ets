import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob } from '../sync/JsonBlob';

/** 演示上传（`ppt_decks` 建行 + `ppt_upload_chunks` 分片 + 完成后置 queued）。 */
export class PptUploadRepository {
  private api: Api;

  constructor(api: Api) {
    this.api = api;
  }

  async createDeck(id: string, title: string, size: number, ext: string, sourceName: string,
    ownerSid: string, ownerName: string, nowMillis: number): Promise<boolean> {
    const row: Blob = {};
    row['id'] = id;
    row['title'] = title;
    row['owner_sid'] = ownerSid;
    row['owner_name'] = ownerName;
    row['client'] = 'harmony';
    row['status'] = 'uploading';
    row['progress'] = 0;
    row['source_name'] = sourceName;
    row['source_size'] = size;
    row['created_at'] = nowMillis;
    row['updated_at'] = nowMillis;
    const result: ApiResult = await this.api.post('ppt_decks', JSON.stringify(row), 'return=minimal', true);
    return result.ok;
  }

  async putChunk(deckId: string, ownerSid: string, idx: number, base64: string, nowMillis: number): Promise<boolean> {
    const row: Blob = {};
    row['deck_id'] = deckId;
    row['owner_sid'] = ownerSid;
    row['idx'] = idx;
    row['data'] = base64;
    row['ts'] = nowMillis;
    const prefer: string = 'resolution=merge-duplicates,return=minimal';
    const result: ApiResult = await this.api.post('ppt_upload_chunks', JSON.stringify(row), prefer, true);
    return result.ok;
  }

  async queue(deckId: string, chunkCount: number, size: number, nowMillis: number): Promise<boolean> {
    const row: Blob = {};
    row['status'] = 'queued';
    row['chunk_count'] = chunkCount;
    row['source_size'] = size;
    row['updated_at'] = nowMillis;
    const path: string = 'ppt_decks?id=eq.' + encodeURIComponent(deckId);
    const result: ApiResult = await this.api.patch(path, JSON.stringify(row), 'return=minimal', true);
    return result.ok;
  }
}
