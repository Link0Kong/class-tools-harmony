/**
 * 临时云空间（与网页/小程序/安卓同一 ECS drop 服务，契约 `web/drop/CONTRACT.md` v2.2）的数据模型。
 *
 * 语义（三端一致）：
 * - 同账号（同班级 token）自动共享同一云空间，不需要房间码/链接/配对；
 * - 每个文件自「上传完成」起保留 72 小时（3 天），逐文件过期；会话空闲 72h 且无未过期文件时回收；
 * - 上传任意大小：8MiB 原始字节分片（init → chunk × N → finish）。
 *
 * 红线：班级 token 只在请求头 `X-Device-Id` 中出现，**不落盘、不打日志、不进错误文案**。
 */
export class CloudSpaceDefaults {
  /**
   * 开发/调试基址：HTTPS 域名（tool.furina.fun）备案前直连 ECS IP
   * （`network_config.json` 已对该 IP 放行明文 HTTP）。
   */
  static readonly BASE_URL: string = 'http://121.196.47.2/drop';

  /** 与服务端/网页/小程序/安卓一致的固定分片：8 MiB。 */
  static readonly CHUNK_SIZE: number = 8 * 1024 * 1024;

  /** 文件 TTL：自上传完成起 72 小时。 */
  static readonly FILE_TTL_MS: number = 72 * 60 * 60 * 1000;

  /** 服务端单文件分片数上限（仅用于本地超限提示）。 */
  static readonly MAX_UPLOAD_CHUNKS: number = 65536;

  /** 服务端单会话文件数上限（仅计未过期文件）。 */
  static readonly MAX_FILES: number = 300;

  /** 列表静默轮询间隔（与网页/小程序一致：5s）。 */
  static readonly POLL_INTERVAL_MS: number = 5000;

  /** 下载签名 URL 有效期（服务端 30 分钟；仅文案提示，不参与校验）。 */
  static readonly DOWNLOAD_URL_TTL_MINUTES: number = 30;
}

/** 云空间会话（`/mine`、`/open`、`/state` 的 session 节点；`code` 为历史兼容字段，UI 不展示）。 */
export class CloudSpaceSession {
  id: string = '';
  code: string = '';
  createdAt: number = 0;
  expiresAt: number = 0;

  constructor(id: string = '', code: string = '', createdAt: number = 0, expiresAt: number = 0) {
    this.id = id;
    this.code = code;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
  }
}

/**
 * 一个云空间文件（来自 `/state` 的 `file` 事件）。
 *
 * `downloadUrl` 由服务端**每次读取重新签发**（30 分钟有效），不要长期缓存：
 * 下载前先刷新一次列表，遇到 403「下载链接已过期」再刷新重试。
 */
export class CloudSpaceFile {
  id: string = '';
  name: string = '';
  sizeBytes: number = 0;
  mimeType: string = '';
  downloadUrl: string = '';
  expired: boolean = false;
  /** 上传完成时刻（文件 TTL 起算点；毫秒）。 */
  uploadedAt: number = 0;

  constructor(id: string = '', name: string = '', sizeBytes: number = 0, mimeType: string = '',
    downloadUrl: string = '', expired: boolean = false, uploadedAt: number = 0) {
    this.id = id;
    this.name = name;
    this.sizeBytes = sizeBytes;
    this.mimeType = mimeType;
    this.downloadUrl = downloadUrl;
    this.expired = expired;
    this.uploadedAt = uploadedAt;
  }
}

/** 列表页渲染用的只读快照（同一时刻的文件集合 + 统计）。 */
export class CloudSpaceSnapshot {
  session: CloudSpaceSession | undefined = undefined;
  files: CloudSpaceFile[] = [];
  /** 已过期（上传超过 72h，服务端已删）的文件事件数；只用于提示。 */
  expiredCount: number = 0;
  /** 已合并的最大事件 seq（增量轮询用）。 */
  cursor: number = 0;

  connected(): boolean {
    return this.session !== undefined;
  }

  count(): number {
    return this.files.length;
  }

  totalBytes(): number {
    let total: number = 0;
    for (let i = 0; i < this.files.length; i++) {
      total += this.files[i].sizeBytes;
    }
    return total;
  }
}

/** `/state` 解析后的事件（本页只关心 file / filedel；text / cmd 直接忽略）。 */
export class CloudSpaceEvent {
  /** `file` / `filedel`。 */
  kind: string = '';
  seq: number = 0;
  file: CloudSpaceFile | undefined = undefined;
  fileId: string = '';
}

/** `/state` 一次响应（events 尚未合并进列表）。 */
export class CloudSpaceState {
  session: CloudSpaceSession | undefined = undefined;
  events: CloudSpaceEvent[] = [];
  cursor: number = 0;
}

/** `/upload/init` 响应。 */
export class CloudSpaceUploadInit {
  uploadId: string = '';
  chunkSize: number = CloudSpaceDefaults.CHUNK_SIZE;
}

/** 上传状态。 */
export enum CloudSpaceUploadState {
  WAITING = 'waiting',
  UPLOADING = 'uploading',
  DONE = 'done',
  FAILED = 'failed',
  CANCELED = 'canceled'
}

/** 上传进度回调（只在内存中传递，不落盘）。 */
export class CloudSpaceUploadProgress {
  state: CloudSpaceUploadState = CloudSpaceUploadState.WAITING;
  sentBytes: number = 0;
  totalBytes: number = 0;
  message: string = '';

  constructor(state: CloudSpaceUploadState, sentBytes: number, totalBytes: number, message: string = '') {
    this.state = state;
    this.sentBytes = sentBytes;
    this.totalBytes = totalBytes;
    this.message = message;
  }
}

/** 页面「上传进度」卡的一行（本机内存状态，不进云端同步）。 */
export class CloudSpaceUploadTask {
  id: string = '';
  name: string = '';
  sizeBytes: number = 0;
  sentBytes: number = 0;
  state: CloudSpaceUploadState = CloudSpaceUploadState.WAITING;
  message: string = '';

  percent(): number {
    if (this.state === CloudSpaceUploadState.DONE) {
      return 100;
    }
    return Math.min(99, Math.floor((this.sentBytes * 100) / Math.max(1, this.sizeBytes)));
  }
}

/** 下载进度回调。 */
export class CloudSpaceDownloadProgress {
  receivedBytes: number = 0;
  totalBytes: number = 0;
}

/** 错误类别（中文文案可直接展示给用户）。 */
export enum CloudSpaceErrorKind {
  NETWORK = 'network',
  TOKEN_INVALID = 'token_invalid',
  HTTP = 'http',
  PARSE = 'parse',
  LOCAL = 'local'
}

/**
 * 云空间错误（任何错误文案都不包含班级 token / 学号；服务端 reason 本身也不含）。
 *
 * 映射口径（drop 服务契约 §1.3）：
 * - 网络不可用 → NETWORK（不重试写请求，页面提示重试）；
 * - 401 → TOKEN_INVALID（身份失效，建议回身份页重新验证）；
 * - 4xx/5xx → HTTP：优先用服务端 `{ok:false,reason:"中文"}` 的 reason，缺失时按状态码给默认中文；
 * - 2xx 但响应不是合法 JSON / 不符合契约 → PARSE；
 * - 本地前置条件（空文件、未连接等）→ LOCAL。
 */
export class CloudSpaceError {
  kind: CloudSpaceErrorKind = CloudSpaceErrorKind.LOCAL;
  status: number = 0;
  reason: string = '';

  constructor(kind: CloudSpaceErrorKind, status: number = 0, reason: string = '') {
    this.kind = kind;
    this.status = status;
    this.reason = reason;
  }

  displayMessage(): string {
    if (this.kind === CloudSpaceErrorKind.NETWORK) {
      return '云空间服务不可达，请检查网络后重试';
    }
    if (this.kind === CloudSpaceErrorKind.PARSE) {
      return '云空间服务响应异常，请稍后重试';
    }
    if (this.reason.length > 0) {
      return this.reason;
    }
    return CloudSpaceErrors.defaultReason(this.status);
  }
}

/** HTTP 状态码 / 服务端 reason → 中文错误的唯一映射入口（纯函数，可单测）。 */
export class CloudSpaceErrors {
  static network(): CloudSpaceError {
    return new CloudSpaceError(CloudSpaceErrorKind.NETWORK);
  }

  static http(status: number, serverReason: string = ''): CloudSpaceError {
    const reason: string = CloudSpaceErrors.sanitize(serverReason);
    if (status === 401) {
      return new CloudSpaceError(CloudSpaceErrorKind.TOKEN_INVALID, status, reason);
    }
    return new CloudSpaceError(CloudSpaceErrorKind.HTTP, status, reason);
  }

  /** HTTP 200 但业务返回 `ok:false`（服务端拒绝；reason 优先）。 */
  static rejected(serverReason: string = ''): CloudSpaceError {
    const reason: string = CloudSpaceErrors.sanitize(serverReason);
    return new CloudSpaceError(CloudSpaceErrorKind.HTTP, 200,
      reason.length > 0 ? reason : '云空间操作失败，请稍后重试');
  }

  static parse(): CloudSpaceError {
    return new CloudSpaceError(CloudSpaceErrorKind.PARSE);
  }

  static local(message: string): CloudSpaceError {
    return new CloudSpaceError(CloudSpaceErrorKind.LOCAL, 0, message);
  }

  static defaultReason(status: number): string {
    if (status === 400) {
      return '请求参数有误，请稍后重试';
    }
    if (status === 401) {
      return '身份已失效，请重新验证';
    }
    if (status === 403) {
      return '没有操作权限，或文件已过期';
    }
    if (status === 404) {
      return '云空间会话或文件不存在（可能已清空或过期）';
    }
    if (status === 405) {
      return '云空间服务暂不支持该操作';
    }
    if (status === 411) {
      return '上传数据不完整，请重试';
    }
    if (status === 413) {
      return '文件数量或大小超出服务限制';
    }
    if (status === 500) {
      return '云空间服务内部错误，请稍后重试';
    }
    if (status === 503) {
      return '身份服务暂不可用，请稍后重试';
    }
    if (status === 507) {
      return '服务器空间不足，请稍后再试';
    }
    return '服务错误（HTTP ' + status + '）';
  }

  /** 服务端 reason 一律是短中文句；防御性截断，避免异常文本撑破 UI。 */
  private static sanitize(reason: string): string {
    const text: string = reason.trim();
    if (text.length <= 120) {
      return text;
    }
    return text.substring(0, 119) + '…';
  }
}

/** 数据层统一返回：成功 / 失败；仓库公开方法不抛异常（取消除外）。 */
export class CloudSpaceResult<T> {
  ok: boolean = false;
  value: T | undefined = undefined;
  error: CloudSpaceError | undefined = undefined;

  static success<T>(value: T): CloudSpaceResult<T> {
    const result: CloudSpaceResult<T> = new CloudSpaceResult<T>();
    result.ok = true;
    result.value = value;
    return result;
  }

  static failure<T>(error: CloudSpaceError): CloudSpaceResult<T> {
    const result: CloudSpaceResult<T> = new CloudSpaceResult<T>();
    result.ok = false;
    result.error = error;
    return result;
  }
}
