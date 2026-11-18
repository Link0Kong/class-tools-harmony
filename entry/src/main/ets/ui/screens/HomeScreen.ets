import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { HomeworkRow } from '../../data/homework/HomeworkModels';
import { HomeworkResult } from '../../data/homework/HomeworkRepository';
import { NoticeCards, NoticeCard } from '../../features/notices/NoticeCards';
import { NoticeEntry, NoticesResult } from '../../data/notices/NoticesRepository';
import { PowerPrefs } from '../../data/power/PowerPrefs';
import { PowerRooms, PowerRow } from '../../data/power/PowerModels';
import { PowerRowResult } from '../../data/power/PowerRepository';
import { SessionInfo, SessionState, TodayState, TtPlan } from '../../data/timetable/TimetableModels';
import { TtCalendar } from '../../data/timetable/TtCalendar';
import { TtResult } from '../../data/timetable/TimetableRepository';
import { ToolCatalog, ToolDef } from '../../data/tool/ToolCatalog';
import { HomeDigest, HomeCardItem } from '../../features/home/HomeDigest';
import { HomeNtBadge } from '../../data/home/HomeNtBadge';
import { HidePrefs } from '../../data/home/HidePrefs';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Breakpoints } from '../theme/Breakpoints';
import { AppSymbols } from '../theme/AppSymbols';
import { BrandMark } from '../components/BrandMark';

/**
 * 工作台（对齐小程序 pages/index）：
 * 问候（日期/周次/角色）→ 今日课程 → 宿舍电费 → 作业待交 → 通知待处理 → 常用工具。
 * 首页只读云端缓存（各仓库 TTL），不额外写数据；快捷工具在「全部」页勾选（≤4）。
 */
@Component
export struct HomeScreen {
  @Prop userName: string = '';
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop @Watch('syncQuickOrder') quickIds: string[] = [];
  @State private quickOrder: string[] = [];
  @Prop @Watch('onEpochChanged') epoch: number = 0;
  @Prop editing: boolean = false;
  onToggleEdit: () => void = () => {
  };
  onRemoveQuick: (id: string) => void = () => {
  };
  onAddQuick: () => void = () => {
  };
  onOpenTool: (id: string) => void = () => {
  };
  onHomeReady: () => void = () => {
  };
  onOpenAll: () => void = () => {
  };
  onReorderQuick: (ids: string[]) => void = () => {
  };
  onEditQuick: () => void = () => {
    this.onOpenAll();
  };

  @State private loading: boolean = true;
  @State private plan: TtPlan = new TtPlan();
  @State private ttLoaded: boolean = false;
  @State private hwOpen: number = 0;
  @State private hwItems: HomeCardItem[] = [];
  @State private ntPending: number = 0;
  @State private ntItems: HomeCardItem[] = [];
  @State private ntState: string = 'loading';
  @State private powerHas: boolean = false;
  @State private powerLabel: string = '';
  @State private powerQ: string = '—';
  @State private powerUnit: string = '度';
  @State private powerState: string = 'idle';
  @State private powerUpd: string = '';
  @State private hwIdx: number = 0;
  @State private ntIdx: number = 0;
  @State private hwFade: boolean = false;
  @State private ntFade: boolean = false;
  @State private refreshing: boolean = false;
  @State private ntNew: boolean = false;
  @State private shimmer: boolean = false;
  @State private floatY: number = 0;
  @State private layoutWidth: number = 0;
  private rotateTimer: number = -1;
  private shimmerTimer: number = -1;
  private floatTimer: number = -1;
  private fadeTimer: number = -1;
  private paintTimer: number = -1;
  private refreshTimer: number = -1;
  private refreshRunning: boolean = false;
  private refreshSeq: number = 0;
  private startedAt: number = 0;
  private loadSeq: number = 0;
  private readyFired: boolean = false;
  private lastLoadAt: number = 0;

  onEpochChanged(): void {
    // 切回工作台：2 分钟内只复用内存缓存，避免每次切 tab 都重复请求
    if (Date.now() - this.lastLoadAt < 2 * 60 * 1000) {
      return;
    }
    this.load(false);
  }

  aboutToAppear(): void {
    this.syncQuickOrder();
    this.startedAt = Date.now();
    this.applyLocal();
    this.startSkeleton();
    this.load(false);
    // 兜底：首帧动画最多 1.5s，任何异常/弱网都不能让骨架屏常驻
    setTimeout(() => {
      if (this.loading) {
        this.finishLoading();
      }
    }, 1500);
    this.rotateTimer = setInterval(() => {
      this.rotateTick();
    }, 5000);
    this.floatTimer = setInterval(() => {
      this.getUIContext().animateTo({ duration: 1200, curve: Motion.ease() }, () => {
        this.floatY = this.floatY === 0 ? -2 : 0;
      });
    }, 2400);
  }

  aboutToDisappear(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
    if (this.fadeTimer >= 0) {
      clearTimeout(this.fadeTimer);
      this.fadeTimer = -1;
    }
    if (this.shimmerTimer >= 0) {
      clearInterval(this.shimmerTimer);
      this.shimmerTimer = -1;
    }
    if (this.floatTimer >= 0) {
      clearInterval(this.floatTimer);
      this.floatTimer = -1;
    }
    if (this.paintTimer >= 0) {
      clearTimeout(this.paintTimer);
      this.paintTimer = -1;
    }
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  /**
   * 下拉刷新：每次 onRefreshing 都必须独立安排一次“收起”，
   * 不能因为上一次刷新还没结束就提前 return（否则第二次下拉会永远停在刷新态）。
   * refreshing 只由系统置 true，这里只负责置 false。
   */
  private refreshNow(): void {
    const token: number = this.refreshSeq + 1;
    this.refreshSeq = token;
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      if (token === this.refreshSeq) {
        this.refreshing = false;
        this.refreshTimer = -1;
      }
    }, 1200);
    if (this.refreshRunning) {
      return;
    }
    this.refreshRunning = true;
    this.runRefresh(token);
  }

  private async runRefresh(token: number): Promise<void> {
    try {
      await this.load(true);
    } catch (e) {
      // 加载异常也不能让刷新动画卡住
    } finally {
      this.refreshRunning = false;
      if (token === this.refreshSeq) {
        if (this.refreshTimer >= 0) {
          clearTimeout(this.refreshTimer);
          this.refreshTimer = -1;
        }
        this.refreshing = false;
      }
    }
  }

  private startSkeleton(): void {
    if (!this.loading || this.shimmerTimer >= 0) {
      return;
    }
    this.shimmerTimer = setInterval(() => {
      this.getUIContext().animateTo({ duration: 700, curve: Motion.ease() }, () => {
        this.shimmer = !this.shimmer;
      });
    }, 700);
  }

  private finishLoading(): void {
    this.loading = false;
    this.shimmer = false;
    if (this.shimmerTimer >= 0) {
      clearInterval(this.shimmerTimer);
      this.shimmerTimer = -1;
    }
    if (this.paintTimer >= 0) {
      clearTimeout(this.paintTimer);
      this.paintTimer = -1;
    }
    if (!this.readyFired) {
      this.readyFired = true;
      setTimeout(() => {
        this.onHomeReady();
      }, 16);
    }
  }

  syncQuickOrder(): void {
    this.quickOrder = this.quickIds.slice();
  }

  private quick(): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < this.quickOrder.length && out.length < 4; i++) {
      const tool: ToolDef | undefined = ToolCatalog.byId(this.quickOrder[i]);
      if (tool !== undefined && !ToolCatalog.isHidden(tool.id)) {
        out.push(tool);
      }
    }
    return out;
  }

  /** 首页常用工具拖拽落位：只交换顺序，交由外层持久化。 */
  private moveQuick(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.quickOrder.length || to >= this.quickOrder.length) {
      return;
    }
    const next: string[] = this.quickOrder.slice();
    const moved: string[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    this.quickOrder = next;
    this.onReorderQuick(next);
  }

  /** 首帧直接用本机缓存渲染（marks / 课表 / 作业 / 通知），不等网络。 */
  private applyLocal(): void {
    const snapshot = Services.marks.marks();
    const tt = Services.timetable.local();
    if (tt !== undefined) {
      this.plan = TtCalendar.plan(tt, Date.now());
      this.ttLoaded = true;
    }
    const hidden = HidePrefs.read(Services.userdata.currentSections());
    const hw = Services.homework.local();
    const open: HomeworkRow[] = HomeDigest.hwOpen(hw,
      (id: string) => snapshot.isDone(MarkKind.HW, id),
      (id: string) => hidden.hwHide.has(id));
    this.hwOpen = open.length;
    this.hwItems = HomeDigest.hwItems(open);
    const entries: NoticeEntry[] = Services.notices.local();
    if (entries.length > 0) {
      this.applyNotices(entries, true);
    }
  }

  private applyNotices(entries: NoticeEntry[], ok: boolean): void {
    const now: number = Date.now();
    const snapshot = Services.marks.marks();
    const hidden = HidePrefs.read(Services.userdata.currentSections());
    const allCards: NoticeCard[] = NoticeCards.build(entries, now);
    const cards: NoticeCard[] = [];
    for (let i = 0; i < allCards.length; i++) {
      const card: NoticeCard = allCards[i];
      const entryId: string = card.entry !== undefined ? card.entry.row.id : '';
      const groupId: string = card.key.indexOf('@occ:') > 0 ? card.key.substring(0, card.key.indexOf('@occ:')) : card.key;
      if (hidden.ntHide.has(entryId) || hidden.ntHide.has(groupId)) {
        continue;
      }
      cards.push(card);
    }
    this.ntPending = HomeDigest.ntPending(cards, (key: string) => snapshot.isDone(MarkKind.NT_DONE, key));
    this.ntItems = HomeDigest.ntItems(cards, (key: string) => snapshot.isDone(MarkKind.NT_DONE, key));
    this.ntState = ok ? 'ok' : (Services.currentSid.length === 0 ? 'off' : 'error');
  }

  private async load(force: boolean): Promise<void> {
    const seq: number = this.loadSeq + 1;
    this.loadSeq = seq;
    this.lastLoadAt = Date.now();
    const now: number = Date.now();
    this.applyLocal();
    this.startSkeleton();
    if (this.loading) {
      if (this.paintTimer >= 0) {
        clearTimeout(this.paintTimer);
        this.paintTimer = -1;
      }
      // 首帧兜底：最多 600ms 骨架，网络结果随后局部填充，避免长时间闪烁
      this.paintTimer = setTimeout(() => {
        if (seq === this.loadSeq) {
          this.finishLoading();
        }
      }, 600);
    }
    // 各模块并行请求，互不阻塞（原来串行最坏要等 5 个 10s 超时）
    const marksPromise = Services.marks.refresh(false);
    const ttPromise = Services.timetable.load(force);
    const hwPromise = Services.homework.load(force);
    const ntPromise = Services.notices.load(force);
    const prefs = PowerPrefs.read(Services.userdata.currentSections());
    let powerPromise: Promise<PowerRowResult> | undefined = undefined;
    if (prefs.sel.length > 0) {
      powerPromise = Services.power.loadRow(prefs.sel, false);
    }

    try {
      await marksPromise;
    } catch (e) {
      // 单项失败不影响其余模块
    }
    const snapshot = Services.marks.marks();
    try {
      const tt: TtResult = await ttPromise;
      if (seq === this.loadSeq) {
        this.plan = TtCalendar.plan(tt.snapshot, now);
        this.ttLoaded = true;
      }
    } catch (e) {
      // 忽略
    }
    try {
      const hw: HomeworkResult = await hwPromise;
      const hidden = HidePrefs.read(Services.userdata.currentSections());
      const open: HomeworkRow[] = HomeDigest.hwOpen(hw.rows,
        (id: string) => snapshot.isDone(MarkKind.HW, id),
        (id: string) => hidden.hwHide.has(id));
      if (seq === this.loadSeq) {
        this.hwOpen = open.length;
        this.hwItems = HomeDigest.hwItems(open);
      }
    } catch (e) {
      // 忽略
    }
    try {
      const nt: NoticesResult = await ntPromise;
      if (seq === this.loadSeq) {
        this.applyNotices(nt.entries, nt.ok);
        HomeNtBadge.update(Services.currentSid, Services.notices.currentSignature()).then((isNew: boolean) => {
          if (seq === this.loadSeq) {
            this.ntNew = isNew;
          }
        });
      }
    } catch (e) {
      if (seq === this.loadSeq) {
        this.ntState = 'error';
      }
    }
    if (powerPromise !== undefined) {
      try {
        const rowResult: PowerRowResult = await powerPromise;
        const row: PowerRow | undefined = rowResult.row;
        if (seq === this.loadSeq) {
          this.powerHas = true;
          this.powerLabel = PowerRooms.labelOf(prefs.sel);
          this.powerState = 'idle';
          if (row !== undefined) {
            this.powerQ = HomeDigest.powerQText(row.q, row.hasValue);
            this.powerUnit = row.unit.length > 0 ? row.unit : '度';
            this.powerState = HomeDigest.powerState(row.q, row.hasValue, prefs.low);
            this.powerUpd = HomeDigest.updText(row.updatedAt);
          }
        }
      } catch (e) {
        // 忽略
      }
    }
    if (seq === this.loadSeq) {
      this.finishLoading();
    }
  }

  private rotateTick(): void {
    const hwCount: number = this.hwItems.length;
    const ntCount: number = this.ntItems.length;
    if (hwCount <= 1 && ntCount <= 1) {
      return;
    }
    this.getUIContext().animateTo({ duration: 260, curve: Motion.ease() }, () => {
      if (hwCount > 1) {
        this.hwFade = true;
      }
      if (ntCount > 1) {
        this.ntFade = true;
      }
    });
    this.fadeTimer = setTimeout(() => {
      if (hwCount > 1) {
        this.hwIdx = HomeDigest.rotate(hwCount, this.hwIdx);
      }
      if (ntCount > 1) {
        this.ntIdx = HomeDigest.rotate(ntCount, this.ntIdx);
      }
      this.getUIContext().animateTo({ duration: 320, curve: Motion.ease() }, () => {
        this.hwFade = false;
        this.ntFade = false;
      });
    }, 260);
  }

  private hwTitle(): string {
    return this.hwItems.length > 0 ? this.hwItems[Math.min(this.hwIdx, this.hwItems.length - 1)].title : '';
  }

  private hwSub(): string {
    return this.hwItems.length > 0 ? this.hwItems[Math.min(this.hwIdx, this.hwItems.length - 1)].sub : '';
  }

  private ntTitle(): string {
    return this.ntItems.length > 0 ? this.ntItems[Math.min(this.ntIdx, this.ntItems.length - 1)].title : '';
  }

  private ntSub(): string {
    return this.ntItems.length > 0 ? this.ntItems[Math.min(this.ntIdx, this.ntItems.length - 1)].sub : '';
  }

  private greeting(): string {
    return HomeDigest.hello(new Date().getHours());
  }

  private subLine(): string {
    const parts: string[] = [];
    parts.push(HomeDigest.dateText(new Date()));
    const week: string = HomeDigest.weekText(this.plan.week);
    if (week.length > 0) {
      parts.push(week);
    }
    if (this.roleLabel.length > 0) {
      parts.push(this.roleLabel);
    }
    return parts.join(' · ');
  }

  private sessionPill(state: string): string {
    return state === 'ongoing' ? '上课中' : '';
  }

  private powerPillColor(): string {
    if (this.powerState === 'low') {
      return Tokens.DANGER;
    }
    if (this.powerState === 'warn') {
      return Tokens.WARM_SAND;
    }
    if (this.powerState === 'ok') {
      return Tokens.MIST_TEAL;
    }
    return Tokens.TEXT_TERTIARY;
  }

  private nextToday(): SessionInfo | undefined {
    for (let i = 0; i < this.plan.today.length; i++) {
      if (this.plan.today[i].state !== SessionState.DONE) {
        return this.plan.today[i];
      }
    }
    return undefined;
  }

  /** Hero 里的一行课程摘要（不写长段落）。 */
  private todaySummary(): string {
    if (!this.plan.hasData) {
      return '课表未同步 · 打开课表拉取本周课程';
    }
    const next: SessionInfo | undefined = this.nextToday();
    let text: string = this.plan.today.length > 0
      ? '今日 ' + this.plan.today.length + ' 节' : '今天没课';
    if (next !== undefined) {
      text += ' · 下一节 ' + next.startText + ' ' + next.name;
    } else if (this.plan.next !== undefined) {
      text += ' · 下次 ' + this.plan.next.dayText + ' ' + this.plan.next.name;
    }
    return text;
  }

  /**
   * 工作台「今日」hero：莫奈浅色纸面（睡莲青 / 雾蓝 / 暖沙三段色条），
   * 深色只用于文字，保持与通知页、手表端一致的莫奈色系。
   * 内容：今日课程摘要 / 周次 / 问候 / 日期与角色。
   */
  @Builder
  heroCard() {
    Column() {
      Row() {
        Row()
          .layoutWeight(1)
          .height(3)
          .backgroundColor(Tokens.MIST_TEAL)
        Row()
          .layoutWeight(1)
          .height(3)
          .backgroundColor(Tokens.SLATE_BLUE)
        Row()
          .layoutWeight(1)
          .height(3)
          .backgroundColor(Tokens.WARM_SAND)
      }
      .width('100%')
      .borderRadius(2)
      .margin({ bottom: 12 })

      Row() {
        Text('今日')
          .fontSize(Tokens.F_CAPTION)
          .fontColor('#3F6F66')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#FFFCF6')
          .borderRadius(Tokens.RADIUS_PILL)
        Blank()
        Text(HomeDigest.weekText(this.plan.week).length > 0
          ? HomeDigest.weekText(this.plan.week) : '课表未同步')
          .fontSize(Tokens.F_CAPTION)
          .fontColor('#5C6860')
      }
      .width('100%')

      Text(this.greeting() + '，' + this.userName)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#303A35')
        .width('100%')
        .margin({ top: 12 })

      Text(this.subLine())
        .fontSize(Tokens.F_CAPTION)
        .fontColor('#5C6860')
        .width('100%')
        .margin({ top: 6 })

      Row() {
        Text(this.todaySummary())
          .fontSize(Tokens.F_LABEL)
          .fontColor('#303A35')
          .layoutWeight(1)
          .maxLines(2)
        Row({ space: 2 }) {
          Text('课表')
            .fontSize(Tokens.F_CAPTION)
            .fontColor('#4E6D8C')
          SymbolGlyph(AppSymbols.ARROW_RIGHT)
            .fontSize(12)
            .fontColor(['#4E6D8C'])
        }
        .padding({ left: Tokens.GAP_SM })
        .onClick(() => {
          this.onOpenTool('tt');
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: Tokens.GAP })
      .margin({ top: Tokens.GAP })
      .border({ width: { top: 0.5 }, color: '#D8E4DE' })
    }
    .width('100%')
    .padding(Tokens.SPACE_16)
    .margin({ top: Tokens.SPACE_4, bottom: Tokens.GAP })
    .backgroundColor('#D9F1F6F2')
    .border({ width: 0.5, color: '#E6DCE7E2' })
    .borderRadius(24)
    .alignItems(HorizontalAlign.Start)
    .shadow({ radius: 16, color: '#0F4E9082', offsetX: 0, offsetY: 6 })
    .transition(Motion.listItem())
  }

  @Builder
  cardHeader(eyebrow: string, action: string, onAction: () => void) {
    Row() {
      Text(eyebrow)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .layoutWeight(1)
      if (action.length > 0) {
        Row({ space: 2 }) {
          Text(action)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
          SymbolGlyph(AppSymbols.ARROW_RIGHT)
            .fontSize(12)
            .fontColor([Tokens.SLATE_BLUE])
        }
        .padding({ left: 8, top: 4, bottom: 4 })
        .onClick(() => {
          onAction();
        })
      }
    }
    .width('100%')
  }

  private cardItems(kind: string): HomeCardItem[] {
    return kind === 'hw' ? this.hwItems : this.ntItems;
  }

  private cardIdx(kind: string): number {
    return kind === 'hw' ? this.hwIdx : this.ntIdx;
  }

  private cardFade(kind: string): boolean {
    return kind === 'hw' ? this.hwFade : this.ntFade;
  }

  private cardCount(kind: string): number {
    return kind === 'hw' ? this.hwOpen : this.ntPending;
  }

  @Builder
  taskCard(kind: string, symbol: Resource, label: string, emptyText: string, accent: string, onTap: () => void) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor([accent])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      }
      .width(40)
      .height(40)
      .backgroundColor(Tokens.tint(accent, 0.12))
      .border({ width: 1, color: Tokens.tint(accent, 0.20) })
      .borderRadius(12)
      Column() {
        Row() {
          Text(label)
            .fontSize(Tokens.F_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
          if (this.cardCount(kind) > 0) {
            Text('' + this.cardCount(kind))
              .fontSize(Tokens.F_CAPTION)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(accent)
              .borderRadius(8)
              .margin({ left: 8 })
          }
          if (kind === 'nt' && this.ntNew) {
            Text('新通知')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(Tokens.tint(Tokens.SLATE_BLUE, 0.14))
              .borderRadius(6)
              .margin({ left: 6 })
          }
        }
        if (this.cardItems(kind).length > 0) {
          Text(this.cardItems(kind)[Math.min(this.cardIdx(kind), this.cardItems(kind).length - 1)].title)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .opacity(this.cardFade(kind) ? 0 : 1)
            .translate({ y: this.cardFade(kind) ? -6 : 0 })
            .margin({ top: 4 })
          Text(this.cardItems(kind)[Math.min(this.cardIdx(kind), this.cardItems(kind).length - 1)].sub)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .maxLines(1)
            .opacity(this.cardFade(kind) ? 0 : 1)
            .translate({ y: this.cardFade(kind) ? -6 : 0 })
            .margin({ top: 2 })
        } else {
          Text(emptyText)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      SymbolGlyph(AppSymbols.ARROW_RIGHT)
        .fontSize(16)
        .fontColor([Tokens.TEXT_TERTIARY])
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .stateStyles({
      pressed: {
        .scale({ x: 0.99, y: 0.99 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .onClick(() => {
      onTap();
    })
  }
  @Builder
  quickGrid() {
    List({ space: 0 }) {
      ForEach(this.quick(), (tool: ToolDef) => {
        ListItem() {
          Column() {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph(tool.symbol)
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor([tool.accent])
                .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
            }
            .width(46)
            .height(46)
            .backgroundColor(Tokens.tint(tool.accent, 0.12))
            .borderRadius(14)
            Text(tool.name)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
              .margin({ top: 6 })
              .maxLines(1)
          }
          .width('100%')
          .height(76)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onOpenTool(tool.id);
          })
        }
        .width('25%')
      }, (tool: ToolDef) => tool.id)
        .onMove((from: number, to: number) => {
          this.moveQuick(from, to);
        })
    }
    .listDirection(Axis.Horizontal)
    .width('100%')
    .height(76)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .accessibilityText('常用工具，长按拖动可调整顺序')
  }

  @Builder
  skeletonPage() {
    Column() {
      Column() {
        Row().width('46%').height(22).backgroundColor('#E6ECEE').borderRadius(6)
        Row().width('34%').height(12).backgroundColor('#EDF1F2').borderRadius(4).margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 32 })
      Column() {
        Row().width('22%').height(10).backgroundColor('#EDF1F2').borderRadius(4)
        Row().width('100%').height(54).backgroundColor('#E9EEEF').borderRadius(10).margin({ top: 12 })
      }
      .width('100%')
      .padding(Tokens.CARD_PADDING)
      .margin({ top: 20 })
      .backgroundColor(Tokens.CARD)
      .border({ width: 0.5, color: Tokens.CARD_EDGE })
      .borderRadius(Tokens.RADIUS_CARD)
      ForEach([0, 1, 2], (i: number) => {
        Row() {
          Row().width(40).height(40).backgroundColor('#E6ECEE').borderRadius(12)
          Column() {
            Row().width('40%').height(12).backgroundColor('#E9EEEF').borderRadius(4)
            Row().width('65%').height(10).backgroundColor('#EDF1F2').borderRadius(4).margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
        }
        .width('100%')
        .padding(Tokens.CARD_PADDING)
        .margin({ top: 12 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
      }, (i: number) => 'sk_' + i)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Breakpoints.pagePadding(this.layoutWidth),
      right: Breakpoints.pagePadding(this.layoutWidth)
    })
    .backgroundColor(Color.Transparent)
    .opacity(this.shimmer ? 0.55 : 1)
  }

  private isWide(): boolean {
    return Breakpoints.useTwoPane(this.layoutWidth);
  }

  private bottomSpace(): number {
    return Breakpoints.contentBottomSpace(this.layoutWidth);
  }

  /** 宽屏二分栏左列：今天课程。 */
  @Builder
  todayCard() {
    Column() {
      this.cardHeader('今天', '课表', () => {
        this.onOpenTool('tt');
      })
      if (this.plan.hasData && this.plan.today.length > 0) {
        ForEach(this.plan.today, (session: SessionInfo) => {
          Row() {
            Text(session.startText)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width(56)
            Column() {
              Text(session.name)
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
                .maxLines(1)
              Text(session.span + (session.room.length > 0 ? ' · ' + session.room : ''))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 2 })
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            if (session.state === SessionState.ONGOING) {
              Text('上课中')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(Tokens.TINT_TEAL)
                .borderRadius(Tokens.RADIUS_PILL)
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (session: SessionInfo) => 'w_t_' + session.startAt + session.name)
        if (this.plan.todayState === TodayState.DONE) {
          Text('今日课程已结束' + (this.plan.next !== undefined
            ? ' · 下次 ' + this.plan.next.dayText + ' ' + this.plan.next.name : ''))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 2 })
        }
      } else if (this.plan.hasData) {
        Text('今天没课')
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 8 })
        Text(this.plan.next !== undefined
          ? '下次 · ' + this.plan.next.dayText + ' ' + this.plan.next.name
          : '近期暂无课程')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      } else {
        Text('课表未同步')
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 8 })
        Text('打开课表即可拉取本周课程')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .shadow({ radius: 18, color: '#0D1C2629', offsetX: 0, offsetY: 6 })
    .transition(Motion.listItem())
  }

  /** 宽屏二分栏右列：宿舍电费。 */
  @Builder
  powerCard() {
    Column() {
      this.cardHeader('宿舍电费', this.powerHas ? '查看' : '', () => {
      })
      if (this.powerHas) {
        Row() {
          Column() {
            Text(this.powerLabel)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
            Text(this.powerUpd.length > 0 ? '更新 ' + this.powerUpd : '点开查看趋势与充值')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Row() {
            Text(this.powerQ)
              .fontSize(Tokens.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
            Text(this.powerUnit)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .margin({ left: 2, bottom: 4 })
          }
          .alignItems(VerticalAlign.Bottom)
          Text(HomeDigest.powerStateText(this.powerState))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.powerPillColor())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(Tokens.tint(this.powerPillColor(), 0.12))
            .borderRadius(Tokens.RADIUS_PILL)
            .margin({ left: Tokens.GAP_SM })
        }
        .width('100%')
        .margin({ top: 8 })
      } else {
        Column() {
          Text('关注宿舍后显示剩余电量')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
          Text('去选择关注宿舍 ›')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .stateStyles({
      pressed: {
        .scale({ x: 0.99, y: 0.99 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .onClick(() => {
      this.onOpenTool('power');
    })
    .transition(Motion.listItem())
  }

  /** 宽屏二分栏右列：作业 / 通知待处理。 */
  @Builder
  tasksSection() {
    Column() {
      Column() {
        this.taskCard('hw', AppSymbols.HOMEWORK, '作业待交', '作业都完成了', Tokens.WARM_SAND, () => {
          this.onOpenTool('hw');
        })
      }
      .width('100%')
      .margin({ top: 16 })
      .transition(Motion.listItem())

      Column() {
        if (this.ntState === 'ok') {
          this.taskCard('nt', AppSymbols.BELL, '通知待处理', '暂无待处理通知', '#B06A55', () => {
            this.onOpenTool('nt');
          })
        } else {
          this.taskCard('nt', AppSymbols.BELL, '通知待处理',
            this.ntState === 'off' ? '通知需联网同步'
              : (this.ntState === 'error' ? '通知同步失败，点开重试' : '通知同步中…'), '#B06A55', () => {
              this.onOpenTool('nt');
            })
        }
      }
      .width('100%')
      .margin({ top: 12 })
      .transition(Motion.listItem())
    }
    .width('100%')
  }

  /** 宽屏二分栏左列：常用工具。 */
  @Builder
  quickSection() {
    Column() {
      Row() {
        Text('常用工具')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
          .layoutWeight(1)
        Text('全部 ›')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.onOpenAll();
          })
      }
      .width('100%')
      .margin({ top: Tokens.GAP_XL, bottom: Tokens.GAP_SM })

      if (this.quick().length > 0) {
        Column() {
          this.quickGrid()
        }
        .width('100%')
        .padding(Tokens.CARD_PADDING)
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
        .transition(Motion.listItem())
      } else {
        Row() {
          Column() {
            Text('尚未勾选常用工具')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
            Text('去工具页勾选想放在首页的工具（最多 4 个）')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('去勾选 ›')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
        }
        .width('100%')
        .padding(Tokens.CARD_PADDING)
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
        .onClick(() => {
          this.onEditQuick();
        })
      }
    }
    .width('100%')
  }

  build() {
    Stack() {
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll() {
      Row() {
      Column() {
        this.heroCard()

        if (this.isWide()) {
          Row({ space: 16 }) {
            Column() {
              this.todayCard()
              this.quickSection()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.powerCard()
              this.tasksSection()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
        // —— 今日课程 ——
        Column() {
          this.cardHeader('今天', '课表', () => {
            this.onOpenTool('tt');
          })
          if (this.plan.hasData && this.plan.today.length > 0) {
            ForEach(this.plan.today, (session: SessionInfo) => {
              Row() {
                Text(session.startText)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .width(56)
                Column() {
                  Text(session.name)
                    .fontSize(Tokens.F_BODY)
                    .fontColor(Tokens.TEXT_PRIMARY)
                    .maxLines(1)
                  Text(session.span + (session.room.length > 0 ? ' · ' + session.room : ''))
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.TEXT_TERTIARY)
                    .margin({ top: 2 })
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (session.state === SessionState.ONGOING) {
                  Text('上课中')
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.MIST_TEAL)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor(Tokens.TINT_TEAL)
                    .borderRadius(Tokens.RADIUS_PILL)
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
            }, (session: SessionInfo) => 't_' + session.startAt + session.name)
            if (this.plan.todayState === TodayState.DONE) {
              Text('今日课程已结束' + (this.plan.next !== undefined
                ? ' · 下次 ' + this.plan.next.dayText + ' ' + this.plan.next.name : ''))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .width('100%')
                .margin({ top: 2 })
            }
          } else if (this.plan.hasData) {
            Text('今天没课')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 8 })
            Text(this.plan.next !== undefined
              ? '下次 · ' + this.plan.next.dayText + ' ' + this.plan.next.name
              : '近期暂无课程')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 4 })
          } else {
            Text('课表未同步')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 8 })
            Row() {
              Text('打开课表即可拉取本周课程')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .layoutWeight(1)
              Text('打开课表')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .onClick(() => {
                  this.onOpenTool('tt');
                })
            }
            .width('100%')
            .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(Tokens.CARD_PADDING)
        .margin({ top: 20 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
        .shadow({ radius: 18, color: '#0D1C2629', offsetX: 0, offsetY: 6 })
        .transition(Motion.listItem())

        // —— 宿舍电费 ——
        Column() {
          this.cardHeader('宿舍电费', this.powerHas ? '查看' : '', () => {
          })
          if (this.powerHas) {
            Row() {
              Column() {
                Text(this.powerLabel)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_SECONDARY)
                Text(this.powerUpd.length > 0 ? '更新 ' + this.powerUpd : '点开查看趋势与充值')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Row() {
                Text(this.powerQ)
                  .fontSize(Tokens.F_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Tokens.TEXT_PRIMARY)
                Text(this.powerUnit)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .margin({ left: 2, bottom: 4 })
              }
              .alignItems(VerticalAlign.Bottom)
              Text(HomeDigest.powerStateText(this.powerState))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(this.powerPillColor())
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(Tokens.tint(this.powerPillColor(), 0.12))
                .borderRadius(Tokens.RADIUS_PILL)
                .margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 8 })
          } else {
            Row() {
              Column() {
                Text('关注宿舍后显示剩余电量')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_SECONDARY)
                Text('去选择关注宿舍 ›')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.SLATE_BLUE)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .margin({ top: 8 })
          }
        }
        .width('100%')
        .padding(Tokens.CARD_PADDING)
        .margin({ top: 12 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
        .stateStyles({
          pressed: {
            .scale({ x: 0.99, y: 0.99 })
          }
        })
        .animation({ duration: Motion.FAST, curve: Motion.ease() })
        .onClick(() => {
          this.onOpenTool('power');
        })
        .transition(Motion.listItem())

        // —— 作业待交 ——
        Column() {
          this.taskCard('hw', AppSymbols.HOMEWORK, '作业待交', '作业都完成了', Tokens.WARM_SAND, () => {
              this.onOpenTool('hw');
            })
        }
        .width('100%')
        .margin({ top: 12 })
        .transition(Motion.listItem())

        // —— 通知待处理 ——
        Column() {
          if (this.ntState === 'ok') {
            this.taskCard('nt', AppSymbols.BELL, '通知待处理', '暂无待处理通知', '#B06A55', () => {
                this.onOpenTool('nt');
              })
          } else {
            this.taskCard('nt', AppSymbols.BELL, '通知待处理',
              this.ntState === 'off' ? '通知需联网同步'
                : (this.ntState === 'error' ? '通知同步失败，点开重试' : '通知同步中…'), '#B06A55', () => {
                this.onOpenTool('nt');
              })
          }
        }
        .width('100%')
        .margin({ top: 12 })
        .transition(Motion.listItem())

        // —— 常用工具 ——
        Row() {
          Text('常用工具')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.TEXT_SECONDARY)
            .layoutWeight(1)
          Row({ space: 2 }) {
            Text('全部')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.SLATE_BLUE)
            SymbolGlyph(AppSymbols.ARROW_RIGHT)
              .fontSize(12)
              .fontColor([Tokens.SLATE_BLUE])
          }
          .onClick(() => {
            this.onOpenAll();
          })
        }
        .width('100%')
        .margin({ top: Tokens.GAP_XL, bottom: Tokens.GAP_SM })

        if (this.quick().length > 0) {
          Column() {
            this.quickGrid()
          }
          .width('100%')
          .padding(Tokens.CARD_PADDING)
          .backgroundColor(Tokens.CARD)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .borderRadius(Tokens.RADIUS_CARD)
          .transition(Motion.listItem())
        } else {
          Row() {
            Column() {
              Text('尚未勾选常用工具')
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
              Text('去工具页勾选想放在首页的工具（最多 4 个）')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('去勾选 ›')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
          }
          .width('100%')
          .padding(Tokens.CARD_PADDING)
          .backgroundColor(Tokens.CARD)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .borderRadius(Tokens.RADIUS_CARD)
          .onClick(() => {
            this.onEditQuick();
          })
        }

        }
        Blank().height(this.bottomSpace())
      }
      .width('100%')
      .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.layoutWidth) })
      .padding({
      left: Breakpoints.pagePadding(this.layoutWidth),
      right: Breakpoints.pagePadding(this.layoutWidth),
      top: Tokens.SPACE_8
    })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Top)
    }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onRefreshing(() => {
      this.refreshNow();
    })
      if (this.loading) {
        this.skeletonPage()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
