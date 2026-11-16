import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { MarksRefreshResult, MarksUpdateResult } from '../../data/marks/MarksRepository';
import { NoticeArchiveFile, NoticeItemMeta, NoticeMsgMeta, NoticeSegment } from '../../data/notices/NoticeModels';
import { NoticeEntry, NoticesRepository, NoticesResult } from '../../data/notices/NoticesRepository';
import { NoticeCard, NoticeCards, NoticeComposeChip, NoticeStats } from '../../features/notices/NoticeCards';
import { NoticeSection } from '../../features/notices/NoticeRecurrence';
import { NoticeStatus } from '../../features/notices/NoticeStatus';
import { HomeNtBadge } from '../../data/home/HomeNtBadge';
import { HidePrefs } from '../../data/home/HidePrefs';
import { Blob } from '../../data/sync/JsonBlob';
import { Motion } from '../theme/Motion';

const NT_BG: string = '#F4F0E6';
const NT_CARD: string = '#FFFCF6';
const NT_CARD_SOFT: string = '#F8F3E9';
const NT_BRIEF: string = '#F3F7F1';
const NT_LINE: string = '#E7DED0';
const NT_LINE_STRONG: string = '#DCD1BF';
const NT_INK: string = '#303A35';
const NT_INK_2: string = '#5C6860';
const NT_INK_3: string = '#667166';
const NT_CY: string = '#5E8F87';
const NT_CY_DEEP: string = '#46776F';
const NT_CY_INK: string = '#3F6F66';
const NT_CY_TINT: string = '#EAF2EC';
const NT_BL_INK: string = '#4E6D8C';
const NT_BL_TINT: string = '#EDF2F7';
const NT_SD_INK: string = '#8A643B';
const NT_SD_TINT: string = '#FAF3E6';
const NT_ROSE_INK: string = '#9C5147';
const NT_ROSE_TINT: string = '#F7EDEB';
const NT_VIOLET_INK: string = '#66579A';
const NT_VIOLET_TINT: string = '#F1EEF7';
const NT_GREY_INK: string = '#5F6A61';
const NT_GREY_TINT: string = '#F0F2F1';

/**
 * 通知工具：对齐「枫丹工具箱」微信小程序 pages/nt 的界面与口径。
 *
 * - 顶部简报：待处理 / 24h 截止 / 7 天内 / 长期通知 / 最新发布 五张可点数据卡；
 * - 两级筛选：状态 chips（全部 / 待处理 / 已截止 / 已隐藏）+ 分类 chips；
 * - 卡片：分类 / 长期安排 / OCR / 状态胶囊 / 来源 / AI 摘要 / 字段拆分 / 附件 / 图片 / 原文摘录 / 组成；
 * - 长期安排：24h 内期次卡（本次已处理）+ 长期清单；已结束归入已过期；
 * - 已处理写 `marks kind='ntdone'`；隐藏走 userdata.hide（可单条恢复 / 全部恢复）。
 */
@Component
export struct NoticeScreen {
  onClose: () => void = () => {
  };

  @State private cards: NoticeCard[] = [];
  @State private dataVersion: number = 0;
  @State private doneKeys: string[] = [];
  @State private hiddenIds: string[] = [];
  @State private stats: NoticeStats = new NoticeStats();
  @State private brief: NoticeCard[] = [];
  @State private categories: string[] = [];
  @State private cat: string = '全部';
  @State private filter: string = 'all';
  @State private cardKey: string = '';
  @State private showExpired: boolean = false;
  @State private showInfo: boolean = true;
  @State private expandedKeys: string[] = [];
  @State private loading: boolean = true;
  @State private syncing: boolean = false;
  @State private errorMsg: string = '';
  @State private notice: string = '';
  @State private now: number = Date.now();
  @State private entered: boolean = false;
  @State private previewOpen: boolean = false;
  @State private previewSrc: string = '';
  @State private rawOpen: boolean = false;
  @State private rawTitle: string = '';
  @State private rawBody: string = '';
  @State private rawBlocks: NoticeItemMeta[] = [];

  aboutToAppear(): void {
    HomeNtBadge.markOpened(Services.currentSid);
    this.reload(false);
  }

  private async reload(force: boolean): Promise<void> {
    this.loading = this.cards.length === 0;
    this.syncing = true;
    this.errorMsg = '';
    const result: NoticesResult = await Services.notices.load(force);
    const marksResult: MarksRefreshResult = await Services.marks.refresh(false);
    this.now = Date.now();
    const hide = HidePrefs.read(Services.userdata.currentSections());
    const hidden: string[] = [];
    hide.ntHide.forEach((id: string) => {
      hidden.push(id);
    });
    this.hiddenIds = hidden;
    const built: NoticeCard[] = NoticeCards.build(result.entries, this.now);
    for (let i = 0; i < built.length; i++) {
      const card: NoticeCard = built[i];
      const entryId: string = card.entry !== undefined ? card.entry.row.id : '';
      const groupId: string = card.key.indexOf('@occ:') > 0
        ? card.key.substring(0, card.key.indexOf('@occ:')) : card.key;
      card.hiddenLocal = hidden.indexOf(entryId) >= 0 || hidden.indexOf(groupId) >= 0;
    }
    this.cards = built;
    this.dataVersion = this.dataVersion + 1;
    this.categories = NoticeCards.categories(built);
    if (this.cat !== '全部' && this.categories.indexOf(this.cat) < 0) {
      this.cat = '全部';
    }
    const done: string[] = [];
    const snapshot = Services.marks.marks();
    for (let i = 0; i < built.length; i++) {
      const key: string = built[i].key;
      if (snapshot.isDone(MarkKind.NT_DONE, key) || this.doneKeys.indexOf(key) >= 0) {
        done.push(key);
      }
    }
    this.doneKeys = done;
    this.refreshDigest();
    if (!result.ok) {
      this.errorMsg = result.message;
    } else if (marksResult.error !== undefined) {
      this.errorMsg = '已处理状态同步失败：' + marksResult.error.displayMessage();
    }
    this.loading = false;
    this.syncing = false;
    if (!this.entered) {
      setTimeout(() => {
        this.entered = true;
      }, 40);
    }
  }

  private refreshDigest(): void {
    const visible: NoticeCard[] = [];
    for (let i = 0; i < this.cards.length; i++) {
      if (!this.cards[i].hiddenLocal) {
        visible.push(this.cards[i]);
      }
    }
    this.stats = NoticeCards.statsOf(visible, this.doneKeys, this.now);
    this.brief = NoticeCards.briefNext(visible, this.doneKeys, this.now, 3);
  }

  private isDone(key: string): boolean {
    return this.doneKeys.indexOf(key) >= 0;
  }

  private isExpanded(key: string): boolean {
    return this.expandedKeys.indexOf(key) >= 0;
  }

  private mode(): string {
    return this.cardKey.length > 0 ? this.cardKey : this.filter;
  }

  private matchesCat(card: NoticeCard): boolean {
    return this.cat === '全部' || card.cat === this.cat;
  }

  private inWindow(card: NoticeCard, days: number): boolean {
    if (card.whenAt <= this.now) {
      return false;
    }
    return card.whenAt - this.now <= days * 24 * 60 * 60 * 1000;
  }

  private currentCards(): NoticeCard[] {
    const mode: string = this.mode();
    const out: NoticeCard[] = [];
    for (let i = 0; i < this.cards.length; i++) {
      const card: NoticeCard = this.cards[i];
      if (mode === 'hidden') {
        if (card.hiddenLocal && this.matchesCat(card)) {
          out.push(card);
        }
        continue;
      }
      if (card.hiddenLocal || !this.matchesCat(card)) {
        continue;
      }
      if (mode === 'longterm') {
        continue;
      }
      if (mode === 'latest') {
        out.push(card);
      } else if (mode === 'expired') {
        if (card.section === NoticeSection.EXPIRED) {
          out.push(card);
        }
      } else if (mode === 'active' || mode === 'pending') {
        if (card.section === NoticeSection.PRIMARY && !card.definition && !this.isDone(card.key)) {
          out.push(card);
        }
      } else if (mode === 'urgent' || mode === 'week') {
        if (card.section === NoticeSection.PRIMARY && !card.definition && !this.isDone(card.key)
          && this.inWindow(card, mode === 'urgent' ? 1 : 7)) {
          out.push(card);
        }
      } else if (card.section === NoticeSection.PRIMARY) {
        out.push(card);
      }
    }
    if (mode === 'latest') {
      out.sort((a: NoticeCard, b: NoticeCard) => b.pubTs - a.pubTs);
    } else if (mode === 'urgent' || mode === 'week') {
      out.sort((a: NoticeCard, b: NoticeCard) => a.whenAt - b.whenAt);
    } else if (mode === 'expired') {
      out.sort((a: NoticeCard, b: NoticeCard) => b.sortAt - a.sortAt);
    }
    return out;
  }

  private infoCards(): NoticeCard[] {
    const out: NoticeCard[] = [];
    if (this.mode() !== 'all') {
      return out;
    }
    for (let i = 0; i < this.cards.length; i++) {
      const card: NoticeCard = this.cards[i];
      if (!card.hiddenLocal && this.matchesCat(card) && card.section === NoticeSection.MATERIAL) {
        out.push(card);
      }
    }
    return out;
  }

  private expiredCards(): NoticeCard[] {
    const out: NoticeCard[] = [];
    if (this.mode() !== 'all' && this.mode() !== 'active') {
      return out;
    }
    for (let i = 0; i < this.cards.length; i++) {
      const card: NoticeCard = this.cards[i];
      if (!card.hiddenLocal && this.matchesCat(card) && card.section === NoticeSection.EXPIRED
        && !card.definition) {
        out.push(card);
      }
    }
    return out;
  }

  private longtermList(): NoticeCard[] {
    const out: NoticeCard[] = [];
    if (this.mode() !== 'longterm') {
      return out;
    }
    for (let i = 0; i < this.cards.length; i++) {
      const card: NoticeCard = this.cards[i];
      if (!card.hiddenLocal && this.matchesCat(card) && card.definition && !card.expired) {
        out.push(card);
      }
    }
    return out;
  }

  private async toggleDone(card: NoticeCard): Promise<void> {
    const key: string = card.key;
    const next: boolean = !this.isDone(key);
    const copy: string[] = this.doneKeys.slice(0);
    if (next) {
      if (copy.indexOf(key) < 0) {
        copy.push(key);
      }
    } else {
      const index: number = copy.indexOf(key);
      if (index >= 0) {
        copy.splice(index, 1);
      }
    }
    this.doneKeys = copy;
    this.notice = '';
    this.refreshDigest();
    const result: MarksUpdateResult = await Services.marks.setMark(MarkKind.NT_DONE, key, next);
    if (!result.ok) {
      this.notice = '网络不佳：已在本机标记，稍后自动补发';
    }
  }

  private async hideCard(card: NoticeCard): Promise<void> {
    if (card.entry === undefined) {
      return;
    }
    const id: string = card.entry.row.id;
    const current: Blob = Services.userdata.currentSections();
    const data = HidePrefs.read(current);
    data.ntHide.add(id);
    await Services.userdata.updateCurrent(HidePrefs.write(current, data));
    const keys: Set<string> = new Set<string>();
    keys.add('hide');
    await Services.userdata.push(false, keys);
    this.notice = '已隐藏该通知（仅自己不可见，可在「已隐藏」恢复）';
    await this.reload(true);
  }

  private async restoreCard(card: NoticeCard): Promise<void> {
    if (card.entry === undefined) {
      return;
    }
    const id: string = card.entry.row.id;
    const current: Blob = Services.userdata.currentSections();
    const data = HidePrefs.read(current);
    data.ntHide.delete(id);
    await Services.userdata.updateCurrent(HidePrefs.write(current, data));
    const keys: Set<string> = new Set<string>();
    keys.add('hide');
    await Services.userdata.push(false, keys);
    this.notice = '已恢复该通知';
    await this.reload(true);
  }

  private async restoreAll(): Promise<void> {
    if (this.hiddenIds.length === 0) {
      return;
    }
    const current: Blob = Services.userdata.currentSections();
    const data = HidePrefs.read(current);
    data.ntHide.clear();
    await Services.userdata.updateCurrent(HidePrefs.write(current, data));
    const keys: Set<string> = new Set<string>();
    keys.add('hide');
    await Services.userdata.push(false, keys);
    this.notice = '已恢复全部隐藏通知';
    await this.reload(true);
  }

  private toggleExpand(key: string): void {
    const copy: string[] = this.expandedKeys.slice(0);
    const index: number = copy.indexOf(key);
    if (index >= 0) {
      copy.splice(index, 1);
    } else {
      copy.push(key);
    }
    this.expandedKeys = copy;
  }

  private openPreview(src: string): void {
    if (src.length === 0) {
      return;
    }
    this.previewSrc = src;
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.previewOpen = true;
    });
  }

  private closePreview(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.previewOpen = false;
    });
  }

  private openRaw(card: NoticeCard): void {
    this.rawTitle = card.rawTitle.length > 0 ? card.rawTitle : card.title;
    const blocks: NoticeItemMeta[] = [];
    for (let i = 0; i < card.quotes.length; i++) {
      blocks.push(card.quotes[i]);
    }
    if (blocks.length === 0 && card.entry !== undefined && card.entry.row.body.trim().length > 0) {
      this.rawBody = card.entry.row.body.trim();
    } else {
      this.rawBody = '';
    }
    this.rawBlocks = blocks;
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.rawOpen = true;
    });
  }

  private closeRaw(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.rawOpen = false;
    });
  }

  private openUrl(url: string): void {
    if (url.length === 0) {
      return;
    }
    if (url.indexOf('http') !== 0) {
      this.notice = '该附件仅有内嵌数据，当前设备无法直接打开';
      return;
    }
    const context = AppGlobal.context;
    if (context === undefined) {
      this.notice = '无法打开链接';
      return;
    }
    try {
      context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }).catch(() => {
        this.notice = '无法打开该链接';
      });
    } catch (e) {
      this.notice = '无法打开该链接';
    }
  }

  private pickCard(key: string): void {
    if (this.cardKey === key) {
      this.cardKey = '';
      this.filter = 'all';
    } else {
      this.cardKey = key;
      this.filter = key === 'pending' ? 'active' : key;
      if (key === 'longterm') {
        this.showExpired = false;
      }
    }
    this.cat = '全部';
  }

  private pickFilter(value: string): void {
    this.cardKey = '';
    this.filter = value;
    if (value === 'expired') {
      this.showExpired = true;
    }
  }

  private catBg(cls: string): string {
    if (cls === 'jw') {
      return NT_BL_TINT;
    }
    if (cls === 'tw') {
      return NT_CY_TINT;
    }
    if (cls === 'ks') {
      return NT_SD_TINT;
    }
    if (cls === 'jf') {
      return NT_ROSE_TINT;
    }
    if (cls === 'hd') {
      return NT_VIOLET_TINT;
    }
    return NT_GREY_TINT;
  }

  private catFg(cls: string): string {
    if (cls === 'jw') {
      return NT_BL_INK;
    }
    if (cls === 'tw') {
      return NT_CY_INK;
    }
    if (cls === 'ks') {
      return NT_SD_INK;
    }
    if (cls === 'jf') {
      return NT_ROSE_INK;
    }
    if (cls === 'hd') {
      return NT_VIOLET_INK;
    }
    return NT_GREY_INK;
  }

  private statusBg(cls: string): string {
    if (cls === 'urgent' || cls === 'alert') {
      return NT_ROSE_TINT;
    }
    if (cls === 'active') {
      return NT_CY_TINT;
    }
    if (cls === 'extended') {
      return NT_SD_TINT;
    }
    if (cls === 'recurring') {
      return NT_BL_TINT;
    }
    return NT_GREY_TINT;
  }

  private statusFg(cls: string): string {
    if (cls === 'urgent' || cls === 'alert') {
      return NT_ROSE_INK;
    }
    if (cls === 'active') {
      return NT_CY_INK;
    }
    if (cls === 'extended') {
      return NT_SD_INK;
    }
    if (cls === 'recurring') {
      return NT_BL_INK;
    }
    return NT_INK_2;
  }

  private typeChipBg(cls: string): string {
    if (cls === 'time' || cls === 'due') {
      return NT_SD_TINT;
    }
    if (cls === 'rule') {
      return NT_ROSE_TINT;
    }
    return NT_GREY_TINT;
  }

  private typeChipFg(cls: string): string {
    if (cls === 'time' || cls === 'due') {
      return NT_SD_INK;
    }
    if (cls === 'rule') {
      return NT_ROSE_INK;
    }
    return NT_INK_2;
  }

  @Builder
  miniTag(text: string, bg: string, fg: string) {
    Text(text)
      .fontSize(10)
      .fontColor(fg)
      .backgroundColor(bg)
      .borderRadius(5)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .maxLines(1)
      .margin({ right: 6, bottom: 2 })
  }

  @Builder
  filterChip(value: string, text: string) {
    Text(text)
      .fontSize(12)
      .fontColor((this.filter === value && this.cardKey.length === 0) ? '#FFFFFF' : NT_INK_2)
      .backgroundColor((this.filter === value && this.cardKey.length === 0) ? NT_CY_DEEP : NT_CARD)
      .border({ width: 1, color: (this.filter === value && this.cardKey.length === 0) ? NT_CY_DEEP : NT_LINE })
      .borderRadius(999)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.pickFilter(value);
      })
  }

  @Builder
  hiddenChip() {
    Text('已隐藏' + (this.hiddenIds.length > 0 ? ' ' + this.hiddenIds.length : ''))
      .fontSize(12)
      .fontColor((this.filter === 'hidden' && this.cardKey.length === 0) ? '#FFFFFF' : NT_INK_2)
      .backgroundColor((this.filter === 'hidden' && this.cardKey.length === 0) ? NT_CY_DEEP : NT_CARD)
      .border({ width: 1, color: (this.filter === 'hidden' && this.cardKey.length === 0) ? NT_CY_DEEP : NT_LINE })
      .borderRadius(999)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.pickFilter('hidden');
      })
  }

  private statValue(key: string): string {
    if (key === 'pending') {
      return '' + this.stats.pending;
    }
    if (key === 'urgent') {
      return '' + this.stats.urgent;
    }
    if (key === 'week') {
      return '' + this.stats.week;
    }
    if (key === 'longterm') {
      return '' + this.stats.longterm;
    }
    return this.stats.latestText;
  }

  private statLabel(key: string): string {
    if (key === 'pending') {
      return '待处理';
    }
    if (key === 'urgent') {
      return '24h 截止';
    }
    if (key === 'week') {
      return '7 天内';
    }
    if (key === 'longterm') {
      return '长期通知';
    }
    return '最新发布';
  }

  @Builder
  dataCard(key: string) {
    Column() {
      Text(this.statValue(key))
        .fontSize(key === 'latest' ? 17 : 16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.cardKey === key ? '#FFFFFF' : NT_INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.statLabel(key))
        .fontSize(10)
        .fontColor(this.cardKey === key ? '#FFFFFF' : NT_INK_2)
        .margin({ top: 2 })
    }
    .width(key === 'longterm' || key === 'latest' ? '47%' : '30%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.cardKey === key ? NT_CY_DEEP : NT_CARD)
    .border({ width: 1, color: this.cardKey === key ? NT_CY_DEEP : NT_LINE })
    .borderRadius(10)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.pickCard(key);
    })
  }

  @Builder
  sectionHeader(title: string, count: number, foldable: boolean, open: boolean, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(NT_INK_2)
      Text(' · ' + count)
        .fontSize(11)
        .fontColor(NT_INK_3)
      Blank()
      if (foldable) {
        Text(open ? '▴ 收起' : '▾ 展开')
          .fontSize(11)
          .fontColor(NT_CY_INK)
      }
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 10, bottom: 6 })
    .onClick(() => {
      if (foldable) {
        onTap();
      }
    })
  }

  @Builder
  segmentRow(segment: NoticeSegment) {
    Row() {
      Text(segment.type)
        .fontSize(10)
        .fontColor(this.typeChipFg(NoticeCards.segClsOf(segment.type)))
        .backgroundColor(this.typeChipBg(NoticeCards.segClsOf(segment.type)))
        .borderRadius(5)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .width(54)
        .textAlign(TextAlign.Center)
      Text(segment.text)
        .fontSize(12)
        .fontColor(NT_INK)
        .layoutWeight(1)
        .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 1 }, color: NT_LINE })
  }

  @Builder
  itemRow(item: NoticeItemMeta, cardKey: string, index: number) {
    if (item.kind === 'file') {
      Row() {
        Text(item.extText.length > 0 ? item.extText : '文件')
          .fontSize(10)
          .fontColor(NT_GREY_INK)
          .backgroundColor(NT_GREY_TINT)
          .borderRadius(6)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
        Column() {
          Text(item.name)
            .fontSize(12)
            .fontColor(NT_INK)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.sizeText.length > 0 ? item.sizeText : '附件')
            .fontSize(10)
            .fontColor(NT_INK_3)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        if (item.hasUrl) {
          Text('打开')
            .fontSize(11)
            .fontColor(NT_CY_INK)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .border({ width: 1, color: NT_LINE_STRONG })
            .borderRadius(999)
            .onClick(() => {
              this.openUrl(item.url);
            })
        } else if (item.archiveOk) {
          Text('已识别 ' + item.archiveCount)
            .fontSize(10)
            .fontColor(NT_BL_INK)
        } else {
          Text('待获取')
            .fontSize(10)
            .fontColor(NT_INK_3)
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .border({ width: { bottom: 1 }, color: NT_LINE })

      if (item.archiveOk) {
        Column() {
          if (item.archiveSummary.length > 0) {
            Text(item.archiveSummary)
              .fontSize(10)
              .fontColor(NT_INK_3)
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          ForEach(item.archiveFiles, (af: NoticeArchiveFile, afIndex: number) => {
            Row() {
              Text(af.extText)
                .fontSize(9)
                .fontColor(NT_INK_2)
                .width(30)
              Text(af.name)
                .fontSize(11)
                .fontColor(NT_INK)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(af.sizeText)
                .fontSize(9)
                .fontColor(NT_INK_3)
              Text(af.hasUrl ? '可预览' : '仅清单')
                .fontSize(9)
                .fontColor(af.hasUrl ? NT_CY_INK : NT_INK_3)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ top: 3, bottom: 3 })
          }, (af: NoticeArchiveFile, afIndex: number) => cardKey + '_af' + index + '_' + afIndex + '_' + af.name)
        }
        .width('100%')
        .padding({ left: 46, bottom: 6 })
      }
    } else if (item.kind === 'form') {
      Row() {
        Text('表')
          .fontSize(11)
          .fontColor(NT_CY_INK)
          .backgroundColor(NT_CY_TINT)
          .borderRadius(6)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
        Column() {
          Text(item.name)
            .fontSize(12)
            .fontColor(NT_INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.statusText + (item.note.length > 0 ? ' · ' + item.note : ''))
            .fontSize(10)
            .fontColor(NT_INK_3)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        if (item.hasUrl) {
          Text('打开')
            .fontSize(11)
            .fontColor(NT_CY_INK)
            .onClick(() => {
              this.openUrl(item.url);
            })
        } else {
          Text('QQ 表单')
            .fontSize(10)
            .fontColor(NT_INK_3)
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .border({ width: { bottom: 1 }, color: NT_LINE })
    } else if (item.kind === 'merged') {
      Column() {
        Row() {
          Text(item.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(NT_INK)
            .layoutWeight(1)
          Text(item.count + ' 条')
            .fontSize(10)
            .fontColor(NT_INK_3)
        }
        .width('100%')
        ForEach(item.messages, (msg: NoticeMsgMeta, msgIndex: number) => {
          Column() {
            Row({ space: 6 }) {
              if (msg.fromBadge.length > 0) {
                Text(msg.fromBadge)
                  .fontSize(9)
                  .fontColor(NT_BL_INK)
              }
              if (msg.fromName.length > 0) {
                Text(msg.fromName)
                  .fontSize(10)
                  .fontColor(NT_INK_3)
              }
              if (msg.timeText.length > 0) {
                Text(msg.timeText)
                  .fontSize(9)
                  .fontColor(NT_INK_3)
              }
            }
            Text(msg.text)
              .fontSize(11)
              .fontColor(NT_INK)
              .width('100%')
              .margin({ top: 2 })
          }
          .width('100%')
          .margin({ top: 6 })
        }, (msg: NoticeMsgMeta, msgIndex: number) => cardKey + '_msg' + index + '_' + msgIndex)
      }
      .width('100%')
      .padding(8)
      .backgroundColor(NT_CARD_SOFT)
      .borderRadius(8)
      .margin({ top: 6 })
    } else if (item.kind === 'link' || item.kind === 'mini' || item.kind === 'article') {
      Row() {
        Text(item.kind === 'article' ? '公' : (item.kind === 'mini' ? '程' : '链'))
          .fontSize(11)
          .fontColor(NT_INK_2)
          .backgroundColor(NT_GREY_TINT)
          .borderRadius(6)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
        Column() {
          Text(item.name)
            .fontSize(12)
            .fontColor(NT_INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.account.length > 0 ? item.account
            : (item.host.length > 0 ? item.host : (item.note.length > 0 ? item.note : '外部链接')))
            .fontSize(10)
            .fontColor(NT_INK_3)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        if (item.hasUrl) {
          Text('打开')
            .fontSize(11)
            .fontColor(NT_CY_INK)
            .onClick(() => {
              this.openUrl(item.url);
            })
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .border({ width: { bottom: 1 }, color: NT_LINE })
    } else if (item.kind === 'img') {
      Image(item.url)
        .width('48.5%')
        .height(110)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .backgroundColor(NT_GREY_TINT)
        .margin({ top: 6 })
        .onClick(() => {
          this.openPreview(item.url);
        })
    }
  }

  @Builder
  noticeCard(card: NoticeCard) {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.miniTag(card.cat, this.catBg(card.catCls), this.catFg(card.catCls))
        if (card.occurrence || card.recurring) {
          this.miniTag('长期安排', NT_BL_TINT, NT_BL_INK)
        }
        if (card.ocr) {
          this.miniTag('OCR', NT_GREY_TINT, NT_INK_2)
        }
        Text(card.statusLabel)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.statusFg(card.statusCls))
          .backgroundColor(this.statusBg(card.statusCls))
          .borderRadius(999)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .maxLines(1)
          .margin({ right: 6, bottom: 2 })
        if (card.hiddenLocal) {
          this.miniTag('已隐藏', NT_GREY_TINT, NT_INK_2)
        }
        if (card.updated) {
          this.miniTag('已更新', NT_SD_TINT, NT_SD_INK)
        }
        if (card.hasRaw) {
          Text('原始消息')
            .fontSize(10)
            .fontColor(NT_INK_3)
            .padding({ left: 4, right: 4, top: 4, bottom: 4 })
            .onClick(() => {
              this.openRaw(card);
            })
        }
      }
      .width('100%')

      Text(card.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDone(card.key) ? NT_INK_3 : NT_INK)
        .decoration({ type: this.isDone(card.key) ? TextDecorationType.LineThrough : TextDecorationType.None })
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      if (card.source.length > 0 || card.senderName.length > 0 || card.senderBadge.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          if (card.source.length > 0) {
            Row() {
              Circle()
                .width(5)
                .height(5)
                .fill(card.sourceKind === 'qq' ? NT_BL_INK : (card.sourceKind === 'wx' ? NT_CY : NT_INK_3))
              Text(card.source)
                .fontSize(10)
                .fontColor(NT_INK_2)
                .margin({ left: 5 })
            }
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .border({ width: 1, color: NT_LINE })
            .borderRadius(999)
            .margin({ right: 8, top: 3 })
          }
          if (card.senderBadge.length > 0) {
            Text(card.senderBadge)
              .fontSize(9)
              .fontColor(NT_BL_INK)
              .backgroundColor(NT_BL_TINT)
              .borderRadius(5)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .margin({ right: 6, top: 3 })
          }
          if (card.senderName.length > 0) {
            Text(card.senderName)
              .fontSize(10)
              .fontColor(NT_INK_3)
              .margin({ top: 3 })
          }
        }
        .width('100%')
        .margin({ top: 4 })
      }

      if (card.recurring && card.nextText.length > 0) {
        Row() {
          Text('下次 ' + card.nextText)
            .fontSize(11)
            .fontColor(NT_BL_INK)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .backgroundColor(NT_BL_TINT)
        .borderRadius(7)
        .margin({ top: 8 })
      }

      if (card.aiSummary.length > 0) {
        Column() {
          Row() {
            Text('AI')
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(NT_CY_INK)
              .backgroundColor(NT_CY_TINT)
              .borderRadius(4)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            Text('摘要')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(NT_CY_INK)
              .margin({ left: 4 })
          }
          Text(card.aiSummary)
            .fontSize(12)
            .fontColor(NT_INK)
            .width('100%')
            .maxLines(this.isExpanded(card.key) ? 30 : 4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
          if (card.points.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(card.points, (point: string, pointIndex: number) => {
                Text(point)
                  .fontSize(10)
                  .fontColor(NT_CY_INK)
                  .backgroundColor(NT_CY_TINT)
                  .borderRadius(5)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .margin({ right: 6, bottom: 5 })
              }, (point: string, pointIndex: number) => card.key + '_pt' + pointIndex)
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding(8)
        .backgroundColor(NT_CARD_SOFT)
        .borderRadius(9)
        .margin({ top: 8 })
      }

      if (!this.isExpanded(card.key) && card.moreText.length > 0) {
        Text(card.moreText)
          .fontSize(10)
          .fontColor(NT_INK_3)
          .width('100%')
          .margin({ top: 8 })
      }

      if (this.isExpanded(card.key)) {
        Column() {
          if (card.segments.length > 0) {
            Column() {
              ForEach(card.segments, (segment: NoticeSegment, segmentIndex: number) => {
                this.segmentRow(segment)
              }, (segment: NoticeSegment, segmentIndex: number) => card.key + '_seg' + segmentIndex + '_' + segment.type)
            }
            .width('100%')
            .margin({ top: 8 })
            .border({ width: { top: 1 }, color: NT_LINE })
          }

          if (card.items.length > 0) {
            Column() {
              ForEach(card.items, (item: NoticeItemMeta, itemIndex: number) => {
                this.itemRow(item, card.key, itemIndex)
              }, (item: NoticeItemMeta, itemIndex: number) => card.key + '_it' + itemIndex + '_' + item.kind)
            }
            .width('100%')
            .margin({ top: 6 })
          }

          if (card.quotes.length > 0) {
            Column() {
              ForEach(card.quotes, (quote: NoticeItemMeta, quoteIndex: number) => {
                Column() {
                  Row({ space: 6 }) {
                    Text(quote.label)
                      .fontSize(9)
                      .fontColor(NT_SD_INK)
                      .backgroundColor(NT_SD_TINT)
                      .borderRadius(4)
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    if (quote.fromName.length > 0) {
                      Text(quote.fromName)
                        .fontSize(9)
                        .fontColor(NT_INK_3)
                    }
                    if (quote.timeText.length > 0) {
                      Text(quote.timeText)
                        .fontSize(9)
                        .fontColor(NT_INK_3)
                    }
                  }
                  Text(quote.text)
                    .fontSize(11)
                    .fontColor(NT_INK)
                    .width('100%')
                    .maxLines(6)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding(8)
                .backgroundColor(NT_CARD_SOFT)
                .borderRadius(8)
                .margin({ top: 6 })
              }, (quote: NoticeItemMeta, quoteIndex: number) => card.key + '_q' + quoteIndex)
            }
            .width('100%')
            .margin({ top: 4 })
          }

          if (card.compose.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(card.compose, (chip: NoticeComposeChip, chipIndex: number) => {
                Row() {
                  Text('' + chip.n)
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(NT_CY_INK)
                  Text(' ' + chip.label)
                    .fontSize(9)
                    .fontColor(NT_INK_2)
                }
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .border({ width: 1, color: NT_LINE })
                .borderRadius(999)
                .margin({ right: 6, bottom: 5 })
              }, (chip: NoticeComposeChip, chipIndex: number) => card.key + '_cp' + chipIndex)
            }
            .width('100%')
            .margin({ top: 8 })
          }
        }
        .width('100%')
        .animation({ duration: Motion.FAST, curve: Motion.ease() })
      }

      Row({ space: 8 }) {
        if (!card.definition) {
          Text(this.isDone(card.key) ? (card.occurrence ? '本期已处理' : '已处理')
            : (card.occurrence ? '本次已处理' : '标记已处理'))
            .fontSize(11)
            .fontColor(this.isDone(card.key) ? NT_CY_INK : NT_INK_2)
            .backgroundColor(this.isDone(card.key) ? NT_CY_TINT : NT_GREY_TINT)
            .borderRadius(999)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.toggleDone(card);
            })
        }
        if (card.hiddenLocal) {
          Text('恢复')
            .fontSize(11)
            .fontColor(NT_CY_INK)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .onClick(() => {
              this.restoreCard(card);
            })
        } else if (card.entry !== undefined) {
          Text('隐藏')
            .fontSize(11)
            .fontColor(NT_INK_3)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .onClick(() => {
              this.hideCard(card);
            })
        }
        Blank()
        if (card.hasDetail) {
          Text(this.isExpanded(card.key) ? '收起' : '展开')
            .fontSize(11)
            .fontColor(NT_CY_INK)
            .padding({ left: 8, right: 4, top: 6, bottom: 6 })
            .onClick(() => {
              this.toggleExpand(card.key);
            })
        }
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(13)
    .backgroundColor(this.isDone(card.key) || card.expired ? NT_CARD_SOFT : NT_CARD)
    .borderRadius(14)
    .border({ width: 1, color: card.occurrence ? '#BFD3E3' : NT_LINE })
    .margin({ bottom: 10 })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 8 })
    .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
  }

  @Builder
  emptyState(title: string, text: string) {
    Column({ space: 6 }) {
      Text('📣')
        .fontSize(26)
      Text(title)
        .fontSize(14)
        .fontColor(NT_INK)
      Text(text)
        .fontSize(11)
        .fontColor(NT_INK_3)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 28, bottom: 28 })
    .backgroundColor(NT_CARD)
    .borderRadius(14)
    .border({ width: 1, color: NT_LINE })
  }

  @Builder
  briefCard() {
    Column() {
      Row() {
        Text('待处理简报')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(NT_CY_INK)
        Text(this.stats.pending > 0 ? this.stats.pending + ' 项待处理' : '无待处理')
          .fontSize(9)
          .fontColor(NT_CY_INK)
          .backgroundColor(NT_CARD)
          .borderRadius(999)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .margin({ left: 8 })
        Blank()
        Text(NoticeStatus.pad2(new Date(this.now).getMonth() + 1) + '-' + NoticeStatus.pad2(new Date(this.now).getDate()))
          .fontSize(10)
          .fontColor(NT_INK_2)
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        this.dataCard('pending')
        this.dataCard('urgent')
        this.dataCard('week')
        this.dataCard('longterm')
        this.dataCard('latest')
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.brief.length > 0) {
        Column() {
          ForEach(this.brief, (card: NoticeCard, index: number) => {
            Row() {
              Text(card.title)
                .fontSize(11)
                .fontColor(NT_INK)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(card.statusLabel)
                .fontSize(9)
                .fontColor(card.statusCls === 'urgent' ? NT_ROSE_INK : NT_INK_2)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ top: 7, bottom: 7 })
            .border({ width: { top: index === 0 ? 0 : 1 }, color: NT_LINE })
            .onClick(() => {
              this.filter = 'active';
              this.cardKey = '';
              this.cat = '全部';
            })
          }, (card: NoticeCard, index: number) => 'brief_' + card.key + '_' + this.dataVersion)
        }
        .width('100%')
        .margin({ top: 4 })
      }

      Row() {
        Text(this.syncing ? '同步中…' : '已同步 · ' + new Date(this.now).getHours() + ':' + NoticeStatus.pad2(new Date(this.now).getMinutes()))
          .fontSize(9)
          .fontColor(NT_INK_2)
          .layoutWeight(1)
        Text(this.syncing ? '同步中…' : '刷新')
          .fontSize(10)
          .fontColor(NT_CY_INK)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            if (!this.syncing) {
              this.reload(true);
            }
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(NT_BRIEF)
    .borderRadius(14)
    .border({ width: 1, color: NT_LINE })
  }

  @Builder
  longtermRow(card: NoticeCard) {
    Column() {
      Row() {
        this.miniTag(card.cat, this.catBg(card.catCls), this.catFg(card.catCls))
        this.miniTag('长期安排', NT_BL_TINT, NT_BL_INK)
        Blank()
        Text('进行中')
          .fontSize(10)
          .fontColor(NT_CY_INK)
      }
      .width('100%')
      Text(card.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(NT_INK)
        .width('100%')
        .maxLines(2)
        .margin({ top: 6 })
      Row() {
        Text(card.recurLabel)
          .fontSize(11)
          .fontColor(NT_BL_INK)
          .layoutWeight(1)
        if (card.nextCnText.length > 0) {
          Text(card.nextCnText)
            .fontSize(11)
            .fontColor(NT_INK_2)
        }
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(13)
    .backgroundColor(NT_CARD)
    .borderRadius(14)
    .border({ width: 1, color: NT_LINE })
    .margin({ bottom: 10 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text('‹')
            .fontSize(28)
            .fontColor(NT_INK)
            .width(42)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
          Text('通知')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(NT_INK)
            .layoutWeight(1)
          Text(this.syncing ? '同步中' : '刷新')
            .fontSize(12)
            .fontColor(this.syncing ? NT_INK_3 : NT_CY_INK)
            .padding({ left: 10, right: 12 })
            .height(44)
            .onClick(() => {
              if (!this.syncing) {
                this.reload(true);
              }
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 2, right: 4 })
        .backgroundColor(NT_BG)

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(30).height(30).color(NT_CY)
            Text('正在读取通知…')
              .fontSize(11)
              .fontColor(NT_INK_2)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.briefCard()

              if (this.notice.length > 0) {
                Text(this.notice)
                  .fontSize(10)
                  .fontColor(NT_SD_INK)
                  .width('100%')
                  .margin({ top: 6 })
              }
              if (this.errorMsg.length > 0) {
                Text(this.errorMsg)
                  .fontSize(10)
                  .fontColor(NT_ROSE_INK)
                  .width('100%')
                  .margin({ top: 6 })
              }

              Column() {
                Flex({ wrap: FlexWrap.Wrap }) {
                  this.filterChip('all', '全部')
                  this.filterChip('active', '待处理')
                  this.filterChip('expired', '已截止')
                  this.hiddenChip()
                }
                .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  Text('全部分类')
                    .fontSize(11)
                    .fontColor(this.cat === '全部' ? NT_CY_INK : NT_INK_2)
                    .backgroundColor(this.cat === '全部' ? NT_CY_TINT : NT_CARD)
                    .border({ width: 1, color: this.cat === '全部' ? NT_CY : NT_LINE })
                    .borderRadius(999)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.cat = '全部';
                    })
                  ForEach(this.categories, (cat: string, index: number) => {
                    Text(cat)
                      .fontSize(11)
                      .fontColor(this.cat === cat ? NT_CY_INK : NT_INK_2)
                      .backgroundColor(this.cat === cat ? NT_CY_TINT : NT_CARD)
                      .border({ width: 1, color: this.cat === cat ? NT_CY : NT_LINE })
                      .borderRadius(999)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.cat = cat;
                      })
                  }, (cat: string, index: number) => 'cat_' + cat)
                }
                .width('100%')
              }
              .width('100%')
              .margin({ top: 4 })

              if (this.filter === 'hidden' && this.hiddenIds.length > 0) {
                Row() {
                  Text('已隐藏 ' + this.hiddenIds.length + ' 条（仅自己不可见）')
                    .fontSize(10)
                    .fontColor(NT_INK_3)
                    .layoutWeight(1)
                  Text('全部恢复')
                    .fontSize(11)
                    .fontColor(NT_CY_INK)
                    .onClick(() => {
                      this.restoreAll();
                    })
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 4, bottom: 4 })
              }

              if (this.mode() === 'longterm') {
                Row() {
                  Text(this.longtermList().length + ' 组')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(NT_INK_2)
                  Blank()
                  Text('仅进行中的长期安排')
                    .fontSize(10)
                    .fontColor(NT_INK_3)
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 8, bottom: 6 })
                if (this.longtermList().length === 0) {
                  this.emptyState('暂无长期安排', '长期安排到期后会自动归入已过期')
                } else {
                  ForEach(this.longtermList(), (card: NoticeCard, index: number) => {
                    this.longtermRow(card)
                  }, (card: NoticeCard, index: number) => 'lt_' + card.key + '_' + this.dataVersion)
                }
              } else {
                Row() {
                  Text(this.currentCards().length + ' 组')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(NT_INK_2)
                  if (this.mode() === 'latest') {
                    Text('按发布时间倒序')
                      .fontSize(10)
                      .fontColor(NT_INK_3)
                      .margin({ left: 8 })
                  } else if (this.mode() === 'active') {
                    Text('未过期默认展开')
                      .fontSize(10)
                      .fontColor(NT_INK_3)
                      .margin({ left: 8 })
                  }
                  Blank()
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 8, bottom: 6 })

                if (this.currentCards().length > 0) {
                  ForEach(this.currentCards(), (card: NoticeCard, index: number) => {
                    this.noticeCard(card)
                  }, (card: NoticeCard, index: number) => card.key + '_' + (this.isDone(card.key) ? '1' : '0')
                    + '_' + (this.isExpanded(card.key) ? 'e' : 'c') + '_' + (card.hiddenLocal ? 'h' : 'v')
                    + '_' + this.dataVersion)
                }

                if (this.currentCards().length === 0 && this.filter === 'hidden') {
                  this.emptyState('没有已隐藏通知', '隐藏的通知会出现在这里，可恢复')
                } else if (this.currentCards().length === 0 && this.filter === 'expired') {
                  this.emptyState('没有已过期通知', '换个筛选看看')
                } else if (this.currentCards().length === 0 && this.mode() === 'latest') {
                  this.emptyState('暂无通知', '刷新试试')
                } else if (this.currentCards().length === 0 && this.mode() === 'urgent') {
                  this.emptyState('24 小时内没有待处理', '看看全部或 7 天内')
                } else if (this.currentCards().length === 0 && this.mode() === 'week') {
                  this.emptyState('7 天内没有待处理', '看看全部待处理')
                } else if (this.currentCards().length === 0 && this.filter === 'active') {
                  this.emptyState('没有待处理通知', '看看全部或已过期')
                } else if (this.currentCards().length === 0 && this.filter === 'all') {
                  this.emptyState('暂无通知', '刷新试试')
                }

                if (this.mode() === 'all' && this.infoCards().length > 0) {
                  this.sectionHeader('资料 / 无时间', this.infoCards().length, true, this.showInfo, () => {
                    this.showInfo = !this.showInfo;
                  })
                  if (this.showInfo) {
                    ForEach(this.infoCards(), (card: NoticeCard, index: number) => {
                      this.noticeCard(card)
                    }, (card: NoticeCard, index: number) => 'info_' + card.key + '_' + (this.isDone(card.key) ? '1' : '0')
                      + '_' + (this.isExpanded(card.key) ? 'e' : 'c') + '_' + this.dataVersion)
                  }
                }

                if (this.expiredCards().length > 0) {
                  this.sectionHeader('已过期', this.expiredCards().length, true, this.showExpired, () => {
                    this.showExpired = !this.showExpired;
                  })
                  if (this.showExpired) {
                    ForEach(this.expiredCards(), (card: NoticeCard, index: number) => {
                      this.noticeCard(card)
                    }, (card: NoticeCard, index: number) => 'exp_' + card.key + '_' + (this.isExpanded(card.key) ? 'e' : 'c')
                      + '_' + this.dataVersion)
                  }
                }
              }

              Blank().height(44)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 8 })
          }
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .clip(true)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(NT_BG)

      if (this.rawOpen) {
        Column() {
          Column() {
            Row() {
              Text(this.rawTitle)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(NT_INK)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('关闭')
                .fontSize(11)
                .fontColor(NT_CY_INK)
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .onClick(() => {
                  this.closeRaw();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 10, top: 12, bottom: 8 })
            Divider().color(NT_LINE)
            Scroll() {
              Column() {
                if (this.rawBody.length > 0) {
                  Text(this.rawBody)
                    .fontSize(12)
                    .fontColor(NT_INK)
                    .width('100%')
                }
                ForEach(this.rawBlocks, (block: NoticeItemMeta, index: number) => {
                  Column() {
                    Row({ space: 6 }) {
                      Text(block.label)
                        .fontSize(9)
                        .fontColor(NT_SD_INK)
                        .backgroundColor(NT_SD_TINT)
                        .borderRadius(4)
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      if (block.fromName.length > 0) {
                        Text(block.fromName)
                          .fontSize(9)
                          .fontColor(NT_INK_3)
                      }
                      if (block.timeText.length > 0) {
                        Text(block.timeText)
                          .fontSize(9)
                          .fontColor(NT_INK_3)
                      }
                    }
                    .width('100%')
                    Text(block.text)
                      .fontSize(12)
                      .fontColor(NT_INK)
                      .width('100%')
                      .margin({ top: 4 })
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .border({ width: { bottom: 1 }, color: NT_LINE })
                }, (block: NoticeItemMeta, index: number) => 'raw_' + index)
                Blank().height(20)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 6 })
            }
            .layoutWeight(1)
            .align(Alignment.Top)
          }
          .width('100%')
          .height('68%')
          .backgroundColor(NT_CARD)
          .borderRadius({ topLeft: 18, topRight: 18 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          this.closeRaw();
        })
        .transition(Motion.scrim())
      }

      if (this.previewOpen) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#E6000000')
            .onClick(() => {
              this.closePreview();
            })
          Image(this.previewSrc)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
        .transition(Motion.scrim())
      }
    }
    .width('100%')
    .height('100%')
  }
}
