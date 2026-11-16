import { Blob, JsonBlob } from '../sync/JsonBlob';
import {
  CloudSpaceDefaults,
  CloudSpaceError,
  CloudSpaceErrors,
  CloudSpaceEvent,
  CloudSpaceFile,
  CloudSpaceResult,
  CloudSpaceSession,
  CloudSpaceState,
  CloudSpaceUploadInit
} from './CloudSpaceModels';

/**
 * ECS drop 服务 API 客户端（契约 `web/drop/CONTRACT.md` v2.2）——**纯请求描述 + 响应解析**。
 *
 * 接口：
 * - `GET  /mine`                          是否有活动会话（不创建）
 * - `POST /open`                          惰性创建/复用本账号会话（同 sid 跨设备自动互见）
 * - `GET  /state?sessionId=&since=`       事件列表（`file` 事件带签名 downloadUrl；`filedel` 表示删除）
 * - `POST /upload/init`                   分片上传初始化（返回 uploadId/chunkSize）
 * - `POST /upload/chunk?uploadId=&index=` 原始字节分片（8MiB，`Content-Type: application/octet-stream`）
 * - `POST /upload/finish`                 拼接完成（返回 file 并追加 file 事件）
 * - `DELETE /file/<fileId>?sessionId=`    单文件删除（幂等）
 * - `POST /close`                         清空：删除会话与全部文件
 *
 * 鉴权：所有请求带 `X-Device-Id: <班级 token>`。**token 只出现在请求头**：
 * 不进 URL / 请求体 / 日志 / 错误文案 / 落盘。本文件不 import 网络/文件 API，hypium 可直接测。
 */
export class CloudSpaceRequestSpec {
  method: string = 'GET';
  /** 相对路径（以 `/` 开头），由 [CloudSpaceApi.url] 拼到基址。 */
  path: string = '';
  /** JSON 请求体文本（GET/DELETE 为空）。 */
  bodyText: string = '';
  /** 请求体类型：''（无）、'application/json'、'application/octet-stream'。 */
  contentType: string = '';
  /** 是否携带班级 token（`X-Device-Id`）。 */
  authenticated: boolean = true;
}

export class CloudSpaceApi {
  static readonly APPLICATION_JSON: string = 'application/json';
  static readonly OCTET_STREAM: string = 'application/octet-stream';

  /** 规范化基址（**结尾不带 `/`**）；`url("/state")` → `<base>/state`。 */
  baseUrl: string = CloudSpaceDefaults.BASE_URL;

  constructor(baseUrl: string = CloudSpaceDefaults.BASE_URL) {
    this.baseUrl = CloudSpaceApi.normalizeBase(baseUrl);
  }

  static normalizeBase(baseUrl: string): string {
    let base: string = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /** 拼接完整 URL；`path` 自带 query。 */
  url(path: string): string {
    if (path.length === 0) {
      return this.baseUrl;
    }
    return path.startsWith('/') ? this.baseUrl + path : this.baseUrl + '/' + path;
  }

  /**
   * 统一请求头：token 只在 `X-Device-Id`，其余为 JSON/缓存约定。
   * 空 token 不发该头（避免把空串当身份）。
   */
  headers(token: string, contentType: string = ''): Record<string, string> {
    const headers: Record<string, string> = {};
    const trimmed: string = token.trim();
    if (trimmed.length > 0) {
      headers['X-Device-Id'] = trimmed;
    }
    headers['Accept'] = 'application/json';
    headers['Cache-Control'] = 'no-store';
    if (contentType.length > 0) {
      headers['Content-Type'] = contentType;
    }
    return headers;
  }

  // ---- 请求描述 -----------------------------------------------------------

  mineSpec(): CloudSpaceRequestSpec {
    return CloudSpaceApi.spec('GET', '/mine');
  }

  openSpec(): CloudSpaceRequestSpec {
    const spec: CloudSpaceRequestSpec = CloudSpaceApi.spec('POST', '/open');
    spec.bodyText = '{}';
    spec.contentType = CloudSpaceApi.APPLICATION_JSON;
    return spec;
  }

  stateSpec(sessionId: string, since: number): CloudSpaceRequestSpec {
    const path: string = '/state?sessionId=' + encodeURIComponent(sessionId)
      + '&since=' + Math.max(0, Math.floor(since));
    return CloudSpaceApi.spec('GET', path);
  }

  initSpec(sessionId: string, name: string, size: number, mimeType: string, totalChunks: number): CloudSpaceRequestSpec {
    const spec: CloudSpaceRequestSpec = CloudSpaceApi.spec('POST', '/upload/init');
    const body: Blob = {};
    body['sessionId'] = sessionId;
    body['name'] = name;
    body['size'] = Math.max(0, Math.floor(size));
    body['mime'] = mimeType.length > 0 ? mimeType : CloudSpaceApi.OCTET_STREAM;
    body['totalChunks'] = Math.max(1, Math.floor(totalChunks));
    spec.bodyText = JsonBlob.encode(body);
    spec.contentType = CloudSpaceApi.APPLICATION_JSON;
    return spec;
  }

  chunkSpec(uploadId: string, index: number): CloudSpaceRequestSpec {
    const path: string = '/upload/chunk?uploadId=' + encodeURIComponent(uploadId)
      + '&index=' + Math.max(0, Math.floor(index));
    const spec: CloudSpaceRequestSpec = CloudSpaceApi.spec('POST', path);
    spec.contentType = CloudSpaceApi.OCTET_STREAM;
    return spec;
  }

  finishSpec(sessionId: string, uploadId: string): CloudSpaceRequestSpec {
    const spec: CloudSpaceRequestSpec = CloudSpaceApi.spec('POST', '/upload/finish');
    const body: Blob = {};
    body['sessionId'] = sessionId;
    body['uploadId'] = uploadId;
    spec.bodyText = JsonBlob.encode(body);
    spec.contentType = CloudSpaceApi.APPLICATION_JSON;
    return spec;
  }

  deleteSpec(fileId: string, sessionId: string): CloudSpaceRequestSpec {
    const path: string = '/file/' + encodeURIComponent(fileId) + '?sessionId=' + encodeURIComponent(sessionId);
    return CloudSpaceApi.spec('DELETE', path);
  }

  closeSpec(sessionId: string): CloudSpaceRequestSpec {
    const spec: CloudSpaceRequestSpec = CloudSpaceApi.spec('POST', '/close');
    const body: Blob = {};
    body['sessionId'] = sessionId;
    spec.bodyText = JsonBlob.encode(body);
    spec.contentType = CloudSpaceApi.APPLICATION_JSON;
    return spec;
  }

  // ---- 响应解释 -----------------------------------------------------------

  /**
   * HTTP 状态 + 响应体 → 统一结果：
   * - 非 2xx：优先服务端 `{ok:false,reason}`；
   * - 2xx 但 `ok:false` → rejected；
   * - 非 JSON / 不符合契约 → parse。
   */
  static interpret(status: number, bodyText: string): CloudSpaceResult<Blob> {
    const parsed: Blob | undefined = JsonBlob.parse(bodyText);
    if (status < 200 || status >= 300) {
      const reason: string = parsed !== undefined
        ? JsonBlob.asString(JsonBlob.get(parsed, 'reason'), '') : '';
      return CloudSpaceResult.failure<Blob>(CloudSpaceErrors.http(status, reason));
    }
    if (parsed === undefined) {
      return CloudSpaceResult.failure<Blob>(CloudSpaceErrors.parse());
    }
    if (JsonBlob.asBoolean(JsonBlob.get(parsed, 'ok'), true) === false) {
      return CloudSpaceResult.failure<Blob>(
        CloudSpaceErrors.rejected(JsonBlob.asString(JsonBlob.get(parsed, 'reason'), '')));
    }
    return CloudSpaceResult.success<Blob>(parsed);
  }

  /** `/mine` / `/state` / `/open` 的 session 节点 → 会话；缺失/非法返回 undefined。 */
  static parseSessionNode(blob: Blob | undefined): CloudSpaceSession | undefined {
    if (blob === undefined) {
      return undefined;
    }
    const id: string = JsonBlob.asString(JsonBlob.get(blob, 'id'), '').trim();
    if (id.length === 0) {
      return undefined;
    }
    return new CloudSpaceSession(
      id,
      JsonBlob.asString(JsonBlob.get(blob, 'code'), ''),
      JsonBlob.asNumber(JsonBlob.get(blob, 'createdAt'), 0),
      JsonBlob.asNumber(JsonBlob.get(blob, 'expiresAt'), 0));
  }

  /** `/state` 响应 → 事件列表 + cursor。 */
  static parseState(blob: Blob): CloudSpaceState {
    const state: CloudSpaceState = new CloudSpaceState();
    state.session = CloudSpaceApi.parseSessionNode(JsonBlob.asBlob(JsonBlob.get(blob, 'session')));
    const rawEvents: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(blob, 'events'));
    let maxSeq: number = 0;
    if (rawEvents !== undefined) {
      for (let i = 0; i < rawEvents.length; i++) {
        const eventBlob: Blob | undefined = JsonBlob.asBlob(rawEvents[i]);
        if (eventBlob === undefined) {
          continue;
        }
        const event: CloudSpaceEvent | undefined = CloudSpaceApi.parseEvent(eventBlob);
        if (event !== undefined) {
          state.events.push(event);
          if (event.seq > maxSeq) {
            maxSeq = event.seq;
          }
        }
      }
    }
    const cursor: number = JsonBlob.asNumber(JsonBlob.get(blob, 'cursor'), -1);
    state.cursor = cursor >= 0 ? cursor : maxSeq;
    return state;
  }

  /** `/upload/init` 响应 → uploadId/chunkSize；uploadId 缺失返回 undefined。 */
  static parseInit(blob: Blob): CloudSpaceUploadInit | undefined {
    const uploadId: string = JsonBlob.asString(JsonBlob.get(blob, 'uploadId'), '').trim();
    if (uploadId.length === 0) {
      return undefined;
    }
    const init: CloudSpaceUploadInit = new CloudSpaceUploadInit();
    init.uploadId = uploadId;
    const chunkSize: number = JsonBlob.asNumber(JsonBlob.get(blob, 'chunkSize'), 0);
    init.chunkSize = chunkSize > 0 ? Math.floor(chunkSize) : CloudSpaceDefaults.CHUNK_SIZE;
    return init;
  }

  /** `/upload/finish` 响应 → 新文件；缺失返回 undefined。 */
  static parseFinishedFile(blob: Blob): CloudSpaceFile | undefined {
    return CloudSpaceApi.parseFileObject(JsonBlob.asBlob(JsonBlob.get(blob, 'file')), 0);
  }

  /** `DELETE /file` 响应 → 是否真的删除了（幂等：不存在返回 false 也算成功）。 */
  static parseDeleted(blob: Blob): boolean {
    return JsonBlob.asBoolean(JsonBlob.get(blob, 'deleted'), false);
  }

  /** `/upload/chunk` 响应 → 服务端累计已收字节（仅诊断用）。 */
  static parseReceived(blob: Blob): number {
    return JsonBlob.asNumber(JsonBlob.get(blob, 'received'), 0);
  }

  // ---- 解析小工具 ---------------------------------------------------------

  private static parseEvent(blob: Blob): CloudSpaceEvent | undefined {
    const kind: string = JsonBlob.asString(JsonBlob.get(blob, 'kind'), '');
    const seq: number = JsonBlob.asNumber(JsonBlob.get(blob, 'seq'), 0);
    const at: number = JsonBlob.asNumber(JsonBlob.get(blob, 'at'), 0);
    const payload: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'payload'));
    if (kind === 'file') {
      const file: CloudSpaceFile | undefined = CloudSpaceApi.parseFileObject(payload, at);
      if (file === undefined) {
        return undefined;
      }
      const event: CloudSpaceEvent = new CloudSpaceEvent();
      event.kind = 'file';
      event.seq = seq;
      event.file = file;
      return event;
    }
    if (kind === 'filedel') {
      if (payload === undefined) {
        return undefined;
      }
      let fileId: string = JsonBlob.asString(JsonBlob.get(payload, 'fileId'), '');
      if (fileId.length === 0) {
        fileId = JsonBlob.asString(JsonBlob.get(payload, 'id'), '');
      }
      if (fileId.length === 0) {
        return undefined;
      }
      const event: CloudSpaceEvent = new CloudSpaceEvent();
      event.kind = 'filedel';
      event.seq = seq;
      event.fileId = fileId;
      return event;
    }
    // text / cmd 事件与本页无关，忽略。
    return undefined;
  }

  /**
   * 文件对象解析：`/state` 的 file 事件 payload 用 `fileId`，
   * `/upload/finish` 响应用 `id`，两者都兼容。
   */
  private static parseFileObject(blob: Blob | undefined, uploadedAt: number): CloudSpaceFile | undefined {
    if (blob === undefined) {
      return undefined;
    }
    let fileId: string = JsonBlob.asString(JsonBlob.get(blob, 'fileId'), '');
    if (fileId.length === 0) {
      fileId = JsonBlob.asString(JsonBlob.get(blob, 'id'), '');
    }
    if (fileId.length === 0) {
      return undefined;
    }
    const downloadUrl: string = JsonBlob.asString(JsonBlob.get(blob, 'downloadUrl'), '');
    const expired: boolean = JsonBlob.asBoolean(JsonBlob.get(blob, 'expired'), false)
      || downloadUrl.length === 0;
    let name: string = JsonBlob.asString(JsonBlob.get(blob, 'name'), '');
    if (name.length === 0) {
      name = '文件';
    }
    return new CloudSpaceFile(
      fileId,
      name,
      JsonBlob.asNumber(JsonBlob.get(blob, 'size'), 0),
      JsonBlob.asString(JsonBlob.get(blob, 'mime'), ''),
      expired ? '' : downloadUrl,
      expired,
      uploadedAt);
  }

  private static spec(method: string, path: string): CloudSpaceRequestSpec {
    const spec: CloudSpaceRequestSpec = new CloudSpaceRequestSpec();
    spec.method = method;
    spec.path = path;
    return spec;
  }
}
