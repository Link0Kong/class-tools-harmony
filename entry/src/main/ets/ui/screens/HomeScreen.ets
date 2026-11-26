import { showFeedback } from '../components/AppFeedback';
import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { TaskRepository } from '../../data/tasks/TaskRepository';
import { HomeworkBrief, PersonalTask } from '../../data/tasks/TaskModels';
import { AppGlobal } from '../../app/AppGlobal';
import { ToolLaunch } from '../../app/ToolLaunch';
import { DeskForms } from '../../forms/DeskForms';
import { NotifyCenter } from '../../data/notify/NotifyCenter';
import { HomeworkDueCalculator, HomeworkItem, HomeworkRow } from '../../data/homework/HomeworkModels';
import { HomeworkResult } from '../../data/homework/HomeworkRepository';
import { NoticeCards, NoticeCard } from '../../features/notices/NoticeCards';
import { NoticeEntry, NoticesResult } from '../../data/notices/NoticesRepository';
import { PowerPrefs } from '../../data/power/PowerPrefs';
import { PowerRooms, PowerRow } from '../../data/power/PowerModels';
import { PowerRowResult } from '../../data/power/PowerRepository';
import { SessionInfo, SessionState, TodayState, TtPlan, TtSnapshot } from '../../data/timetable/TimetableModels';
import { TtCalendar } from '../../data/timetable/TtCalendar';
import { TtResult } from '../../data/timetable/TimetableRepository';
import { ToolCatalog, ToolDef } from '../../data/tool/ToolCatalog';
import { HomeDigest, HomeCardItem } from '../../features/home/HomeDigest';
import { HomeToolDigest, ToolCardDigest, ToolDigestLine } from '../../features/home/HomeToolDigest';
import { WaterCodec } from '../../features/water/WaterCodec';
import { JsonBlob } from '../../data/sync/JsonBlob';
import { FitRecsResult } from '../../data/fitrecs/FitRecsRepository';
import { HomeNtBadge } from '../../data/home/HomeNtBadge';
import { HidePrefs } from '../../data/home/HidePrefs';
import { HomeCardConfig, HomeCardDef, HomeCards } from '../../data/home/HomeCards';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Breakpoints } from '../theme/Breakpoints';
import { AppSymbols } from '../theme/AppSymbols';
import { HomeCardShell } from '../components/HomeCardShell';
import { HomeCardConfigSheet } from './HomeCardConfigSheet';

/** 统一卡片高度，保证一行两张时上下对齐。 */
const HOME_CARD_H: number = 152;

/**
 * 工作台（对齐小程序 pages/index）：
 * 问候 hero → 可自定义卡片（课程 / 电费 / 作业 / 通知 / 常用工具 / 各工具入口 / 时钟 / 天气）。
 *
 * 卡片顺序、类型、数量与宽度由右上角配置按钮自定义：
 * - 一行最多两张，span=1 半宽、span=2 整行，宽度变化走弹性动画；
 * - 布局按账号保存在本机 preferences，切换账号互不影响；
 * - 首页只读缓存数据，不额外写业务数据。
 */
@Component
export struct HomeScreen {
  @Prop userName: string = '';
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop @Watch('syncQuickOrder') quickIds: string[] = [];
  @State private quickOrder: string[] = [];
  @Prop @Watch('onEpochChanged') epoch: number = 0;
  /** 编辑态：卡片右上角显示移除按钮，点按不再打开工具。 */
  @Prop editing: boolean = false;
  /** 标题栏「加号」按钮每次点击 +1，用于打开添加卡片面板。 */
  @Prop @Watch('onAddEpoch') addEpoch: number = 0;
  onOpenTool: (id: string) => void = () => {
  };
  onHomeReady: () => void = () => {
  };
  onOpenAll: () => void = () => {
  };
  onReorderQuick: (ids: string[]) => void = () => {
  };

  @State private loading: boolean = true;
  private ttSnapshot: TtSnapshot | undefined = undefined;
  private planMinute: number = -1;
  @State private plan: TtPlan = new TtPlan();
  private tasks: PersonalTask[] = [];
  private completing = new Set<string>();
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
  @State private layoutWidth: number = 0;

  @State private cards: HomeCardConfig[] = HomeCards.defaults();
  @State private sheetOpen: boolean = false;
  @State private resizingId: string = '';
  @State private resizeDx: number = 0;
  @State private dragId: string = '';
  @State private dragDx: number = 0;
  @State private dragDy: number = 0;

  /** 缩放开始时的卡片宽度（绝对宽度跟手，避免累计误差）。 */
  private resizeStartWidth: number = 0;
  private resizeOriginIndex: number = -1;
  private resizeOriginSpan: number = HomeCards.HALF;
  private resizeSwapped: boolean = false;

  @State private clockText: string = '--:--';
  @State private clockDate: string = '';
  @State private clockWeek: string = '';

  /** 工具入口卡片摘要（体测/水量/文件传输读本机数据，其余用功能点）。 */
  @State private fitDigest: ToolCardDigest = new ToolCardDigest('体测未加载');
  @State private waterDigest: ToolCardDigest = new ToolCardDigest('水量未加载');
  @State private cloudDigest: ToolCardDigest = new ToolCardDigest('临时空间未连接');

  scroller: Scroller = new Scroller();
  private rotateTimer: number = -1;
  private shimmerTimer: number = -1;  private fadeTimer: number = -1;
  private paintTimer: number = -1;
  private refreshTimer: number = -1;
  private clockTimer: number = -1;
  private refreshRunning: boolean = false;
  private refreshSeq: number = 0;
  private startedAt: number = 0;
  private loadSeq: number = 0;
  private readyFired: boolean = false;
  private lastLoadAt: number = 0;
  /** 手势刚结束（拖动/缩放）时屏蔽一次误触打开。 */
  private suppressTap: boolean = false;

  onEpochChanged(): void {
    // 切回工作台：2 分钟内只复用内存缓存，避免每次切 tab 都重复请求
    if (Date.now() - this.lastLoadAt < 2 * 60 * 1000) {
      this.readLocalTasks();
      this.applyLocal();
      return;
    }
    this.load(false);
  }

  onAddEpoch(): void {
    if (this.addEpoch > 0) {
      this.sheetOpen = true;
    }
  }

  aboutToAppear(): void {
    this.syncQuickOrder();
    this.readLocalTasks();
    this.startedAt = Date.now();
    this.applyLocal();
    this.refreshDigests();
    this.startSkeleton();
    this.load(false);
    this.loadCards();
    this.tickClock();
    // 兜底：首帧动画最多 1.5s，任何异常/弱网都不能让骨架屏常驻
    setTimeout(() => {
      if (this.loading) {
        this.finishLoading();
      }
    }, 1500);
    this.rotateTimer = setInterval(() => {
      this.rotateTick();
    }, 5000);
    this.scheduleClock();
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
    if (this.paintTimer >= 0) {
      clearTimeout(this.paintTimer);
      this.paintTimer = -1;
    }
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    if (this.clockTimer >= 0) {
      clearTimeout(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private scheduleClock(): void {
    this.clockTimer = setTimeout(() => {
      this.tickClock();
      this.scheduleClock();
    }, 60000 - Date.now() % 60000);
  }

  private tickClock(): void {
    const now: Date = new Date();
    const minute: number = Math.floor(now.getTime() / 60000);
    if (minute !== this.planMinute && this.ttSnapshot !== undefined) {
      this.plan = TtCalendar.plan(this.ttSnapshot, now.getTime());
      this.planMinute = minute;
    }
    this.clockText = HomeDigest.pad2(now.getHours()) + ':' + HomeDigest.pad2(now.getMinutes());
    this.clockDate = HomeDigest.dateText(now);
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    this.clockWeek = names[now.getDay()];
  }

  private async loadCards(): Promise<void> {
    // 首帧可能早于根页面写入会话身份，等 sid 就绪后再读本机布局
    let sid: string = Services.currentSid;
    let tries: number = 0;
    while (sid.length === 0 && tries < 15) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 200);
      });
      sid = Services.currentSid;
      tries += 1;
    }
    if (sid.length === 0) {
      return;
    }
    const stored: HomeCardConfig[] | undefined = await HomeCards.load(sid);
    if (stored !== undefined && stored.length > 0) {
      this.cards = HomeCards.normalize(stored);
    }
    this.refreshDigests();
    this.refreshFitDigest();
  }

  /** 体测历史（带 TTL 缓存）就绪后刷新入口卡片摘要。 */
  private async refreshFitDigest(): Promise<void> {
    if (Services.currentSid.length === 0) {
      return;
    }
    try {
      const fit: FitRecsResult = await Services.fitRecs.refresh(false);
      this.fitDigest = HomeToolDigest.fit(fit.records);
    } catch (e) {
      // 失败时保留已有摘要
    }
  }

  /** 只读本机缓存刷新工具卡片摘要（体测历史在 load 里异步更新）。 */
  private refreshDigests(): void {
    const sections = Services.userdata.currentSections();
    this.waterDigest = HomeToolDigest.water(WaterCodec.fromJson(JsonBlob.get(sections, 'water')), Date.now());
    this.cloudDigest = HomeToolDigest.cloud(Services.cloudspace.snapshot());
    this.fitDigest = HomeToolDigest.fit(Services.fitRecs.local());
  }

  private digestOf(id: string): ToolCardDigest {
    if (id === 'fit') {
      return this.fitDigest;
    }
    if (id === 'water') {
      return this.waterDigest;
    }
    if (id === 'file') {
      return this.cloudDigest;
    }
    return HomeToolDigest.fallback(id, HomeCards.defOr(id).subtitle);
  }

  private applyCards(next: HomeCardConfig[]): void {    const normalized: HomeCardConfig[] = HomeCards.normalize(next);
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.spring() }, () => {
      this.cards = normalized;
    });
    HomeCards.save(Services.currentSid, normalized);
  }

  private onCardTap(id: string): void {
    if (this.suppressTap || this.editing) {
      return;
    }
    if (id === 'weather') {
      showFeedback(this.getUIContext(), '当前设备暂未提供天气数据');
      return;
    }
    if (id === 'clock') {
      return;
    }
    if (id === 'quick') {
      this.onOpenAll();
      return;
    }
    const def: HomeCardDef = HomeCards.defOr(id);
    if (def.toolId.length > 0) {
      this.onOpenTool(def.toolId);
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

  /** 首页常用工具拖拽落位：只调整顺序，交由外层持久化。 */
  private moveQuick(from: number, to: number): void {
    const tools: ToolDef[] = this.quick();
    if (from === to || from < 0 || to < 0 || from >= tools.length || to >= tools.length) {
      return;
    }
    const ids: string[] = [];
    for (let i = 0; i < this.quickOrder.length; i++) {
      ids.push(this.quickOrder[i]);
    }
    if (from >= ids.length || to >= ids.length) {
      return;
    }
    const moved: string[] = ids.splice(from, 1);
    ids.splice(to, 0, moved[0]);
    this.quickOrder = ids;
    this.onReorderQuick(ids);
  }

  private quickRows(wide: boolean): number {
    const lanes: number = wide ? 4 : 2;
    return Math.ceil(this.quick().length / lanes);
  }

  private quickHeight(wide: boolean): number {
    return this.quickRows(wide) * (wide ? 64 : 36);
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

  /** 首帧直接用本机缓存渲染（marks / 课表 / 作业 / 通知），不等网络。 */
  private async readLocalTasks(): Promise<void> {
    const sid = Services.currentSid;
    const tasks = await TaskRepository.load(false);
    if (sid && sid === Services.currentSid) {
      this.tasks = tasks;
      this.applyAssignments(Services.homework.local());
    }
  }

  private applyAssignments(rows: HomeworkRow[]): void {
    const hidden = HidePrefs.read(Services.userdata.currentSections()).hwHide;
    const excluded = new Set<string>(hidden);
    const marks = Services.marks.marks();
    rows.forEach((row: HomeworkRow) => {
      if (marks.isDone(MarkKind.HW, row.id)) excluded.add(row.id);
    });
    const brief = HomeworkBrief.build(rows, excluded, this.tasks, Date.now());
    const items = HomeDigest.hwItems(brief.pending.map((hw: HomeworkItem) => hw.row), 5);
    const personal = this.tasks.filter((task: PersonalTask) => !task.done);
    for (const task of personal) {
      const item = new HomeCardItem();
      item.kind = 'task';
      item.id = task.id;
      item.title = HomeDigest.shortTitle(task.title);
      item.sub = task.dueLabel() || '个人任务';
      item.dueAt = HomeworkDueCalculator.parseDue(task.due, task.dueTime || '23:59') ?? Number.MAX_SAFE_INTEGER;
      items.push(item);
    }
    this.hwOpen = personal.length + brief.pending.length;
    this.hwItems = items.sort((a: HomeCardItem, b: HomeCardItem) => a.dueAt - b.dueAt).slice(0, 5);
    this.hwIdx = this.hwIdx < this.hwItems.length ? this.hwIdx : 0;
  }

  private openItem(item: HomeCardItem): void {
    if (this.editing || this.suppressTap) return;
    const launch = new ToolLaunch(item.kind === 'nt' ? 'nt' : 'hw');
    if (item.kind === 'task') launch.taskId = item.id;
    else if (item.kind === 'hw') launch.homeworkId = item.id;
    else launch.noticeId = item.id;
    AppGlobal.requestTool(launch);
  }

  private async completeItem(item: HomeCardItem): Promise<void> {
    const key = item.kind + ':' + item.id;
    if (this.editing || this.suppressTap || this.completing.has(key)) return;
    this.completing.add(key);
    const sid = Services.currentSid;
    try {
      if (item.kind === 'task') {
        const saved = await TaskRepository.toggle(item.id, true);
        if (!saved) return;
        await this.readLocalTasks();
      } else {
        const mark = item.kind === 'nt' ? MarkKind.NT_DONE : MarkKind.HW;
        await Services.marks.setMark(mark, item.id, true);
      }
      if (sid !== Services.currentSid) return;
      this.applyLocal();
      DeskForms.refresh();
      NotifyCenter.syncAll(true);
    } finally {
      this.completing.delete(key);
    }
  }

  private applyLocal(): void {
    const tt = Services.timetable.local();
    this.ttSnapshot = tt;
    this.plan = TtCalendar.plan(tt, Date.now());
    this.applyAssignments(Services.homework.local());
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
    this.ntIdx = 0;
    this.ntItems = HomeDigest.ntItems(cards, (key: string) => snapshot.isDone(MarkKind.NT_DONE, key));
    this.ntState = ok ? 'ok' : (Services.currentSid.length === 0 ? 'off' : 'error');
  }

  private async load(force: boolean): Promise<void> {
    const seq: number = this.loadSeq + 1;
    this.loadSeq = seq;
    this.lastLoadAt = Date.now();
    const now: number = Date.now();
    this.applyLocal();
    this.refreshDigests();
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
    const ttPromise = Services.loadTimetableForView(force);
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
    try {
      const tt: TtResult = await ttPromise;
      if (seq === this.loadSeq) {
        this.ttSnapshot = tt.snapshot;
        this.plan = TtCalendar.plan(tt.snapshot, Date.now());
      }
    } catch (e) {
      // 忽略
    }
    try {
      const hw: HomeworkResult = await hwPromise;
      if (seq === this.loadSeq) this.applyAssignments(hw.rows);
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
      text += ' · ' + (next.state === SessionState.ONGOING ? '上课中 ' : '下一节 ') + next.startText + ' ' + next.name;
    } else if (this.plan.next !== undefined) {
      text += ' · 下次 ' + this.plan.next.dayText + ' ' + this.plan.next.name;
    }
    return text;
  }

  /** 当前内容区可用宽度（vp）。 */
  private contentWidth(): number {
    const max: number = Breakpoints.contentMaxWidth(this.layoutWidth);
    const pad: number = Breakpoints.pagePadding(this.layoutWidth);
    const available: number = Math.min(this.layoutWidth, max) - pad * 2;
    return available > 0 ? available : 328;
  }

  private widthForSpan(span: number): number {
    const full: number = this.contentWidth();
    if (HomeCards.normalizeSpan(span) === HomeCards.FULL) {
      return full;
    }
    return Math.floor((full - Tokens.GAP) / 2);
  }

  /** 卡片所在列右侧还剩下的宽度（防止缩放时卡片跑出屏幕）。 */
  private maxWidthAt(cfg: HomeCardConfig): number {
    const half: number = this.widthForSpan(HomeCards.HALF);
    const full: number = this.widthForSpan(HomeCards.FULL);
    if (this.slotCol(this.indexOf(cfg.id)) === 0) {
      return full;
    }
    return Math.max(half, full - half - Tokens.GAP);
  }

  /** 卡片当前宽度：缩放拖动时实时跟手，夹在半宽与整行之间。 */
  private cardWidthOf(cfg: HomeCardConfig): number {
    const base: number = this.widthForSpan(cfg.span);
    if (this.resizingId !== cfg.id) {
      return base;
    }
    const half: number = this.widthForSpan(HomeCards.HALF);
    const max: number = this.maxWidthAt(cfg);
    return Math.max(half, Math.min(max, this.resizeStartWidth + this.resizeDx));
  }

  private spanAt(index: number): number {
    return HomeCards.normalizeSpan(this.cards[index].span);
  }

  /**
   * 槽位行号：必须把目标卡片自身也算进去。
   * 半宽卡后面紧跟整行卡时，整行卡要先换行，否则会落在右列并溢出屏幕。
   */
  private slotRow(index: number): number {
    if (index < 0 || index >= this.cards.length) {
      return 0;
    }
    let row: number = 0;
    let used: number = 0;
    for (let i = 0; i <= index; i++) {
      const span: number = this.spanAt(i);
      if (used + span > HomeCards.PER_ROW) {
        row += 1;
        used = 0;
      }
      if (i === index) {
        return row;
      }
      used += span;
      if (used >= HomeCards.PER_ROW) {
        row += 1;
        used = 0;
      }
    }
    return row;
  }

  private slotCol(index: number): number {
    if (index < 0 || index >= this.cards.length) {
      return 0;
    }
    let used: number = 0;
    for (let i = 0; i <= index; i++) {
      const span: number = this.spanAt(i);
      if (used + span > HomeCards.PER_ROW) {
        used = 0;
      }
      if (i === index) {
        return used;
      }
      used += span;
      if (used >= HomeCards.PER_ROW) {
        used = 0;
      }
    }
    return used;
  }

  private indexOf(id: string): number {
    for (let i = 0; i < this.cards.length; i++) {
      if (this.cards[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private spanOf(id: string): number {
    const index: number = this.indexOf(id);
    return index >= 0 ? HomeCards.normalizeSpan(this.cards[index].span) : HomeCards.HALF;
  }

  private isDragging(): boolean {
    return this.dragId.length > 0;
  }

  /** 拖动开始时的卡片中心（用于把手指位置换算成绝对坐标，跨多格重排时保持跟手）。 */
  private dragStartCenterX: number = 0;
  private dragStartCenterY: number = 0;
  private dragReordered: boolean = false;

  /** 卡片槽位左上角（相对内容区）。整行卡片永远从第 0 列开始。 */
  private slotX(index: number): number {
    if (index < 0 || index >= this.cards.length) {
      return 0;
    }
    if (this.spanAt(index) === HomeCards.FULL || this.slotCol(index) === 0) {
      return 0;
    }
    return this.widthForSpan(HomeCards.HALF) + Tokens.GAP;
  }

  private cardHeight(cfg: HomeCardConfig): number {
    if (cfg.id === 'tt' && cfg.span === HomeCards.FULL) {
      return Math.max(HOME_CARD_H, 86 + 46 * this.plan.today.length);
    }
    return HOME_CARD_H;
  }

  private slotY(index: number): number {
    if (index < 0 || index >= this.cards.length) {
      return 0;
    }
    const ttIndex: number = this.indexOf('tt');
    const extra: number = ttIndex >= 0 && ttIndex < index ? this.cardHeight(this.cards[ttIndex]) - HOME_CARD_H : 0;
    return this.slotRow(index) * (HOME_CARD_H + Tokens.GAP) + extra;
  }

  private centerX(index: number): number {
    return this.slotX(index) + this.widthForSpan(this.cards[index].span) / 2;
  }

  private centerY(index: number): number {
    return this.slotY(index) + this.cardHeight(this.cards[index]) / 2;
  }

  private boardHeight(): number {
    const last: number = this.cards.length - 1;
    return last >= 0 ? this.slotY(last) + this.cardHeight(this.cards[last]) : 0;
  }

  /** 按 id 查槽位（渲染时读取 cards 状态，重排后才能触发其他卡片让位）。 */
  private slotXOf(id: string): number {
    return this.slotX(this.indexOf(id));
  }

  private slotYOf(id: string): number {
    return this.slotY(this.indexOf(id));
  }

  private beginDrag(id: string): void {
    const index: number = this.indexOf(id);
    if (index < 0) {
      return;
    }
    this.suppressTap = true;
    this.dragId = id;
    this.dragStartCenterX = this.centerX(index);
    this.dragStartCenterY = this.centerY(index);
    this.dragDx = 0;
    this.dragDy = 0;
    this.dragReordered = false;
  }

  /**
   * 拖动实时排序：被拖卡片中心进入某个槽位就立即交换，
   * 其余卡片由隐式动画让位；被拖卡片用绝对中心减去新槽位中心，保持在手指下不跳。
   */
  private updateDrag(dx: number, dy: number): void {
    if (this.dragId.length === 0) {
      return;
    }
    const absX: number = this.dragStartCenterX + dx;
    const absY: number = this.dragStartCenterY + dy;
    const from: number = this.indexOf(this.dragId);
    if (from < 0) {
      return;
    }
    const to: number = this.targetIndexAt(absX, absY, from);
    if (to !== from) {
      this.cards = HomeCards.moveTo(this.cards, from, to);
      this.dragReordered = true;
    }
    const now: number = this.indexOf(this.dragId);
    this.dragDx = absX - this.centerX(now);
    this.dragDy = absY - this.centerY(now);
  }

  private cancelDrag(): void {
    this.dragId = '';
    this.dragDx = 0;
    this.dragDy = 0;
    this.dragReordered = false;
    setTimeout(() => {
      this.suppressTap = false;
    }, 260);
  }

  /** 松手：已在拖动过程中完成落位，这里只回收拖动偏移并持久化。 */
  private endDrag(): void {
    if (this.dragId.length === 0) {
      return;
    }
    const reordered: boolean = this.dragReordered;
    this.dragId = '';
    this.dragDx = 0;
    this.dragDy = 0;
    this.dragReordered = false;
    if (reordered) {
      HomeCards.save(Services.currentSid, this.cards);
    }
    setTimeout(() => {
      this.suppressTap = false;
    }, 260);
  }

  /** 命中槽位：中心落进哪个卡片的矩形就换到哪个位置；落在间隙时取最近中心。 */
  private targetIndexAt(x: number, y: number, exclude: number): number {
    for (let i = 0; i < this.cards.length; i++) {
      const sx: number = this.slotX(i);
      const sy: number = this.slotY(i);
      const w: number = this.widthForSpan(this.spanAt(i));
      if (x >= sx && x <= sx + w && y >= sy && y <= sy + this.cardHeight(this.cards[i])) {
        return i;
      }
    }
    let best: number = exclude;
    let bestDistance: number = Number.MAX_VALUE;
    for (let i = 0; i < this.cards.length; i++) {
      const cx: number = this.centerX(i);
      const cy: number = this.centerY(i);
      const distance: number = (cx - x) * (cx - x) + (cy - y) * (cy - y);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /** 右下角抓手拖动：宽度实时跟手，松手吸附到半宽 / 整行。 */
  private onCardResize(id: string, phase: string, dx: number): void {
    if (phase === 'start') {
      this.suppressTap = true;
      const index: number = this.indexOf(id);
      this.resizeOriginIndex = index;
      this.resizeOriginSpan = this.spanOf(id);
      this.resizeStartWidth = this.widthForSpan(this.resizeOriginSpan);
      this.resizeDx = 0;
      // 右列卡片先与同排左卡换位：缩放时从左边缘向右展开，避免跑出屏幕
      this.resizeSwapped = index > 0 && this.slotCol(index) > 0;
      if (this.resizeSwapped) {
        this.cards = HomeCards.moveTo(this.cards, index, index - 1);
      }
      this.resizingId = id;
      return;
    }
    if (phase === 'update') {
      this.resizeDx = dx;
      return;
    }
    // 两态吸附：向外拖（半宽→整行）或向内拖（整行→半宽）超过阈值即切换
    let targetSpan: number = this.resizeOriginSpan;
    if (this.resizeOriginSpan === HomeCards.HALF && this.resizeDx > 24) {
      targetSpan = HomeCards.FULL;
    } else if (this.resizeOriginSpan === HomeCards.FULL && this.resizeDx < -24) {
      targetSpan = HomeCards.HALF;
    }
    let next: HomeCardConfig[] = HomeCards.withSpan(this.cards, id, targetSpan);
    if (this.resizeSwapped && targetSpan === this.resizeOriginSpan) {
      // 没有达到切换阈值：还原换位，避免误触改顺序
      next = HomeCards.moveTo(next, this.indexOf(id), this.resizeOriginIndex);
    }
    this.resizeSwapped = false;
    this.getUIContext().animateTo({ duration: Motion.SLOW, curve: Motion.ease() }, () => {
      this.resizingId = '';
      this.resizeDx = 0;
      this.cards = next;
    });
    HomeCards.save(Services.currentSid, next);
    setTimeout(() => {
      this.suppressTap = false;
    }, 260);
  }

  private bottomSpace(): number {
    return Breakpoints.contentBottomSpace(this.layoutWidth);
  }


  /**
   * 工作台「今日」hero：莫奈浅色纸面（睡莲青 / 雾蓝 / 暖沙三段色条），
   * 深色只用于文字，保持与通知页、手表端一致的莫奈色系。
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
  iconBadge(symbol: Resource, accent: string, box: number, glyph: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(symbol)
        .fontSize(glyph)
        .fontWeight(FontWeight.Medium)
        .fontColor([accent])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(box)
    .height(box)
    .backgroundColor(Tokens.tint(accent, 0.12))
    .border({ width: 1, color: Tokens.tint(accent, 0.18) })
    .borderRadius(box * 0.3)
  }

  @Builder
  cardTitleRow(symbol: Resource, accent: string, title: string, badge: string) {
    Row() {
      this.iconBadge(symbol, accent, 30, 17)
      Text(title)
        .fontSize(Tokens.F_LABEL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
        .margin({ left: 8 })
        .layoutWeight(1)
        .maxLines(1)
      if (badge.length > 0) {
        Text(badge)
          .fontSize(Tokens.F_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(Tokens.tint(accent, 0.16))
          .borderRadius(Tokens.RADIUS_PILL)
      }
    }
    .width('100%')
  }

  /** 整行课程卡的一节课：时间 + 课程 + 教室。 */
  @Builder
  sessionRow(s: SessionInfo) {
    Row({ space: 8 }) {
      Text(s.startText)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.MIST_TEAL)
        .width(48)
      Column({ space: 2 }) {
        Text(s.name)
          .fontSize(Tokens.F_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(s.span + (s.room.length > 0 ? ' · ' + s.room : ''))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (s.countdown.length > 0) {
        Text(s.countdown)
          .fontSize(11)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.1))
          .borderRadius(8)
      }
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
  }

  /** 整行列表卡的一行：标题 + 右侧辅助信息。 */
  @Builder
  listRow(item: HomeCardItem, accent: string) {
    Row({ space: 6 }) {
      Row()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(accent)
      Text(item.title)
        .fontSize(12)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.sub.length > 0) {
        Text(item.sub)
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(26)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openItem(item))
  }

  /** 卡片底部提示行：填入半宽卡片的剩余空间，避免大片空白。 */
  @Builder
  cardFooter(text: string) {
    Row({ space: 2 }) {
      Text(text)
        .fontSize(10)
        .fontColor(Tokens.TEXT_TERTIARY)
        .layoutWeight(1)
        .maxLines(1)
      SymbolGlyph(AppSymbols.ARROW_RIGHT)
        .fontSize(10)
        .fontColor([Tokens.TEXT_TERTIARY])
    }
    .width('100%')
    .height(14)
    .alignItems(VerticalAlign.Center)
  }

  private afterClassText(): string {
    const next = this.plan.next;
    return '今日课程已结束' + (next !== undefined ? ' · 下次 ' + next.dayText + ' ' + next.startText + ' ' + next.name : '');
  }

  @Builder
  compactCourse(s: SessionInfo) {
    Text((s.state === SessionState.ONGOING ? '上课中' : '下一节') + ' · ' + s.startText)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(Tokens.MIST_TEAL)
      .margin({ top: 6 })
    Text(s.name)
      .fontSize(Tokens.F_BODY)
      .fontWeight(FontWeight.Medium)
      .fontColor(Tokens.TEXT_PRIMARY)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Text(s.span + (s.room.length > 0 ? ' · ' + s.room : ''))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(Tokens.TEXT_SECONDARY)
      .maxLines(1)
    Blank()
    this.cardFooter(s.countdown && s.countdown !== '下一节' ? s.countdown : '查看本周课表')
  }

  @Builder
  ttBody(wide: boolean) {
    this.cardTitleRow(AppSymbols.TIMETABLE, '#6E8CA8', '今日课程',
      this.plan.hasData && this.plan.today.length > 0 ? '' + this.plan.today.length + ' 节' : '')
    if (this.plan.hasData && this.plan.today.length > 0 && (wide || this.nextToday() !== undefined)) {
      if (wide) {
        Column() {
          ForEach(this.plan.today, (s: SessionInfo) => {
            this.sessionRow(s)
          }, (s: SessionInfo, index: number) => index + '_' + s.startAt + '_' + s.name + '_' + s.room + '_' + s.span + '_' + s.state + '_' + s.countdown)
        }
        .width('100%')
        Blank()
        this.cardFooter(this.plan.todayState === TodayState.DONE ? this.afterClassText() : '查看本周课表')
      } else if (this.nextToday() !== undefined) {
        this.compactCourse(this.nextToday()!)
      }
    } else if (this.plan.hasData) {
      Text(this.plan.todayState === TodayState.DONE ? '今日课程已结束' : '今天没课')
        .fontSize(wide ? Tokens.F_HEADING : Tokens.F_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
        .margin({ top: 10 })
      Text(this.plan.next !== undefined
        ? '下次 · ' + this.plan.next.dayText + ' ' + this.plan.next.startText + ' ' + this.plan.next.name : '近期暂无课程')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .margin({ top: 4 })
      Blank()
      this.cardFooter('查看本周课表')
    } else {
      Text('课表未同步')
        .fontSize(Tokens.F_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .margin({ top: 10 })
      Text('打开课表拉取本周课程')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .margin({ top: 4 })
      Blank()
      this.cardFooter('去同步课表')
    }
  }

  @Builder
  doneAction(item: HomeCardItem) {
    Button(item.kind === 'nt' ? '已处理' : '完成')
      .fontSize(11).height(24).margin({ left: 8 })
      .backgroundColor(Tokens.TINT_TEAL).fontColor(Tokens.MIST_TEAL)
      .accessibilityText((item.kind === 'nt' ? '标记已处理 ' : '完成 ') + item.title)
      .onClick(() => this.completeItem(item))
  }

  @Builder
  hwBody(wide: boolean) {
    this.cardTitleRow(AppSymbols.HOMEWORK, Tokens.WARM_SAND, '任务待办',
      this.hwOpen > 0 ? '' + this.hwOpen : '')
    if (this.hwItems.length > 0) {
      if (wide) {
        Column() {
          ForEach(this.hwItems.slice(0, 3), (item: HomeCardItem, index: number) => {
            Row() {
              Column() { this.listRow(item, Tokens.WARM_SAND) }.layoutWeight(1)
              this.doneAction(item)
            }
          }, (item: HomeCardItem, index: number) => 'hw_' + item.kind + item.id + item.title + item.sub)
        }
        .width('100%')
        .margin({ top: 6 })
        Blank()
      } else {
        Text(this.hwTitle())
          .onClick(() => { if (this.hwIdx < this.hwItems.length) this.openItem(this.hwItems[this.hwIdx]); })
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })
          .opacity(this.hwFade ? 0 : 1)
          .translate({ y: this.hwFade ? -6 : 0 })
        Text(this.hwSub())
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
          .margin({ top: 4 })
          .opacity(this.hwFade ? 0 : 1)
          .translate({ y: this.hwFade ? -6 : 0 })
        Blank()
        if (this.hwIdx < this.hwItems.length) {
          this.doneAction(this.hwItems[this.hwIdx])
        }
      }
    } else {
      Text('暂无待办任务')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .margin({ top: 10 })
      Blank()
    }
  }

  @Builder
  ntBody(wide: boolean) {
    this.cardTitleRow(AppSymbols.BELL, '#B06A55', '通知待处理',
      this.ntPending > 0 ? '' + this.ntPending : '')
    if (this.ntState === 'ok') {
      if (this.ntItems.length > 0) {
        if (wide) {
          Column() {
            ForEach(this.ntItems.slice(0, 3), (item: HomeCardItem, index: number) => {
              Row() {
                Column() { this.listRow(item, '#B06A55') }.layoutWeight(1)
                this.doneAction(item)
              }
            }, (item: HomeCardItem, index: number) => 'nt_' + item.id + item.title + item.sub)
          }
          .width('100%')
          .margin({ top: 6 })
          Blank()
        } else {
          Text(this.ntTitle())
            .onClick(() => { if (this.ntIdx < this.ntItems.length) this.openItem(this.ntItems[this.ntIdx]); })
            .fontSize(Tokens.F_LABEL)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 10 })
            .opacity(this.ntFade ? 0 : 1)
            .translate({ y: this.ntFade ? -6 : 0 })
          Text(this.ntSub())
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .maxLines(1)
            .margin({ top: 4 })
            .opacity(this.ntFade ? 0 : 1)
            .translate({ y: this.ntFade ? -6 : 0 })
          Blank()
          if (this.ntIdx < this.ntItems.length) {
            this.doneAction(this.ntItems[this.ntIdx])
          }
        }
      } else {
        Text('暂无待处理通知')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
          .margin({ top: 10 })
        Blank()
      }
    } else {
      Text(this.ntState === 'off' ? '通知需联网同步'
        : (this.ntState === 'error' ? '同步失败，点开重试' : '通知同步中…'))
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(2)
        .margin({ top: 10 })
      Blank()
    }
  }

  @Builder
  powerBody(wide: boolean) {
    this.cardTitleRow(AppSymbols.POWER, '#C29A3B', '宿舍电费', '')
    if (this.powerHas) {
      Row() {
        Text(this.powerQ)
          .fontSize(wide ? 32 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text(this.powerUnit)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ left: 2, bottom: 4 })
        if (wide) {
          Blank()
          Text(HomeDigest.powerStateText(this.powerState))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.powerPillColor())
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(Tokens.tint(this.powerPillColor(), 0.12))
            .borderRadius(Tokens.RADIUS_PILL)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: wide ? 6 : 8 })
      Text(this.powerLabel + (this.powerUpd.length > 0 ? ' · ' + this.powerUpd : ''))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(1)
        .margin({ top: 4 })
      if (wide) {
        if (this.powerState === 'low' || this.powerState === 'warn') {
          Text('电量偏低，建议及时充值')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .maxLines(1)
            .margin({ top: 4 })
        }
      } else {
        Text(HomeDigest.powerStateText(this.powerState))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.powerPillColor())
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(Tokens.tint(this.powerPillColor(), 0.12))
          .borderRadius(Tokens.RADIUS_PILL)
          .margin({ top: 6 })
      }
    } else {
      Text('关注宿舍后显示电量')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(wide ? 2 : 1)
        .margin({ top: 10 })
      if (wide) {
        Text('在「我的 · 宿舍电费」选择房间后自动同步')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
          .margin({ top: 4 })
      }
    }
    Blank()
    if (!wide) {
      this.cardFooter('查看用电趋势')
    }
  }

  @Builder
  quickBody(wide: boolean) {
    Row() {
      Text('常用工具')
        .fontSize(Tokens.F_LABEL)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
      Row({ space: 2 }) {
        Text('全部')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
        SymbolGlyph(AppSymbols.ARROW_RIGHT)
          .fontSize(11)
          .fontColor([Tokens.SLATE_BLUE])
      }
    }
    .width('100%')

    if (this.quick().length > 0) {
      List({ space: 0 }) {
        ForEach(this.quick(), (tool: ToolDef) => {
          ListItem() {
            Column() {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph(tool.symbol)
                  .fontSize(wide ? 22 : 16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([tool.accent])
                  .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
              }
              .width(wide ? 34 : 26)
              .height(wide ? 34 : 26)
              .backgroundColor(Tokens.tint(tool.accent, 0.12))
              .borderRadius(10)
              Text(tool.name)
                .fontSize(10)
                .fontColor(Tokens.TEXT_SECONDARY)
                .maxLines(1)
                .margin({ top: 2 })
            }
            .width('100%')
            .height(wide ? 64 : 36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.onOpenTool(tool.id);
            })
          }
          .transition(Motion.popIn())
        }, (tool: ToolDef) => 'qc_' + tool.id)
          .onMove((from: number, to: number) => {
            this.moveQuick(from, to);
          })
      }
      .lanes(wide ? 4 : 2)
      .width('100%')
      .height(this.quickHeight(wide))
      .scrollBar(BarState.Off)
      .enableScrollInteraction(false)
      .margin({ top: 8 })
      .accessibilityText('常用工具，长按拖动可调整顺序')
    } else {
      Text('去工具页勾选常用工具')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ top: 10 })
    }
    Blank()
  }

  @Builder
  digestLineRow(line: ToolDigestLine) {
    Row({ space: 6 }) {
      Row()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(Tokens.TEXT_TERTIARY)
      Text(line.text)
        .fontSize(11)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (line.sub.length > 0) {
        Text(line.sub)
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(20)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  entryBody(def: HomeCardDef, wide: boolean) {
    Row() {
      this.iconBadge(def.symbol, def.accent, wide ? 40 : 34, wide ? 22 : 18)
      Column() {
        Text(def.title)
          .fontSize(wide ? Tokens.F_BODY : Tokens.F_LABEL)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.digestOf(def.id).primary)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
        if (!wide && this.digestOf(def.id).lines.length > 0) {
          Text(this.digestOf(def.id).lines[0].text)
            .fontSize(11)
            .fontColor(Tokens.TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
      if (wide) {
        SymbolGlyph(AppSymbols.ARROW_RIGHT)
          .fontSize(15)
          .fontColor([Tokens.TEXT_TERTIARY])
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    if (wide) {
      Column() {
        ForEach(this.digestOf(def.id).lines, (line: ToolDigestLine) => {
          this.digestLineRow(line)
        }, (line: ToolDigestLine) => line.text + '|' + line.sub)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    Blank()
    if (!wide) {
      this.cardFooter('点击进入')
    }
  }

  @Builder
  clockBody(wide: boolean) {
    Row() {
      Text('时钟')
        .fontSize(Tokens.F_LABEL)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
      SymbolGlyph(AppSymbols.CLOCK)
        .fontSize(16)
        .fontColor([Tokens.MIST_TEAL])
    }
    .width('100%')

    Text(this.clockText)
      .fontSize(wide ? 34 : 30)
      .fontWeight(FontWeight.Bold)
      .fontColor(Tokens.TEXT_PRIMARY)
      .margin({ top: wide ? 8 : 8 })
      .animation({ duration: Motion.NORMAL, curve: Motion.ease() })

    if (wide) {
      Row({ space: 6 }) {
        Text(this.clockWeek + ' · ' + this.clockDate)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .layoutWeight(1)
          .maxLines(1)
        if (HomeDigest.weekText(this.plan.week).length > 0) {
          Text(HomeDigest.weekText(this.plan.week))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.MIST_TEAL)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.12))
            .borderRadius(6)
        }
      }
      .width('100%')
      .margin({ top: 4 })
    } else {
      Text(this.clockDate)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(1)
        .margin({ top: 2 })
      Text(this.clockWeek + (HomeDigest.weekText(this.plan.week).length > 0
        ? ' · ' + HomeDigest.weekText(this.plan.week) : ''))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .margin({ top: 2 })
    }
    Blank()
  }

  @Builder
  weatherBody(wide: boolean) {
    Row() {
      Text('天气')
        .fontSize(Tokens.F_LABEL)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_SECONDARY)
        .layoutWeight(1)
      SymbolGlyph(AppSymbols.WEATHER)
        .fontSize(16)
        .fontColor(['#4A88A8'])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width('100%')

    Row({ space: 8 }) {
      SymbolGlyph(AppSymbols.WEATHER)
        .fontSize(wide ? 30 : 24)
        .fontColor(['#4A88A8'])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      Text('天气数据未接入')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
    .margin({ top: wide ? 12 : 10 })

    if (wide) {
      Text('当前设备未提供天气服务，可在系统天气中查看')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(2)
        .margin({ top: 6 })
    } else {
      Text('可在系统天气查看')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .margin({ top: 4 })
    }
    Blank()
    if (!wide) {
      this.cardFooter('在系统天气中查看')
    }
  }
  @Builder
  cardBody(cfg: HomeCardConfig) {
    if (cfg.id === 'tt') {
      this.ttBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'hw') {
      this.hwBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'nt') {
      this.ntBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'power') {
      this.powerBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'quick') {
      this.quickBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'clock') {
      this.clockBody(cfg.span === HomeCards.FULL)
    } else if (cfg.id === 'weather') {
      this.weatherBody(cfg.span === HomeCards.FULL)
    } else {
      this.entryBody(HomeCards.defOr(cfg.id), cfg.span === HomeCards.FULL)
    }
  }

  /** 单张卡片：编辑态右上角移除 + 长按拖动排序 + 右下角边框线拖动缩放。 */
  @Builder
  dragCard(cfg: HomeCardConfig) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        HomeCardShell({
          cardHeightVp: this.cardHeight(cfg),
          accentColor: HomeCards.defOr(cfg.id).accent,
          resizing: this.resizingId === cfg.id,
          onCardTap: () => {
            this.onCardTap(cfg.id);
          },
          onResize: (phase: string, dx: number) => {
            this.onCardResize(cfg.id, phase, dx);
          }
        }) {
          this.cardBody(cfg)
        }

        if (this.editing) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph(AppSymbols.XMARK)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor([Color.White])
          }
          .width(20)
          .height(20)
          .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.78))
          .border({ width: 1, color: Tokens.tint('#FFFFFF', 0.92) })
          .borderRadius(10)
          .shadow({ radius: 6, color: Tokens.tint(Tokens.TEXT_PRIMARY, 0.22), offsetX: 0, offsetY: 2 })
          .margin({ top: 6, right: 6 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.applyCards(HomeCards.remove(this.cards, cfg.id));
          })
          .accessibilityText('移除 ' + HomeCards.defOr(cfg.id).title)
        }
      }
      .width('100%')
      .height(this.cardHeight(cfg))
    }
    .width(this.cardWidthOf(cfg))
    .height(this.cardHeight(cfg))
    .translate({
      x: this.slotXOf(cfg.id) + (this.dragId === cfg.id ? this.dragDx : 0),
      y: this.slotYOf(cfg.id) + (this.dragId === cfg.id ? this.dragDy : 0)
    })
    .scale({
      x: this.dragId === cfg.id ? 1.0 : 1,
      y: this.dragId === cfg.id ? 1.0 : 1
    })
    .zIndex(this.dragId === cfg.id ? 20 : 0)
    .opacity(this.dragId.length > 0 && this.dragId !== cfg.id ? 0.72 : 1)
    // 拖动/缩放中的卡片必须实时跟手；其余卡片保留动画做「让位」过渡
    .animation(this.resizingId === cfg.id || this.dragId === cfg.id
      ? { duration: 0 }
      : { duration: Motion.NORMAL, curve: Motion.spring() })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 320 })
          .onAction((event: GestureEvent) => {
            // 右下角是缩放手势区，长按在此不启动排序拖动
            const finger: FingerInfo | undefined = event.fingerList.length > 0
              ? event.fingerList[0] : undefined;
            const localX: number = finger !== undefined ? finger.localX : 0;
            const localY: number = finger !== undefined ? finger.localY : 0;
            if (localX > this.cardWidthOf(cfg) - 56 && localY > this.cardHeight(cfg) - 56) {
              return;
            }
            this.beginDrag(cfg.id);
          }),
        PanGesture({ direction: PanDirection.All, distance: 1 })
          .onActionUpdate((event: GestureEvent) => {
            this.updateDrag(event.offsetX, event.offsetY);
          })
          .onActionEnd(() => {
            this.endDrag();
          })
          .onActionCancel(() => {
            this.cancelDrag();
          })
      )
    )
  }

  @Builder
  configSheet() {
    HomeCardConfigSheet({
      cards: this.cards,
      onAddCard: (id: string) => {
        this.applyCards(HomeCards.add(this.cards, id));
      },
      onRemoveCard: (id: string) => {
        this.applyCards(HomeCards.remove(this.cards, id));
      },
      onReset: () => {
        this.applyCards(HomeCards.defaults());
      },
      onDone: () => {
        this.sheetOpen = false;
      }
    })
  }

  @Builder
  editHint() {
    Row() {
      Text('点卡片右上角 × 移除 · 长按拖动排序 · 右下角边框拖动缩放')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .layoutWeight(1)
        .maxLines(2)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.10))
    .borderRadius(Tokens.RADIUS_INPUT)
    .margin({ top: Tokens.GAP })
  }

  @Builder
  emptyCards() {
    Row() {
      Column() {
        Text('还没有工作台卡片')
          .fontSize(Tokens.F_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text('点按添加课程、作业、天气等卡片')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('添加卡片')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.MIST_TEAL)
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .margin({ top: Tokens.GAP })
    .onClick(() => {
      this.sheetOpen = true;
    })
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

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll(this.scroller) {
          Row() {
            Column() {
              this.heroCard()

              if (this.editing) {
                this.editHint()
              }

              if (this.cards.length === 0) {
                this.emptyCards()
              } else {
                Stack({ alignContent: Alignment.TopStart }) {
                  ForEach(this.cards, (cfg: HomeCardConfig) => {
                    this.dragCard(cfg)
                  }, (cfg: HomeCardConfig) => cfg.id + '_' + cfg.span)
                }
                .width('100%')
                .height(this.boardHeight())
                .margin({ top: Tokens.SPACE_4 })
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
        .padding({ top: 0 })
        .enableScrollInteraction(!this.isDragging())
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
    .bindSheet($$this.sheetOpen, this.configSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      backgroundColor: Tokens.SHEET,
      onDisappear: () => {
        this.sheetOpen = false;
      }
    })
  }
}
