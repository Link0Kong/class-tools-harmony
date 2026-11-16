import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import {
  PptDeck,
  PptDeckDetail,
  PptDetailResult,
  PptFileInfo,
  PptListResult,
  PptChapter,
  PptMediaFile,
  PptSlide,
  PptStep,
  PptVideoInfo
} from './PptModels';

const LIST_SELECT: string = 'id,title,owner_name,owner_sid,status,progress,error,slide_count,step_count,aspect,'
  + 'cover_url,source_name,source_size,created_at,converted_at,client,manifest->files';
const DETAIL_SELECT: string = 'id,manifest,title,status,progress,error,owner_name,owner_sid,slide_count,step_count,aspect,'
  + 'cover_url,source_name,source_key,source_size,converted_at';

const LIST_PATH: string = 'ppt_decks?select=' + LIST_SELECT + '&deleted=eq.false&order=created_at.desc&limit=100';
const AGENT_PATH: string = 'site_assets?id=eq.ppt_agent&select=body,updated_at';

/** 转换机心跳超过 180s 视为离线（与网页一致）。 */
const AGENT_STALE_MS: number = 180 * 1000;

/** PPT 演示仓库：列表（轻字段）+ 下载详情（manifest 文件）。 */
export class PptRepository {
  private api: Api;

  constructor(api: Api) {
    this.api = api;
  }

  /** 软删除本人演示（deleted=true；RLS 由服务端校验 owner_sid）。 */
  async softDelete(deckId: string, nowMillis: number): Promise<boolean> {
    const row: Blob = {};
    row['deleted'] = true;
    row['updated_at'] = new Date(nowMillis).toISOString();
    const path: string = 'ppt_decks?id=eq.' + encodeURIComponent(deckId);
    const result: ApiResult = await this.api.patch(path, JSON.stringify(row), 'return=representation', true);
    return result.ok;
  }

  async list(): Promise<PptListResult> {
    const listResult: ApiResult = await this.api.get(LIST_PATH, true);
    if (!listResult.ok) {
      return new PptListResult(false,
        listResult.error !== undefined ? listResult.error.displayMessage() : '演示列表加载失败', [], false);
    }
    const decks: PptDeck[] = PptRepository.parseList(listResult.value);
    const agentResult: ApiResult = await this.api.get(AGENT_PATH, true);
    const agentOnline: boolean = agentResult.ok && PptRepository.agentOnline(agentResult.value);
    return new PptListResult(true, '', decks, agentOnline);
  }

  async detail(deckId: string): Promise<PptDetailResult> {
    const path: string = 'ppt_decks?select=' + DETAIL_SELECT + '&id=eq.' + encodeURIComponent(deckId);
    const result: ApiResult = await this.api.get(path, true);
    if (!result.ok) {
      return new PptDetailResult(false,
        result.error !== undefined ? result.error.displayMessage() : '演示详情加载失败', new PptDeckDetail());
    }
    const detail: PptDeckDetail | undefined = PptRepository.parseDetail(result.value);
    if (detail === undefined) {
      return new PptDetailResult(false, '演示不存在', new PptDeckDetail());
    }
    return new PptDetailResult(true, '', detail);
  }

  /** 列表元信息（`manifest->files` 子查询：只有 compat/pdf 是否存在，用于小标签）。 */
  static parseList(raw: string): PptDeck[] {
    const rows: Blob[] = rowsOf(raw);
    const out: PptDeck[] = [];
    for (let i = 0; i < rows.length; i++) {
      const deck: PptDeck | undefined = parseDeck(rows[i]);
      if (deck !== undefined) {
        const files: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(rows[i], 'files'));
        if (files !== undefined) {
          deck.hasCompat = JsonBlob.asBlob(JsonBlob.get(files, 'compat')) !== undefined;
          deck.hasPdf = JsonBlob.asBlob(JsonBlob.get(files, 'pdf')) !== undefined;
        }
        out.push(deck);
      }
    }
    return out;
  }

  static parseDetail(raw: string): PptDeckDetail | undefined {
    const rows: Blob[] = rowsOf(raw);
    if (rows.length === 0) {
      return undefined;
    }
    const row: Blob = rows[0];
    const deck: PptDeck | undefined = parseDeck(row);
    if (deck === undefined) {
      return undefined;
    }
    const detail: PptDeckDetail = new PptDeckDetail();
    detail.deck = deck;
    const manifest: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(row, 'manifest'));
    if (manifest !== undefined) {
      detail.base = JsonBlob.asString(JsonBlob.get(manifest, 'base'), '');
      const files: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(manifest, 'files'));
      if (files !== undefined) {
        detail.files.compat = parseFile(JsonBlob.asBlob(JsonBlob.get(files, 'compat')));
        detail.files.pdf = parseFile(JsonBlob.asBlob(JsonBlob.get(files, 'pdf')));
        detail.files.source = parseFile(JsonBlob.asBlob(JsonBlob.get(files, 'source')));
      }
      deck.hasCompat = detail.files.compat !== undefined;
      deck.hasPdf = detail.files.pdf !== undefined;
      const compat: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(manifest, 'compat'));
      if (compat !== undefined) {
        const warnings: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(compat, 'warnings'));
        if (warnings !== undefined) {
          for (let i = 0; i < warnings.length; i++) {
            const text: string = JsonBlob.asString(warnings[i], '');
            if (text.length > 0) {
              detail.warnings.push(text);
            }
          }
        }
      }
      const media: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(manifest, 'media_files'));
      detail.mediaCount = media !== undefined ? media.length : 0;
      if (media !== undefined) {
        for (let i = 0; i < media.length; i++) {
          const blob: Blob | undefined = JsonBlob.asBlob(media[i]);
          if (blob === undefined) {
            continue;
          }
          const file: PptMediaFile = new PptMediaFile();
          file.s = JsonBlob.asString(JsonBlob.get(blob, 's'), '');
          file.name = JsonBlob.asString(JsonBlob.get(blob, 'name'), '');
          file.size = JsonBlob.asNumber(JsonBlob.get(blob, 'size'), 0);
          file.kind = JsonBlob.asString(JsonBlob.get(blob, 'kind'), '');
          const slideList: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(blob, 'slides'));
          if (slideList !== undefined) {
            for (let j = 0; j < slideList.length; j++) {
              file.slides.push(Math.round(JsonBlob.asNumber(slideList[j], 0)));
            }
          }
          detail.mediaFiles.push(file);
        }
      }
      const slides: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(manifest, 'slides'));
      if (slides !== undefined) {
        for (let i = 0; i < slides.length; i++) {
          const slideBlob: Blob | undefined = JsonBlob.asBlob(slides[i]);
          if (slideBlob === undefined) {
            continue;
          }
          const slide: PptSlide = new PptSlide();
          const steps: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(slideBlob, 'steps'));
          if (steps !== undefined) {
            for (let j = 0; j < steps.length; j++) {
              const stepBlob: Blob | undefined = JsonBlob.asBlob(steps[j]);
              if (stepBlob === undefined) {
                continue;
              }
              const step: PptStep = new PptStep();
              step.img = JsonBlob.asString(JsonBlob.get(stepBlob, 'img'), '');
              const hotspots: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(stepBlob, 'media'));
              step.hasMedia = hotspots !== undefined && hotspots.length > 0;
              slide.steps.push(step);
            }
          }
          if (slide.steps.length > 0) {
            detail.slides.push(slide);
          }
        }
      }
      const video: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(manifest, 'video'));
      if (video !== undefined) {
        const info: PptVideoInfo = new PptVideoInfo();
        info.src = JsonBlob.asString(JsonBlob.get(video, 'src'), '');
        if (info.src.length === 0) {
          info.src = JsonBlob.asString(JsonBlob.get(video, 's'), '');
        }
        if (info.src.length === 0) {
          info.src = JsonBlob.asString(JsonBlob.get(video, 'path'), '');
        }
        info.width = Math.round(JsonBlob.asNumber(JsonBlob.get(video, 'w'), 0));
        info.height = Math.round(JsonBlob.asNumber(JsonBlob.get(video, 'h'), 0));
        info.durationSec = JsonBlob.asNumber(JsonBlob.get(video, 'dur'), 0);
        const chapters: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(video, 'chapters'));
        info.chapters = chapters !== undefined ? chapters.length : 0;
        if (chapters !== undefined) {
          for (let i = 0; i < chapters.length; i++) {
            const chapterBlob: Blob | undefined = JsonBlob.asBlob(chapters[i]);
            if (chapterBlob === undefined) {
              continue;
            }
            const chapter: PptChapter = new PptChapter();
            let indexValue: number = JsonBlob.asNumber(JsonBlob.get(chapterBlob, 'i'), -1);
            if (indexValue < 0) {
              indexValue = JsonBlob.asNumber(JsonBlob.get(chapterBlob, 'index'), i);
            }
            chapter.index = Math.round(indexValue);
            let start: number = JsonBlob.asNumber(JsonBlob.get(chapterBlob, 't'), -1);
            if (start < 0) {
              start = JsonBlob.asNumber(JsonBlob.get(chapterBlob, 'startSec'), -1);
            }
            if (start < 0) {
              start = JsonBlob.asNumber(JsonBlob.get(chapterBlob, 'start'), 0);
            }
            chapter.startSec = start;
            chapter.title = JsonBlob.asString(JsonBlob.get(chapterBlob, 'title'), '');
            info.chapterList.push(chapter);
          }
        }
        if (info.src.length > 0) {
          detail.video = info;
        }
      }
    }
    return detail;
  }

  /** 转换机心跳（`site_assets id=ppt_agent` 的 body.fetchedAt/updated_at）。 */
  static agentOnline(raw: string): boolean {
    const rows: Blob[] = rowsOf(raw);
    if (rows.length === 0) {
      return false;
    }
    const body: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(rows[0], 'body'));
    let stamp: number = JsonBlob.asNumber(JsonBlob.get(rows[0], 'updated_at'), 0);
    const text: string = JsonBlob.asString(JsonBlob.get(rows[0], 'updated_at'), '');
    let onlineFlag: boolean = true;
    if (body !== undefined) {
      const seen: number = JsonBlob.asNumber(JsonBlob.get(body, 'seen_at'), 0);
      const beat: number = JsonBlob.asNumber(JsonBlob.get(body, 'at'), 0);
      if (seen > 0) {
        stamp = seen;
      } else if (beat > 0) {
        stamp = beat;
      }
      onlineFlag = JsonBlob.asBoolean(JsonBlob.get(body, 'online'), true);
    }
    if (!onlineFlag) {
      return false;
    }
    if (stamp <= 0 && text.length > 0) {
      stamp = Date.parse(text);
    }
    if (stamp <= 0) {
      return false;
    }
    return Date.now() - stamp < AGENT_STALE_MS;
  }
}

function parseDeck(row: Blob): PptDeck | undefined {
  const id: string = JsonBlob.asString(JsonBlob.get(row, 'id'), '').trim();
  if (id.length === 0) {
    return undefined;
  }
  const deck: PptDeck = new PptDeck();
  deck.id = id;
  deck.title = JsonBlob.asString(JsonBlob.get(row, 'title'), '');
  deck.ownerName = JsonBlob.asString(JsonBlob.get(row, 'owner_name'), '');
  deck.ownerSid = JsonBlob.asString(JsonBlob.get(row, 'owner_sid'), '');
  deck.status = JsonBlob.asString(JsonBlob.get(row, 'status'), 'uploading');
  deck.progress = Math.round(JsonBlob.asNumber(JsonBlob.get(row, 'progress'), 0));
  deck.error = JsonBlob.asString(JsonBlob.get(row, 'error'), '');
  deck.slideCount = Math.round(JsonBlob.asNumber(JsonBlob.get(row, 'slide_count'), 0));
  deck.stepCount = Math.round(JsonBlob.asNumber(JsonBlob.get(row, 'step_count'), 0));
  deck.aspect = JsonBlob.asString(JsonBlob.get(row, 'aspect'), '');
  deck.coverUrl = JsonBlob.asString(JsonBlob.get(row, 'cover_url'), '');
  deck.sourceName = JsonBlob.asString(JsonBlob.get(row, 'source_name'), '');
  deck.sourceSize = JsonBlob.asNumber(JsonBlob.get(row, 'source_size'), 0);
  deck.createdAt = timeOf(JsonBlob.get(row, 'created_at'));
  deck.convertedAt = timeOf(JsonBlob.get(row, 'converted_at'));
  return deck;
}

function parseFile(obj: Blob | undefined): PptFileInfo | undefined {
  if (obj === undefined) {
    return undefined;
  }
  const file: PptFileInfo = new PptFileInfo();
  file.s = JsonBlob.asString(JsonBlob.get(obj, 's'), '');
  file.src = JsonBlob.asString(JsonBlob.get(obj, 'src'), '');
  file.size = JsonBlob.asNumber(JsonBlob.get(obj, 'size'), 0);
  file.ext = JsonBlob.asString(JsonBlob.get(obj, 'ext'), '');
  file.name = JsonBlob.asString(JsonBlob.get(obj, 'name'), '');
  file.pages = Math.round(JsonBlob.asNumber(JsonBlob.get(obj, 'pages'), 0));
  file.sha256 = JsonBlob.asString(JsonBlob.get(obj, 'sha256'), '');
  return file.src.length > 0 || file.s.length > 0 || file.size > 0 ? file : undefined;
}

function timeOf(value: Object | null | undefined): number {
  if (typeof value === 'number') {
    return value as number;
  }
  if (typeof value === 'string') {
    const parsed: number = Date.parse(value as string);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function rowsOf(raw: string): Blob[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  const array: Object[] | undefined = JsonBlob.asArray(parsed);
  if (array === undefined) {
    return [];
  }
  const out: Blob[] = [];
  for (let i = 0; i < array.length; i++) {
    const obj: Blob | undefined = JsonBlob.asBlob(array[i]);
    if (obj !== undefined) {
      out.push(obj);
    }
  }
  return out;
}
