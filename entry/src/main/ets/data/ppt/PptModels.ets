/** PPT 文件条目（manifest.files.compat/pdf/source）。 */
export class PptFileInfo {
  /** 相对文件名（manifest.files.*.s）。 */
  s: string = '';
  /** 绝对地址（旧字段/绝对引用）；为空时用 base + s 解析。 */
  src: string = '';
  size: number = 0;
  ext: string = '';
  name: string = '';
  pages: number = 0;
  sha256: string = '';
}

export class PptFiles {
  compat: PptFileInfo | undefined = undefined;
  pdf: PptFileInfo | undefined = undefined;
  source: PptFileInfo | undefined = undefined;
}

/** 演示列表行（`ppt_decks` 轻字段）。 */
export class PptDeck {
  id: string = '';
  title: string = '';
  ownerName: string = '';
  ownerSid: string = '';
  status: string = 'uploading';
  progress: number = 0;
  error: string = '';
  slideCount: number = 0;
  stepCount: number = 0;
  aspect: string = '';
  coverUrl: string = '';
  sourceName: string = '';
  sourceSize: number = 0;
  createdAt: number = 0;
  convertedAt: number = 0;
  hasCompat: boolean = false;
  hasPdf: boolean = false;
}

/** 下载详情（列表行 + manifest 文件）。 */
/** 分步图的一步（img 为相对 base 的图片名）。 */
export class PptStep {
  img: string = '';
  hasMedia: boolean = false;
}

/** 一页（含多个点击步骤）。 */
export class PptSlide {
  steps: PptStep[] = [];
}

/** 视频章节。 */
export class PptChapter {
  index: number = 0;
  startSec: number = 0;
  title: string = '';
}

/** 原样播放视频信息。 */
export class PptVideoInfo {
  src: string = '';
  chapters: number = 0;
  chapterList: PptChapter[] = [];
  durationSec: number = 0;
  width: number = 0;
  height: number = 0;
}

/** 单独媒体文件（视频/音频）。 */
export class PptMediaFile {
  s: string = '';
  name: string = '';
  size: number = 0;
  kind: string = '';
  slides: number[] = [];
}

export class PptDeckDetail {
  deck: PptDeck = new PptDeck();
  /** manifest.base（OSS 构建目录，结尾通常带 /）。 */
  base: string = '';
  files: PptFiles = new PptFiles();
  warnings: string[] = [];
  slides: PptSlide[] = [];
  video: PptVideoInfo | undefined = undefined;
  mediaFiles: PptMediaFile[] = [];
  mediaCount: number = 0;
}

export class PptListResult {
  ok: boolean = false;
  message: string = '';
  decks: PptDeck[] = [];
  agentOnline: boolean = false;

  constructor(ok: boolean, message: string, decks: PptDeck[], agentOnline: boolean) {
    this.ok = ok;
    this.message = message;
    this.decks = decks;
    this.agentOnline = agentOnline;
  }
}

export class PptDetailResult {
  ok: boolean = false;
  message: string = '';
  detail: PptDeckDetail = new PptDeckDetail();

  constructor(ok: boolean, message: string, detail: PptDeckDetail) {
    this.ok = ok;
    this.message = message;
    this.detail = detail;
  }
}

export function pptStatusLabel(status: string): string {
  if (status === 'ready') {
    return '就绪';
  }
  if (status === 'processing') {
    return '转换中';
  }
  if (status === 'queued') {
    return '排队中';
  }
  if (status === 'failed') {
    return '转换失败';
  }
  return '上传中';
}

export function pptStatusColor(status: string): string {
  if (status === 'ready') {
    return '#4E9082';
  }
  if (status === 'failed') {
    return '#B4543F';
  }
  return '#B98F63';
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '—';
  }
  if (bytes < 1024) {
    return bytes + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
}

/** 解析 manifest 相对引用（契约 §5：绝对地址原样、否则 base + 引用）。 */
export function resolveUrl(base: string, ref: string): string {
  const reference: string = ref.trim();
  if (reference.length === 0) {
    return '';
  }
  const lower: string = reference.toLowerCase();
  if (lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0
    || lower.indexOf('data:') === 0 || lower.indexOf('file:') === 0) {
    return reference;
  }
  const root: string = base.trim();
  if (root.length === 0) {
    return reference;
  }
  const prefix: string = root.endsWith('/') ? root : root + '/';
  return prefix + (reference.indexOf('/') === 0 ? reference.substring(1) : reference);
}

/** 文件下载地址（优先绝对 src，其次 base + s）。 */
export function fileUrl(base: string, file: PptFileInfo): string {
  if (file.src.length > 0) {
    return resolveUrl(base, file.src);
  }
  return resolveUrl(base, file.s);
}

/** 下载文件名（`<标题>_兼容版.pptx` 等，替换非法字符）。 */
export function downloadName(deck: PptDeck, file: PptFileInfo, kind: string): string {
  const title: string = deck.title.trim().length > 0 ? deck.title.trim() : '演示';
  const suffix: string = kind === 'compat' ? '_兼容版' : (kind === 'pdf' ? '_预览' : '_原始文件');
  const ext: string = file.ext.length > 0 ? '.' + file.ext : '';
  const raw: string = title + suffix + ext;
  return raw.replace(new RegExp('[\\\\/:*?"<>|]', 'g'), '_');
}
