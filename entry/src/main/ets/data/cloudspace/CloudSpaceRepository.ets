import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { wantConstant, Want } from '@kit.AbilityKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { Blob } from '../sync/JsonBlob';
import { CloudSpaceApi, CloudSpaceRequestSpec } from './CloudSpaceApi';
import {
  CloudSpaceDefaults,
  CloudSpaceError,
  CloudSpaceErrors,
  CloudSpaceFile,
  CloudSpaceResult,
  CloudSpaceSession,
  CloudSpaceSnapshot,
  CloudSpaceUploadInit,
  CloudSpaceUploadProgress,
  CloudSpaceUploadState
} from './CloudSpaceModels';
import { CloudSpaceLogic } from './CloudSpaceLogic';

const TAG: string = 'CloudSpaceRepo';

/** 一次 HTTP 响应的原始结果（内部用）。 */
class RawResponse {
  status: number = 0;
  body: string = '';
}

/** 本机选中的待上传文件。 */
export class PickedFile {
  uri: string = '';
  name: string = '';
  sizeBytes: number = 0;
  mimeType: string = '';
}

/**
 * 临时云空间仓库：会话生命周期 + 列表事件合并 + 分片上传 + 删除/清空 + 下载。
 *
 * 设计要点（对齐网页/小程序/安卓）：
 * - 同账号跨设备自动共享：先 `GET /mine`，无会话再 `POST /open`（**不展示房间码/配对**）；
 * - 列表以 `/state` 为准：`since=0` 全量重建（force），否则按 cursor 增量合并（file/filedel）；
 * - 下载链接 30 分钟有效且每次 `/state` 重签：下载前强拉一次最新链接；
 * - 上传：`init → chunk × N（8MiB 原始字节）→ finish`，逐片回调进度；
 * - 所有公开方法不抛异常（网络/解析错误以 [CloudSpaceResult.Failure] 返回）；
 * - **班级 token 只出现在 `X-Device-Id` 请求头**，不落盘、不打日志、不进错误文案。
 */
export class CloudSpaceRepository {
  private api: CloudSpaceApi;
  private tokenProvider: () => string;
  private now: () => number;
  private chunkSize: number;

  private session: CloudSpaceSession | undefined = undefined;
  private files: CloudSpaceFile[] = [];
  private expiredIds: string[] = [];
  private cursor: number = 0;

  constructor(tokenProvider: () => string, baseUrl: string = CloudSpaceDefaults.BASE_URL,
    now: () => number = () => Date.now(), chunkSize: number = CloudSpaceDefaults.CHUNK_SIZE) {
    this.api = new CloudSpaceApi(baseUrl);
    this.tokenProvider = tokenProvider;
    this.now = now;
    this.chunkSize = chunkSize;
  }

  /** 当前列表快照（只读）。 */
  snapshot(): CloudSpaceSnapshot {
    const snapshot: CloudSpaceSnapshot = new CloudSpaceSnapshot();
    snapshot.session = this.session;
    snapshot.files = this.files.slice(0);
    snapshot.expiredCount = this.expiredIds.length;
    snapshot.cursor = this.cursor;
    return snapshot;
  }

  /** 退出登录/切换账号时清空内存状态（不向服务端发请求）。 */
  reset(): void {
    this.session = undefined;
    this.files = [];
    this.expiredIds = [];
    this.cursor = 0;
  }

  // ---- 会话 + 列表 ---------------------------------------------------------

  /** 确保已连接本账号云空间：`/mine` → 无会话则 `/open` → 全量拉列表。 */
  async ensureSpace(): Promise<CloudSpaceResult<CloudSpaceSnapshot>> {
    if (this.session !== undefined) {
      return await this.refresh(true);
    }
    const sessionResult: CloudSpaceResult<CloudSpaceSession> = await this.resolveSession();
    if (!sessionResult.ok) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(
        sessionResult.error !== undefined ? sessionResult.error : CloudSpaceErrors.parse());
    }
    this.session = sessionResult.value;
    this.files = [];
    this.expiredIds = [];
    this.cursor = 0;
    return await this.refresh(true);
  }

  /** 刷新列表：force = `since=0` 全量重建；false = 增量。失败时保留上一次列表。 */
  async refresh(force: boolean): Promise<CloudSpaceResult<CloudSpaceSnapshot>> {
    if (this.session === undefined) {
      return await this.ensureSpace();
    }
    const session: CloudSpaceSession = this.session;
    const since: number = force ? 0 : this.cursor;
    const spec: CloudSpaceRequestSpec = this.api.stateSpec(session.id, since);
    const result: CloudSpaceResult<Blob> = await this.request(spec);
    if (!result.ok) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(
        result.error !== undefined ? result.error : CloudSpaceErrors.parse());
    }
    const state = CloudSpaceApi.parseState(result.value!);
    const merged = CloudSpaceLogic.applyEvents(force ? [] : this.files, force ? [] : this.expiredIds, state.events);
    this.session = state.session !== undefined ? state.session : session;
    this.files = merged.files;
    this.expiredIds = merged.expiredIds;
    this.cursor = force ? state.cursor : Math.max(this.cursor, state.cursor);
    return CloudSpaceResult.success<CloudSpaceSnapshot>(this.snapshot());
  }

  /** 下载前调用：强拉一次最新列表并返回该文件（带 30 分钟有效的签名下载链接）。 */
  async findFreshFile(fileId: string): Promise<CloudSpaceResult<CloudSpaceFile>> {
    if (fileId.trim().length === 0) {
      return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.local('文件不存在或已被删除'));
    }
    const refreshed: CloudSpaceResult<CloudSpaceSnapshot> = await this.refresh(true);
    if (!refreshed.ok) {
      return CloudSpaceResult.failure<CloudSpaceFile>(
        refreshed.error !== undefined ? refreshed.error : CloudSpaceErrors.parse());
    }
    let found: CloudSpaceFile | undefined = undefined;
    for (let i = 0; i < this.files.length; i++) {
      if (this.files[i].id === fileId) {
        found = this.files[i];
        break;
      }
    }
    if (found === undefined) {
      return CloudSpaceResult.failure<CloudSpaceFile>(
        CloudSpaceErrors.local('文件已过期或已被删除（上传超过 72 小时）'));
    }
    if (found.expired || found.downloadUrl.length === 0) {
      return CloudSpaceResult.failure<CloudSpaceFile>(
        CloudSpaceErrors.local('文件已过期（上传超过 72 小时，已自动删除）'));
    }
    return CloudSpaceResult.success<CloudSpaceFile>(found);
  }

  // ---- 上传 ---------------------------------------------------------------

  /** 打开文件选择器（任意类型，单选）；取消返回 undefined。 */
  async pickFile(): Promise<PickedFile | undefined> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return undefined;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await viewPicker.select(options);
      if (uris.length === 0) {
        return undefined;
      }
      const uri: string = uris[0];
      const name: string = CloudSpaceRepository.baseName(uri);
      let size: number = 0;
      try {
        const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        size = fs.statSync(file.fd).size;
        fs.closeSync(file);
      } catch (e) {
        size = 0;
      }
      const picked: PickedFile = new PickedFile();
      picked.uri = uri;
      picked.name = CloudSpaceLogic.safeName(name);
      picked.sizeBytes = size;
      picked.mimeType = CloudSpaceLogic.mimeOf(picked.name);
      return picked;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.w(TAG, '选择文件失败 code=' + err.code);
      return undefined;
    }
  }

  /**
   * 分片上传一个文件（任意大小；8MiB/片，逐片回调进度）。
   *
   * 失败语义：任何一片失败都立即停止（服务端残留分片由 24h 清理线程回收，重传同 index 可覆盖）。
   */
  async upload(picked: PickedFile,
    onProgress: (progress: CloudSpaceUploadProgress) => void): Promise<CloudSpaceResult<CloudSpaceFile>> {
    const size: number = Math.floor(picked.sizeBytes);
    if (size <= 0) {
      return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.local('空文件无法上传（0 字节）'));
    }
    const plan = CloudSpaceLogic.chunkPlan(size, this.chunkSize);
    if (plan.totalChunks > CloudSpaceDefaults.MAX_UPLOAD_CHUNKS) {
      return CloudSpaceResult.failure<CloudSpaceFile>(
        CloudSpaceErrors.local('文件超过服务上限（约 512 GB），请压缩后重试'));
    }
    let session: CloudSpaceSession | undefined = this.session;
    if (session === undefined) {
      const resolved: CloudSpaceResult<CloudSpaceSession> = await this.resolveSession();
      if (!resolved.ok) {
        return CloudSpaceResult.failure<CloudSpaceFile>(
          resolved.error !== undefined ? resolved.error : CloudSpaceErrors.parse());
      }
      session = resolved.value;
      this.session = session;
    }
    if (session === undefined) {
      return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.parse());
    }
    const sessionId: string = session.id;
    const name: string = CloudSpaceLogic.safeName(picked.name);
    const mime: string = picked.mimeType.length > 0 ? picked.mimeType : 'application/octet-stream';
    onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.WAITING, 0, size));

    const initResult: CloudSpaceResult<Blob> =
      await this.request(this.api.initSpec(sessionId, name, size, mime, plan.totalChunks));
    if (!initResult.ok) {
      onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.FAILED, 0, size,
        initResult.error !== undefined ? initResult.error.displayMessage() : '上传初始化失败'));
      return CloudSpaceResult.failure<CloudSpaceFile>(
        initResult.error !== undefined ? initResult.error : CloudSpaceErrors.parse());
    }
    const init: CloudSpaceUploadInit | undefined = CloudSpaceApi.parseInit(initResult.value!);
    if (init === undefined) {
      return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.parse());
    }
    if (init.chunkSize !== plan.chunkSize) {
      return CloudSpaceResult.failure<CloudSpaceFile>(
        CloudSpaceErrors.local('云空间分片大小异常（' + init.chunkSize + ' B），请稍后重试'));
    }

    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(picked.uri, fs.OpenMode.READ_ONLY);
    } catch (e) {
      return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.local('读取文件失败，请重新选择文件'));
    }
    try {
      for (let i = 0; i < plan.chunks.length; i++) {
        const chunk = plan.chunks[i];
        const length: number = chunk.size();
        if (length <= 0) {
          continue;
        }
        const buffer: ArrayBuffer = new ArrayBuffer(length);
        let read: number = 0;
        try {
          read = fs.readSync(file.fd, buffer, { offset: chunk.start, length: length });
        } catch (e) {
          onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.FAILED, chunk.start, size,
            '读取文件失败，请重新选择文件'));
          return CloudSpaceResult.failure<CloudSpaceFile>(
            CloudSpaceErrors.local('读取文件失败，请重新选择文件'));
        }
        if (read !== length) {
          onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.FAILED, chunk.start, size,
            '文件读取不完整（可能已被移动或截断），请重新选择文件'));
          return CloudSpaceResult.failure<CloudSpaceFile>(
            CloudSpaceErrors.local('文件读取不完整（可能已被移动或截断），请重新选择文件'));
        }
        onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.UPLOADING, chunk.start, size));
        const chunkSpec: CloudSpaceRequestSpec = this.api.chunkSpec(init.uploadId, chunk.index);
        const chunkResult: CloudSpaceResult<Blob> =
          await this.request(chunkSpec, buffer);
        if (!chunkResult.ok) {
          onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.FAILED, chunk.start, size,
            chunkResult.error !== undefined ? chunkResult.error.displayMessage() : '分片上传失败'));
          return CloudSpaceResult.failure<CloudSpaceFile>(
            chunkResult.error !== undefined ? chunkResult.error : CloudSpaceErrors.parse());
        }
        onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.UPLOADING, chunk.endExclusive, size));
      }
      onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.UPLOADING, size, size, '正在完成…'));
      const finishResult: CloudSpaceResult<Blob> =
        await this.request(this.api.finishSpec(sessionId, init.uploadId));
      if (!finishResult.ok) {
        onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.FAILED, size, size,
          finishResult.error !== undefined ? finishResult.error.displayMessage() : '上传完成失败'));
        return CloudSpaceResult.failure<CloudSpaceFile>(
          finishResult.error !== undefined ? finishResult.error : CloudSpaceErrors.parse());
      }
      const finished: CloudSpaceFile | undefined = CloudSpaceApi.parseFinishedFile(finishResult.value!);
      if (finished === undefined) {
        return CloudSpaceResult.failure<CloudSpaceFile>(CloudSpaceErrors.parse());
      }
      const stored: CloudSpaceFile = new CloudSpaceFile(finished.id, finished.name, finished.sizeBytes,
        finished.mimeType, finished.downloadUrl, false, this.now());
      const remaining: CloudSpaceFile[] = [];
      for (let i = 0; i < this.files.length; i++) {
        if (this.files[i].id !== stored.id) {
          remaining.push(this.files[i]);
        }
      }
      remaining.push(stored);
      remaining.sort((a: CloudSpaceFile, b: CloudSpaceFile) => b.uploadedAt - a.uploadedAt);
      this.files = remaining;
      onProgress(new CloudSpaceUploadProgress(CloudSpaceUploadState.DONE, size, size));
      return CloudSpaceResult.success<CloudSpaceFile>(stored);
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 忽略关闭失败
        }
      }
    }
  }

  // ---- 删除 / 清空 ---------------------------------------------------------

  /** 删除单个文件（幂等；成功后从本地列表移除）。 */
  async delete(fileId: string): Promise<CloudSpaceResult<CloudSpaceSnapshot>> {
    if (fileId.trim().length === 0) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(CloudSpaceErrors.local('文件不存在或已被删除'));
    }
    const session: CloudSpaceSession | undefined = this.session;
    if (session === undefined) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(CloudSpaceErrors.local('云空间未连接，请先刷新'));
    }
    const result: CloudSpaceResult<Blob> =
      await this.request(this.api.deleteSpec(fileId, session.id));
    if (!result.ok) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(
        result.error !== undefined ? result.error : CloudSpaceErrors.parse());
    }
    const remaining: CloudSpaceFile[] = [];
    for (let i = 0; i < this.files.length; i++) {
      if (this.files[i].id !== fileId) {
        remaining.push(this.files[i]);
      }
    }
    this.files = remaining;
    this.expiredIds = this.expiredIds.filter((id: string) => id !== fileId);
    return CloudSpaceResult.success<CloudSpaceSnapshot>(this.snapshot());
  }

  /** 清空云空间：`POST /close` 删除会话与全部文件，随后自动重开一个新空间。 */
  async clearSpace(): Promise<CloudSpaceResult<CloudSpaceSnapshot>> {
    const session: CloudSpaceSession | undefined = this.session;
    if (session === undefined) {
      return await this.ensureSpace();
    }
    const closed: CloudSpaceResult<Blob> =
      await this.request(this.api.closeSpec(session.id));
    if (!closed.ok) {
      return CloudSpaceResult.failure<CloudSpaceSnapshot>(
        closed.error !== undefined ? closed.error : CloudSpaceErrors.parse());
    }
    this.reset();
    return await this.ensureSpace();
  }

  // ---- 下载 / 打开 ---------------------------------------------------------

  /**
   * 下载文件到应用沙箱（`filesDir/cloudspace/<fileId>_<安全名>`），返回沙箱路径。
   * 下载前刷新签名链接；流式落盘（不整文件进内存），回调进度。
   */
  async download(file: CloudSpaceFile,
    onProgress: (received: number, total: number) => void): Promise<CloudSpaceResult<string>> {
    const fresh: CloudSpaceResult<CloudSpaceFile> = await this.findFreshFile(file.id);
    if (!fresh.ok) {
      return CloudSpaceResult.failure<string>(
        fresh.error !== undefined ? fresh.error : CloudSpaceErrors.parse());
    }
    const target: CloudSpaceFile = fresh.value!;
    const dir: string = this.sandboxDir();
    if (dir.length === 0) {
      return CloudSpaceResult.failure<string>(CloudSpaceErrors.local('下载目录不可用'));
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      // 目录已存在时 accessSync 可能抛错，忽略
    }
    const safe: string = CloudSpaceLogic.safeName(target.name);
    const path: string = dir + '/' + CloudSpaceLogic.sandboxFileName(target.id, safe);
    const total: number = target.sizeBytes;
    let received: number = 0;
    let fileFd: fs.File | undefined = undefined;
    try {
      fileFd = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    } catch (e) {
      return CloudSpaceResult.failure<string>(CloudSpaceErrors.local('无法创建下载文件'));
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      request.on('dataReceive', (data: ArrayBuffer) => {
        try {
          fs.writeSync(fileFd!.fd, data);
          received += data.byteLength;
          onProgress(received, total);
        } catch (e) {
          Log.w(TAG, '写入下载文件失败');
        }
      });
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'Accept': '*/*', 'Cache-Control': 'no-store' },
        connectTimeout: 30000,
        readTimeout: 120000,
        usingCache: false
      };
      const status: number = await request.requestInStream(target.downloadUrl, options);
      if (status < 200 || status >= 300) {
        try {
          fs.unlinkSync(path);
        } catch (e) {
          // 忽略
        }
        return CloudSpaceResult.failure<string>(CloudSpaceErrors.http(status));
      }
      onProgress(received, total > 0 ? total : received);
      return CloudSpaceResult.success<string>(path);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.w(TAG, '下载失败 code=' + err.code);
      try {
        fs.unlinkSync(path);
      } catch (ignored) {
        // 忽略
      }
      return CloudSpaceResult.failure<string>(CloudSpaceErrors.network());
    } finally {
      try {
        request.off('dataReceive');
        request.destroy();
      } catch (e) {
        // 忽略
      }
      if (fileFd !== undefined) {
        try {
          fs.closeSync(fileFd);
        } catch (e) {
          // 忽略
        }
      }
    }
  }

  /** 用系统能力打开沙箱文件（文件选择器/文件管理器/系统匹配应用）；返回错误文案（成功为空串）。 */
  async openLocalFile(path: string, mimeType: string): Promise<string> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return '应用上下文缺失，无法打开文件';
    }
    try {
      const uri: string = fileUri.getUriFromPath(path);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: mimeType.length > 0 ? mimeType : 'application/octet-stream',
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      await context.startAbility(want);
      return '';
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.w(TAG, '打开文件失败 code=' + err.code);
      return '没有可打开该文件的应用（已下载到应用沙箱）';
    }
  }

  // ---- 内部实现 -----------------------------------------------------------

  /** 解析本账号会话：`/mine` → 无会话则 `/open`。 */
  private async resolveSession(): Promise<CloudSpaceResult<CloudSpaceSession>> {
    if (this.session !== undefined) {
      return CloudSpaceResult.success<CloudSpaceSession>(this.session);
    }
    const mineResult: CloudSpaceResult<Blob> =
      await this.request(this.api.mineSpec());
    if (!mineResult.ok) {
      return CloudSpaceResult.failure<CloudSpaceSession>(
        mineResult.error !== undefined ? mineResult.error : CloudSpaceErrors.parse());
    }
    const mineBlob = mineResult.value!;
    const existing: CloudSpaceSession | undefined =
      CloudSpaceApi.parseSessionNode(requireBlob(mineBlob, 'session'));
    if (existing !== undefined) {
      return CloudSpaceResult.success<CloudSpaceSession>(existing);
    }
    const openResult: CloudSpaceResult<Blob> =
      await this.request(this.api.openSpec());
    if (!openResult.ok) {
      return CloudSpaceResult.failure<CloudSpaceSession>(
        openResult.error !== undefined ? openResult.error : CloudSpaceErrors.parse());
    }
    const opened: CloudSpaceSession | undefined =
      CloudSpaceApi.parseSessionNode(requireBlob(openResult.value!, 'session'));
    if (opened === undefined) {
      return CloudSpaceResult.failure<CloudSpaceSession>(CloudSpaceErrors.parse());
    }
    return CloudSpaceResult.success<CloudSpaceSession>(opened);
  }

  /** 发起一次请求并解释响应；网络异常统一映射为 NETWORK。 */
  private async request(spec: CloudSpaceRequestSpec, bodyData?: ArrayBuffer):
    Promise<CloudSpaceResult<Blob>> {
    if (this.tokenProvider().trim().length === 0) {
      return CloudSpaceResult.failure<Blob>(CloudSpaceErrors.local('身份缺失，请重新登录后重试'));
    }
    const raw: RawResponse | undefined = await this.execute(spec, bodyData);
    if (raw === undefined) {
      return CloudSpaceResult.failure<Blob>(CloudSpaceErrors.network());
    }
    return CloudSpaceApi.interpret(raw.status, raw.body);
  }

  private async execute(spec: CloudSpaceRequestSpec, bodyData?: ArrayBuffer): Promise<RawResponse | undefined> {
    const token: string = this.tokenProvider();
    if (token.trim().length === 0) {
      return undefined;
    }
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: toMethod(spec.method),
      header: this.api.headers(token, spec.contentType),
      connectTimeout: 30000,
      readTimeout: 60000,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false
    };
    if (bodyData !== undefined) {
      options.extraData = bodyData;
    } else if (spec.bodyText.length > 0) {
      options.extraData = spec.bodyText;
    }
    try {
      const response: http.HttpResponse = await request.request(this.api.url(spec.path), options);
      const raw: RawResponse = new RawResponse();
      raw.status = response.responseCode;
      raw.body = bodyToText(response.result);
      return raw;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.w(TAG, '云空间请求失败 code=' + err.code);
      return undefined;
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // 忽略
      }
    }
  }

  private sandboxDir(): string {
    const context = AppGlobal.context;
    if (context === undefined) {
      return '';
    }
    return context.filesDir + '/cloudspace';
  }

  private static baseName(uri: string): string {
    let text: string = uri;
    const q: number = text.indexOf('?');
    if (q >= 0) {
      text = text.substring(0, q);
    }
    const slash: number = Math.max(text.lastIndexOf('/'), text.lastIndexOf('\\'));
    let name: string = slash >= 0 ? text.substring(slash + 1) : text;
    try {
      name = decodeURIComponent(name);
    } catch (e) {
      // 保持原样
    }
    return name.length > 0 ? name : 'file';
  }
}

/** 取 Blob 中的子对象；不存在返回 undefined（避免 `!` 展开后类型不匹配）。 */
function requireBlob(blob: Blob, key: string): Blob | undefined {
  const value = blob[key];
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as Blob;
}

function toMethod(method: string): http.RequestMethod {
  if (method === 'POST') {
    return http.RequestMethod.POST;
  }
  if (method === 'DELETE') {
    return http.RequestMethod.DELETE;
  }
  if (method === 'PUT') {
    return http.RequestMethod.PUT;
  }
  return http.RequestMethod.GET;
}

function bodyToText(result: string | Object | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  if (result instanceof ArrayBuffer) {
    return '';
  }
  return JSON.stringify(result);
}
