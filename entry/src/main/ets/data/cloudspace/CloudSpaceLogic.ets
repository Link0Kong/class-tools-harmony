import { CloudSpaceDefaults, CloudSpaceEvent, CloudSpaceFile } from './CloudSpaceModels';

/**
 * 临时云空间的纯逻辑（无网络 / 无 ArkUI 依赖，hypium 直接覆盖）：
 * 分片规划、大小/时间/剩余 TTL 文案、上传百分比、文件名清洗与去重、文件类型、事件合并。
 *
 * 与安卓 `CloudSpaceLogic.kt`、小程序 `utils/cloudspace.js` 保持同一口径（可读性优先，不追求逐字节一致）。
 */
export class CloudSpaceChunk {
  index: number = 0;
  start: number = 0;
  endExclusive: number = 0;

  constructor(index: number, start: number, endExclusive: number) {
    this.index = index;
    this.start = start;
    this.endExclusive = endExclusive;
  }

  size(): number {
    return Math.max(0, this.endExclusive - this.start);
  }
}

export class CloudSpaceChunkPlan {
  totalChunks: number = 0;
  chunkSize: number = CloudSpaceDefaults.CHUNK_SIZE;
  chunks: CloudSpaceChunk[] = [];
}

export class CloudSpaceMergedFiles {
  files: CloudSpaceFile[] = [];
  expiredIds: string[] = [];

  expiredCount(): number {
    return this.expiredIds.length;
  }
}

/** 文件类型（只用于列表图标）。 */
export enum CloudSpaceFileKind {
  IMAGE = 'image',
  VIDEO = 'video',
  AUDIO = 'audio',
  ARCHIVE = 'archive',
  PDF = 'pdf',
  DOCUMENT = 'document',
  OTHER = 'other'
}

export class CloudSpaceLogic {
  /** 分片规划：最后一片可小于 chunkSize；空文件按 1 个 0 字节分片（纯函数语义完整，业务层拒绝空文件）。 */
  static chunkPlan(sizeBytes: number, chunkSize: number = CloudSpaceDefaults.CHUNK_SIZE): CloudSpaceChunkPlan {
    const size: number = Math.max(0, Math.floor(sizeBytes));
    const cs: number = chunkSize > 0 ? Math.floor(chunkSize) : CloudSpaceDefaults.CHUNK_SIZE;
    const total: number = size === 0 ? 1 : Math.ceil(size / cs);
    const plan: CloudSpaceChunkPlan = new CloudSpaceChunkPlan();
    plan.totalChunks = total;
    plan.chunkSize = cs;
    for (let index = 0; index < total; index++) {
      const start: number = index * cs;
      const end: number = Math.min(start + cs, size);
      plan.chunks.push(new CloudSpaceChunk(index, start, end));
    }
    return plan;
  }

  // ---- 文案格式 -----------------------------------------------------------

  /** 文件大小：B / KB / MB（≥10MB 不带小数，其余 1 位小数）。 */
  static fmtSize(bytes: number): string {
    const n: number = Math.max(0, Math.floor(bytes));
    if (n === 0) {
      return '0 B';
    }
    if (n >= 1024 * 1024) {
      const mb: number = n / (1024 * 1024);
      return (n >= 10 * 1024 * 1024 ? mb.toFixed(0) : mb.toFixed(1)) + ' MB';
    }
    if (n >= 1024) {
      return (n / 1024).toFixed(1) + ' KB';
    }
    return n + ' B';
  }

  /** 本地时间 `MM-dd HH:mm`；非法时间返回空串。 */
  static fmtTime(epochMs: number): string {
    if (epochMs <= 0) {
      return '';
    }
    const d: Date = new Date(epochMs);
    const month: string = d.getMonth() + 1 < 10 ? '0' + (d.getMonth() + 1) : '' + (d.getMonth() + 1);
    const day: string = d.getDate() < 10 ? '0' + d.getDate() : '' + d.getDate();
    const hh: string = d.getHours() < 10 ? '0' + d.getHours() : '' + d.getHours();
    const mm: string = d.getMinutes() < 10 ? '0' + d.getMinutes() : '' + d.getMinutes();
    return month + '-' + day + ' ' + hh + ':' + mm;
  }

  /** 剩余保留时间（自上传完成起 72h）：`剩 N 天 M 小时` / `剩 N 小时` / `已过期`。 */
  static ttlText(uploadedAt: number, now: number): string {
    if (uploadedAt <= 0) {
      return '已过期';
    }
    const left: number = uploadedAt + CloudSpaceDefaults.FILE_TTL_MS - now;
    if (left <= 0) {
      return '已过期';
    }
    const hours: number = Math.ceil(left / 3600000);
    if (hours >= 24) {
      const days: number = Math.floor(hours / 24);
      const rest: number = hours % 24;
      return rest > 0 ? '剩 ' + days + ' 天 ' + rest + ' 小时' : '剩 ' + days + ' 天';
    }
    return '剩 ' + hours + ' 小时';
  }

  /** 上传中百分比：0..99（100 由「完成」状态给出，避免提前显示 100%）。 */
  static uploadPercent(sentBytes: number, totalBytes: number): number {
    if (totalBytes <= 0) {
      return 0;
    }
    const sent: number = Math.min(Math.max(0, sentBytes), totalBytes);
    return Math.min(99, Math.floor((sent * 100) / totalBytes));
  }

  /** 已过期文件提示。 */
  static expiredHint(count: number): string {
    return count + ' 个文件已过期（上传超过 72 小时，已自动删除）';
  }

  /** 上传任务状态文案（无自定义 message 时的默认文案）。 */
  static uploadStateText(state: string, message: string): string {
    if (message.length > 0) {
      return message;
    }
    if (state === 'waiting') {
      return '准备上传…';
    }
    if (state === 'uploading') {
      return '上传中…';
    }
    if (state === 'done') {
      return '已上传';
    }
    if (state === 'failed') {
      return '上传失败';
    }
    return '已取消';
  }

  // ---- 文件名 -------------------------------------------------------------

  /** 文件名清洗：去路径分隔符/控制字符、限长（保留扩展名）；空名回退 `file`。 */
  static safeName(rawName: string): string {
    const raw: string = rawName === undefined ? '' : rawName;
    let cleaned: string = '';
    const illegal: string = '\\/:*?"<>|';
    for (let i = 0; i < raw.length; i++) {
      const ch: string = raw.charAt(i);
      const code: number = raw.charCodeAt(i);
      if (illegal.indexOf(ch) >= 0 || code < 0x20) {
        cleaned += '_';
      } else {
        cleaned += ch;
      }
    }
    cleaned = cleaned.trim();
    // 去首尾 `.`（避免 `..`/隐藏文件）
    while (cleaned.startsWith('.')) {
      cleaned = cleaned.substring(1);
    }
    while (cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.length === 0) {
      cleaned = 'file';
    }
    if (cleaned.length <= 120) {
      return cleaned;
    }
    const dot: number = cleaned.lastIndexOf('.');
    if (dot > 0 && cleaned.length - dot <= 12) {
      const ext: string = cleaned.substring(dot);
      return cleaned.substring(0, 120 - ext.length) + ext;
    }
    return cleaned.substring(0, 120);
  }

  /** 同名文件去重：`名称 (1).ext`、`名称 (2).ext`…（目录内已存在时递增）。 */
  static uniqueName(existingNames: string[], desiredName: string): string {
    if (existingNames.indexOf(desiredName) < 0) {
      return desiredName;
    }
    const dot: number = desiredName.lastIndexOf('.');
    const base: string = dot > 0 ? desiredName.substring(0, dot) : desiredName;
    const ext: string = dot > 0 ? desiredName.substring(dot) : '';
    for (let index = 1; index <= 9999; index++) {
      const candidate: string = base + ' (' + index + ')' + ext;
      if (existingNames.indexOf(candidate) < 0) {
        return candidate;
      }
    }
    return desiredName;
  }

  /** 下载落盘名：`<fileId>_<安全名>`（fileId 保证同会话不重名；展示仍用原名）。 */
  static sandboxFileName(fileId: string, safeName: string): string {
    return fileId + '_' + safeName;
  }

  // ---- 文件类型 -----------------------------------------------------------

  /** 按 MIME 优先、扩展名兜底判断文件类型。 */
  static fileKind(mimeType: string, name: string): CloudSpaceFileKind {
    const mime: string = mimeType.trim().toLowerCase();
    const dot: number = name.lastIndexOf('.');
    const ext: string = dot >= 0 ? name.substring(dot + 1).toLowerCase().trim() : '';
    if (mime.startsWith('image/') || CloudSpaceLogic.inList(ext,
      ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'])) {
      return CloudSpaceFileKind.IMAGE;
    }
    if (mime.startsWith('video/') || CloudSpaceLogic.inList(ext,
      ['mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp', 'ts'])) {
      return CloudSpaceFileKind.VIDEO;
    }
    if (mime.startsWith('audio/') || CloudSpaceLogic.inList(ext, ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'])) {
      return CloudSpaceFileKind.AUDIO;
    }
    if (CloudSpaceLogic.inList(ext, ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'])) {
      return CloudSpaceFileKind.ARCHIVE;
    }
    if (mime === 'application/pdf' || ext === 'pdf') {
      return CloudSpaceFileKind.PDF;
    }
    if (CloudSpaceLogic.inList(ext, ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv'])) {
      return CloudSpaceFileKind.DOCUMENT;
    }
    return CloudSpaceFileKind.OTHER;
  }

  /** 文件类型单字字形（列表图标，避免依赖图标字体）。 */
  static fileKindGlyph(kind: CloudSpaceFileKind): string {    if (kind === CloudSpaceFileKind.IMAGE) {
      return '图';
    }
    if (kind === CloudSpaceFileKind.VIDEO) {
      return '视';
    }
    if (kind === CloudSpaceFileKind.AUDIO) {
      return '音';
    }
    if (kind === CloudSpaceFileKind.ARCHIVE) {
      return '档';
    }
    if (kind === CloudSpaceFileKind.PDF) {
      return 'PDF';
    }
    if (kind === CloudSpaceFileKind.DOCUMENT) {
      return '文';
    }
    return '件';
  }

  // ---- 事件合并 -----------------------------------------------------------

  /**
   * 合并 `/state` 事件到当前列表（`since > 0` 的增量合并；`since = 0` 时调用方传空列表重建）。
   *
   * - `file` 事件：未过期 → 覆盖/加入列表（同 id 去重，刷新 downloadUrl）；已过期 → 从列表移除并计入过期数；
   * - `filedel` 事件：从列表移除，同时从过期集合移除（已手动删除的文件不算「已过期」）；
   * - 输出按上传时间倒序（新文件在前），同时间按 id 稳定排序。
   */
  static applyEvents(currentFiles: CloudSpaceFile[], currentExpiredIds: string[],
    events: CloudSpaceEvent[]): CloudSpaceMergedFiles {
    const byId: Map<string, CloudSpaceFile> = new Map<string, CloudSpaceFile>();
    for (let i = 0; i < currentFiles.length; i++) {
      byId.set(currentFiles[i].id, currentFiles[i]);
    }
    const expired: string[] = currentExpiredIds.slice(0);
    const sorted: CloudSpaceEvent[] = events.slice(0);
    sorted.sort((a: CloudSpaceEvent, b: CloudSpaceEvent) => a.seq - b.seq);
    for (let i = 0; i < sorted.length; i++) {
      const event: CloudSpaceEvent = sorted[i];
      if (event.kind === 'file' && event.file !== undefined) {
        const file: CloudSpaceFile = event.file;
        if (file.expired) {
          byId.delete(file.id);
          if (expired.indexOf(file.id) < 0) {
            expired.push(file.id);
          }
        } else {
          byId.set(file.id, file);
          const index: number = expired.indexOf(file.id);
          if (index >= 0) {
            expired.splice(index, 1);
          }
        }
      } else if (event.kind === 'filedel') {
        byId.delete(event.fileId);
        const index: number = expired.indexOf(event.fileId);
        if (index >= 0) {
          expired.splice(index, 1);
        }
      }
    }
    const files: CloudSpaceFile[] = [];
    byId.forEach((file: CloudSpaceFile) => {
      files.push(file);
    });
    files.sort((a: CloudSpaceFile, b: CloudSpaceFile) => {
      if (a.uploadedAt !== b.uploadedAt) {
        return b.uploadedAt - a.uploadedAt;
      }
      return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
    });
    const merged: CloudSpaceMergedFiles = new CloudSpaceMergedFiles();
    merged.files = files;
    merged.expiredIds = expired;
    return merged;
  }

  /** 按扩展名猜 MIME（filePicker 只给 URI/文件名，上传时兜底用）。 */
  static mimeOf(name: string): string {
    const dot: number = name.lastIndexOf('.');
    const ext: string = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    if (ext === 'pdf') {
      return 'application/pdf';
    }
    if (ext === 'png') {
      return 'image/png';
    }
    if (ext === 'jpg' || ext === 'jpeg') {
      return 'image/jpeg';
    }
    if (ext === 'gif') {
      return 'image/gif';
    }
    if (ext === 'webp') {
      return 'image/webp';
    }
    if (ext === 'mp4') {
      return 'video/mp4';
    }
    if (ext === 'mov') {
      return 'video/quicktime';
    }
    if (ext === 'mp3') {
      return 'audio/mpeg';
    }
    if (ext === 'm4a') {
      return 'audio/mp4';
    }
    if (ext === 'wav') {
      return 'audio/wav';
    }
    if (ext === 'zip') {
      return 'application/zip';
    }
    if (ext === 'rar') {
      return 'application/vnd.rar';
    }
    if (ext === '7z') {
      return 'application/x-7z-compressed';
    }
    if (ext === 'doc') {
      return 'application/msword';
    }
    if (ext === 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext === 'xls') {
      return 'application/vnd.ms-excel';
    }
    if (ext === 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (ext === 'ppt') {
      return 'application/vnd.ms-powerpoint';
    }
    if (ext === 'pptx') {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (ext === 'txt' || ext === 'md' || ext === 'csv') {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }

  private static inList(value: string, list: string[]): boolean {
    return list.indexOf(value) >= 0;
  }
}
