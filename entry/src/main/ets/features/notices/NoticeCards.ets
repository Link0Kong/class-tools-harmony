import { NoticeEntry } from '../../data/notices/NoticesRepository';
import { NoticeGroup, NoticeItemMeta, NoticeOccurrence, NoticeRecurrence, NoticeSegment } from '../../data/notices/NoticeModels';
import { NoticeRecurrenceLogic, NoticeSection } from './NoticeRecurrence';
import { NoticeStatus, NoticeStatusInfo } from './NoticeStatus';

/** 卡片里的「组成」小标签（图片 3 / 附件 1 …）。 */
export class NoticeComposeChip {
  n: number = 0;
  label: string = '';
}

/** 列表卡片（普通通知 / 长期期次 / 长期定义）。 */
export class NoticeCard {
  key: string = '';
  title: string = '';
  summary: string = '';
  label: string = '';
  timeText: string = '';
  dueText: string = '';
  occurrence: boolean = false;
  definition: boolean = false;
  section: string = NoticeSection.PRIMARY;
  sortAt: number = 0;
  entry: NoticeEntry | undefined = undefined;

  // ---- 展示层（与小程序 notice-card 对齐） ----
  cat: string = '通知';
  catCls: string = 'qt';
  statusLabel: string = '';
  statusCls: string = 'none';
  expired: boolean = false;
  source: string = '';
  sourceKind: string = 'doc';
  senderName: string = '';
  senderBadge: string = '';
  ocr: boolean = false;
  updated: boolean = false;
  hiddenLocal: boolean = false;
  recurring: boolean = false;
  recurLabel: string = '';
  nextText: string = '';
  nextCnText: string = '';
  pubTs: number = 0;
  whenAt: number = 0;
  canDone: boolean = true;
  canRemind: boolean = true;
  aiSummary: string = '';
  points: string[] = [];
  segments: NoticeSegment[] = [];
  items: NoticeItemMeta[] = [];
  quotes: NoticeItemMeta[] = [];
  compose: NoticeComposeChip[] = [];
  hasDetail: boolean = false;
  hasRaw: boolean = false;
  moreText: string = '';
  rawTitle: string = '';
  definitionGroup: NoticeGroup | undefined = undefined;
}

/** 顶部简报统计。 */
export class NoticeStats {
  pending: number = 0;
  urgent: number = 0;
  week: number = 0;
  longterm: number = 0;
  latestText: string = '—';
  expired: number = 0;
}

/** 卡片构建 + 分区（纯函数，可单测）。 */
export class NoticeCards {
  private static readonly CAT_PALETTE: string[] = ['jw', 'tw', 'ks', 'jf', 'hd', 'qt'];
  private static readonly COMPOSE_DEFS: string[] = ['text', 'img', 'file', 'form', 'link', 'mini', 'article', 'merged'];
  private static readonly COMPOSE_LABELS: string[] = ['原文', '图片', '附件', '收集表', '链接', '小程序', '公众号', '聊天记录'];
  private static readonly SEG_ORDER: string[] = ['时间', '地点', '对象', '内容', '报名', '截止', '要求', '联系方式', '补充'];

  static build(entries: NoticeEntry[], nowMillis: number): NoticeCard[] {
    const primary: NoticeCard[] = [];
    const material: NoticeCard[] = [];
    const expired: NoticeCard[] = [];
    for (let i = 0; i < entries.length; i++) {
      const entry: NoticeEntry = entries[i];
      const group: NoticeGroup | undefined = entry.group;
      if (group !== undefined && NoticeRecurrenceLogic.isLongterm(group)) {
        const until: number = NoticeRecurrenceLogic.recurUntil(group);
        const ended: boolean = until > 0 && nowMillis > until;
        const occurrence: NoticeOccurrence | undefined = ended ? undefined
          : NoticeRecurrenceLogic.occurrenceOf(entry, nowMillis);
        if (occurrence !== undefined) {
          const card: NoticeCard = new NoticeCard();
          NoticeCards.fill(card, entry, nowMillis);
          card.key = occurrence.key;
          card.title = NoticeStatus.fmtDatesCn(occurrence.title, nowMillis);
          card.label = occurrence.label;
          card.occurrence = true;
          card.section = NoticeSection.PRIMARY;
          card.sortAt = occurrence.nextMillis;
          card.whenAt = occurrence.nextMillis;
          card.statusLabel = NoticeStatus.occurrenceLabel(occurrence.nextMillis, nowMillis);
          card.statusCls = 'recurring';
          card.expired = false;
          card.canDone = true;
          card.canRemind = false;
          card.recurring = false;
          card.nextText = '';
          primary.push(card);
          continue;
        }
        const card: NoticeCard = new NoticeCard();
        NoticeCards.fill(card, entry, nowMillis);
        card.key = entry.id();
        card.title = NoticeStatus.fmtDatesCn(entry.title(), nowMillis);
        card.definition = true;
        card.definitionGroup = group;
        card.section = ended ? NoticeSection.EXPIRED : NoticeSection.PRIMARY;
        card.sortAt = entry.row.ts;
        card.expired = ended;
        card.canDone = false;
        card.canRemind = false;
        card.recurring = !ended;
        card.recurLabel = NoticeCards.recurLabelOf(group);
        card.nextText = ended ? '' : NoticeStatus.dateTimeCnOf(card.whenAt, nowMillis);
        card.nextCnText = card.nextText.length > 0 ? '下次 ' + card.nextText : '';
        card.statusLabel = ended ? '长期安排已结束'
          : ('长期安排 · ' + NoticeCards.recurLabelOf(group));
        card.statusCls = ended ? 'expired' : 'recurring';
        card.label = card.statusLabel;
        if (ended) {
          expired.push(card);
        } else {
          primary.push(card);
        }
        continue;
      }
      const card: NoticeCard = new NoticeCard();
      NoticeCards.fill(card, entry, nowMillis);
      card.key = entry.id();
      card.title = NoticeStatus.fmtDatesCn(entry.title(), nowMillis);
      card.timeText = entry.timeLabel();
      card.dueText = group !== undefined ? NoticeRecurrenceLogic.deadlineText(group) : '';
      card.section = NoticeRecurrenceLogic.sectionOf(entry, nowMillis);
      card.sortAt = entry.row.ts;
      if (card.section === NoticeSection.EXPIRED) {
        expired.push(card);
      } else if (card.section === NoticeSection.MATERIAL) {
        material.push(card);
      } else {
        primary.push(card);
      }
    }
    primary.sort((a: NoticeCard, b: NoticeCard) => {
      if (a.occurrence !== b.occurrence) {
        return a.occurrence ? -1 : 1;
      }
      if (a.occurrence && b.occurrence) {
        return a.sortAt - b.sortAt;
      }
      return 0;
    });
    const out: NoticeCard[] = [];
    for (let i = 0; i < primary.length; i++) {
      out.push(primary[i]);
    }
    for (let i = 0; i < material.length; i++) {
      out.push(material[i]);
    }
    for (let i = 0; i < expired.length; i++) {
      out.push(expired[i]);
    }
    return out;
  }

  /** 填充展示层公共字段。 */
  private static fill(card: NoticeCard, entry: NoticeEntry, nowMillis: number): void {
    const group: NoticeGroup | undefined = entry.group;
    card.entry = entry;
    card.summary = NoticeStatus.fmtDatesCn(entry.summary(), nowMillis);
    card.cat = group !== undefined && group.cat.trim().length > 0 ? group.cat.trim() : '通知';
    card.catCls = NoticeCards.catClsOf(card.cat);
    card.source = group !== undefined ? group.source.trim() : '';
    card.sourceKind = NoticeCards.sourceKindOf(card.source);
    card.senderName = group !== undefined ? group.senderName.trim() : '';
    card.senderBadge = group !== undefined
      ? (group.senderRole.trim().length > 0 ? group.senderRole.trim() : group.senderBadge.trim())
      : '';
    card.ocr = group !== undefined && group.ocr;
    card.updated = (group !== undefined && group.updatedAt.trim().length > 0) || entry.row.editedAt > 0;
    card.aiSummary = group !== undefined ? NoticeStatus.fmtDatesCn(group.aiSummary.trim(), nowMillis) : '';
    card.points = [];
    if (group !== undefined) {
      for (let i = 0; i < group.aiPoints.length && i < 3; i++) {
        card.points.push(NoticeStatus.fmtDatesCn(group.aiPoints[i], nowMillis));
      }
    }
    card.segments = [];
    if (group !== undefined) {
      const compact: NoticeSegment[] = NoticeCards.compactSegments(group.aiSegments);
      for (let i = 0; i < compact.length; i++) {
        const seg: NoticeSegment = new NoticeSegment();
        seg.type = compact[i].type;
        seg.text = NoticeStatus.fmtDatesCn(compact[i].text, nowMillis);
        card.segments.push(seg);
      }
    }
    const status: NoticeStatusInfo = NoticeStatus.ofEntry(entry, nowMillis);
    card.statusLabel = NoticeStatus.fmtDatesCn(status.label, nowMillis);
    card.statusCls = status.cls;
    card.expired = status.expired;
    card.whenAt = status.whenAt;
    card.canDone = !status.expired && !(group !== undefined && NoticeRecurrenceLogic.isLongterm(group));
    card.canRemind = card.canDone;
    // 明细项与原文摘录
    const details: NoticeItemMeta[] = [];
    const quotes: NoticeItemMeta[] = [];
    for (let i = 0; i < entry.items.length; i++) {
      const item: NoticeItemMeta = entry.items[i];
      if (item.kind === 'text' || item.kind === 'follow') {
        if (quotes.length < 2) {
          const quote: NoticeItemMeta = new NoticeItemMeta();
          quote.kind = item.kind;
          quote.label = item.label;
          quote.fromName = item.fromName;
          quote.fromRole = item.fromRole;
          quote.timeText = NoticeStatus.fmtDatesCn(item.timeText, nowMillis);
          quote.text = NoticeStatus.fmtDatesCn(item.text, nowMillis);
          quote.isFollow = item.isFollow;
          quotes.push(quote);
        }
      } else {
        details.push(item);
      }
    }
    card.items = details;
    card.quotes = card.aiSummary.length > 0 ? [] : quotes;
    card.compose = NoticeCards.composeOf(entry.items);
    card.hasRaw = quotes.length > 0 || (group === undefined && entry.row.body.trim().length > 0);
    card.rawTitle = entry.title();
    const more: string[] = [];
    if (details.length > 0) {
      more.push(details.length + ' 项详情');
    }
    let files: number = 0;
    let images: number = 0;
    let forms: number = 0;
    for (let i = 0; i < details.length; i++) {
      if (details[i].kind === 'file') {
        files += 1;
      } else if (details[i].kind === 'img') {
        images += 1;
      } else if (details[i].kind === 'form') {
        forms += 1;
      }
    }
    if (files > 0) {
      more.push(files + ' 个附件');
    }
    if (images > 0) {
      more.push(images + ' 张图片');
    }
    if (forms > 0) {
      more.push(forms + ' 个收集表');
    }
    card.moreText = more.length > 0 ? more.join(' · ') : '';
    card.hasDetail = card.segments.length > 0 || details.length > 0 || quotes.length > 0;
    card.pubTs = NoticeCards.pubTsOf(entry, nowMillis);
    if (group !== undefined && NoticeRecurrenceLogic.isLongterm(group)) {
      card.recurring = !status.expired;
      card.recurLabel = NoticeCards.recurLabelOf(group);
      const next: number = NoticeRecurrenceLogic.recurNext(group, nowMillis);
      card.nextText = next > 0 && !status.expired ? NoticeStatus.dateTimeCnOf(next, nowMillis) : '';
    }
    if (card.timeText.length === 0 && status.whenAt > 0) {
      card.timeText = NoticeStatus.shortTime(status.whenAt);
    }
  }

  static ofSection(cards: NoticeCard[], section: string): NoticeCard[] {
    const out: NoticeCard[] = [];
    for (let i = 0; i < cards.length; i++) {
      if (cards[i].section === section) {
        out.push(cards[i]);
      }
    }
    return out;
  }

  /** 未处理数（期次卡与普通卡都计入；长期定义不计）。 */
  static pendingCount(cards: NoticeCard[], doneKeys: string[]): number {
    let count: number = 0;
    for (let i = 0; i < cards.length; i++) {
      if (cards[i].definition) {
        continue;
      }
      if (doneKeys.indexOf(cards[i].key) < 0) {
        count += 1;
      }
    }
    return count;
  }

  /** 顶部 5 张数据卡 + 已过期数。 */
  static statsOf(cards: NoticeCard[], doneKeys: string[], nowMillis: number): NoticeStats {
    const stats: NoticeStats = new NoticeStats();
    let latest: number = 0;
    for (let i = 0; i < cards.length; i++) {
      const card: NoticeCard = cards[i];
      latest = Math.max(latest, card.pubTs);
      if (card.definition) {
        if (!card.expired) {
          stats.longterm += 1;
        }
        continue;
      }
      if (card.section === NoticeSection.EXPIRED) {
        stats.expired += 1;
        continue;
      }
      if (card.section === NoticeSection.MATERIAL) {
        continue;
      }
      if (doneKeys.indexOf(card.key) >= 0) {
        continue;
      }
      stats.pending += 1;
      if (card.whenAt > nowMillis) {
        const left: number = card.whenAt - nowMillis;
        if (left <= 24 * 60 * 60 * 1000) {
          stats.urgent += 1;
        }
        if (left <= 7 * 24 * 60 * 60 * 1000) {
          stats.week += 1;
        }
      }
    }
    stats.latestText = NoticeStatus.latestTextOf(latest, nowMillis);
    return stats;
  }

  /** 简报「最近截止」：待处理且有时间，升序取前 3。 */
  static briefNext(cards: NoticeCard[], doneKeys: string[], nowMillis: number, max: number = 3): NoticeCard[] {
    const out: NoticeCard[] = [];
    for (let i = 0; i < cards.length; i++) {
      const card: NoticeCard = cards[i];
      if (card.definition || card.section !== NoticeSection.PRIMARY) {
        continue;
      }
      if (doneKeys.indexOf(card.key) >= 0) {
        continue;
      }
      if (card.whenAt <= 0) {
        continue;
      }
      out.push(card);
    }
    out.sort((a: NoticeCard, b: NoticeCard) => a.whenAt - b.whenAt);
    return out.length > max ? out.slice(0, max) : out;
  }

  /** 分类 chips（未过期、非空）。 */
  static categories(cards: NoticeCard[]): string[] {
    const seen: Map<string, boolean> = new Map<string, boolean>();
    const out: string[] = [];
    for (let i = 0; i < cards.length; i++) {
      const cat: string = cards[i].cat.trim();
      if (cat.length === 0 || cards[i].expired) {
        continue;
      }
      if (!seen.has(cat)) {
        seen.set(cat, true);
        out.push(cat);
      }
    }
    return out;
  }

  /** 长期安排清单（进行中的定义卡）。 */
  static longtermCards(cards: NoticeCard[]): NoticeCard[] {
    const out: NoticeCard[] = [];
    for (let i = 0; i < cards.length; i++) {
      if (cards[i].definition && !cards[i].expired) {
        out.push(cards[i]);
      }
    }
    return out;
  }

  /** 已处理状态用：卡片是否可标记。 */
  static doneKey(card: NoticeCard): string {
    return card.key;
  }

  static catClsOf(cat: string): string {
    if (cat === '教务') {
      return 'jw';
    }
    if (cat === '团务') {
      return 'tw';
    }
    if (cat === '考试') {
      return 'ks';
    }
    if (cat === '缴费') {
      return 'jf';
    }
    if (cat === '活动') {
      return 'hd';
    }
    if (cat === '班级事务') {
      return 'qt';
    }
    let hash: number = 0;
    for (let i = 0; i < cat.length; i++) {
      hash = (hash * 31 + cat.charCodeAt(i)) >>> 0;
    }
    return NoticeCards.CAT_PALETTE[hash % NoticeCards.CAT_PALETTE.length];
  }

  static sourceKindOf(source: string): string {
    if (source.indexOf('QQ') >= 0) {
      return 'qq';
    }
    if (source.indexOf('微信') >= 0) {
      return 'wx';
    }
    return 'doc';
  }

  static recurLabelOf(group: NoticeGroup): string {
    const recur: NoticeRecurrence | undefined = group.recurrence;
    if (recur === undefined) {
      return '';
    }
    const raw: string = recur.label.trim();
    if (raw.length > 0) {
      return raw;
    }
    const time: string = recur.time.trim();
    if (recur.freq === 'daily') {
      return '每天 ' + time;
    }
    if (recur.freq === 'weekly') {
      return '每周' + weekCn(recur.weekday) + ' ' + time;
    }
    if (recur.freq === 'monthly_day') {
      return '每月 ' + recur.day + ' 日 ' + time;
    }
    const last: number = recur.weeks.length > 0 ? recur.weeks[recur.weeks.length - 1] : 3;
    return '每月前 ' + last + ' 周' + weekCn(recur.weekday) + ' ' + time;
  }

  static compactSegments(segments: NoticeSegment[]): NoticeSegment[] {
    const map: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < segments.length; i++) {
      const type: string = segments[i].type.trim();
      const text: string = segments[i].text.trim();
      if (type.length === 0 || text.length === 0) {
        continue;
      }
      const existing: string | undefined = map.get(type);
      map.set(type, existing === undefined ? text : existing + '；' + text);
    }
    const out: NoticeSegment[] = [];
    for (let i = 0; i < NoticeCards.SEG_ORDER.length; i++) {
      const type: string = NoticeCards.SEG_ORDER[i];
      const text: string | undefined = map.get(type);
      if (text !== undefined) {
        const seg: NoticeSegment = new NoticeSegment();
        seg.type = type;
        seg.text = text;
        out.push(seg);
      }
    }
    return out;
  }

  static segClsOf(type: string): string {
    if (type === '时间') {
      return 'time';
    }
    if (type === '地点') {
      return 'place';
    }
    if (type === '对象') {
      return 'who';
    }
    if (type === '报名') {
      return 'join';
    }
    if (type === '截止') {
      return 'due';
    }
    if (type === '要求') {
      return 'rule';
    }
    if (type === '联系方式') {
      return 'contact';
    }
    if (type === '补充') {
      return 'supp';
    }
    return 'info';
  }

  private static composeOf(items: NoticeItemMeta[]): NoticeComposeChip[] {
    const count: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < items.length; i++) {
      const kind: string = items[i].kind;
      const n: number | undefined = count.get(kind);
      count.set(kind, n === undefined ? 1 : n + 1);
    }
    const out: NoticeComposeChip[] = [];
    for (let i = 0; i < NoticeCards.COMPOSE_DEFS.length; i++) {
      const kind: string = NoticeCards.COMPOSE_DEFS[i];
      const n: number | undefined = count.get(kind);
      if (n !== undefined && n > 0) {
        const chip: NoticeComposeChip = new NoticeComposeChip();
        chip.n = n;
        chip.label = NoticeCards.COMPOSE_LABELS[i];
        out.push(chip);
      }
    }
    return out;
  }

  private static pubTsOf(entry: NoticeEntry, nowMillis: number): number {
    let best: number = entry.row.ts;
    if (entry.group !== undefined) {
      const updated: number = NoticeRecurrenceLogic.parseTs(entry.group.updatedAt);
      if (updated > best) {
        best = updated;
      }
    }
    for (let i = 0; i < entry.items.length; i++) {
      const t: number = NoticeRecurrenceLogic.parseTs(entry.items[i].timeText);
      if (t > best && t <= nowMillis) {
        best = t;
      }
    }
    return best;
  }
}

function weekCn(weekday: number): string {
  const names: string[] = ['日', '一', '二', '三', '四', '五', '六'];
  if (weekday < 0 || weekday > 6) {
    return '';
  }
  return names[weekday];
}
