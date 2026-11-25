import { vibrator } from '@kit.SensorServiceKit';
import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { MarksUpdateResult } from '../../data/marks/MarksRepository';
import { HomeworkResult } from '../../data/homework/HomeworkRepository';
import {
  HomeworkDue,
  HomeworkDueCalculator,
  HomeworkDueTone,
  HomeworkRow
} from '../../data/homework/HomeworkModels';
import { NoticeCard, NoticeCards } from '../../features/notices/NoticeCards';
import { NoticesResult } from '../../data/notices/NoticesRepository';
import { PowerPrefs, PowerPrefsData } from '../../data/power/PowerPrefs';
import { PowerPoint, PowerEstimate, PowerRange, PowerRooms, PowerRow, PowerStats, RangeStats } from '../../data/power/PowerModels';
import { PowerHistoryResult, PowerRowResult } from '../../data/power/PowerRepository';
import { SessionInfo, SessionState, TtPlan } from '../../data/timetable/TimetableModels';
import { TtCalendar } from '../../data/timetable/TtCalendar';
import { TtResult } from '../../data/timetable/TimetableRepository';
import { HomeDigest } from '../../features/home/HomeDigest';
import { WatchLogic } from '../../features/watch/WatchLogic';
import { Tokens } from '../theme/Tokens';

/** 手表作业行（轻量展示模型）。 */
class WatchHwItem {
  id: string = '';
  title: string = '';
  sub: string = '';
  tone: string = 'neutral';
}

/** 手表通知行（轻量展示模型）。 */
class WatchNtItem {
  key: string = '';
  title: string = '';
  sub: string = '';
  urgent: boolean = false;
}

/**
 * 手表端：5 屏（今日 / 作业 / 通知 / 电费 / 更多）。
 *
 * 操作贴合手表：左右滑动或转动表冠翻页；列表内表冠滚动；
 * 作业点按即完成、通知点按看详情；长按任意处打开操作菜单（刷新 / 退出）。
 * UI：深色圆屏、大字号、环形进度、底部圆点与一句操作提示。
 */
@Component
export struct WatchShell {
  @Prop userName: string = '';
  onLogout: () => void = () => {
  };

  @State private page: number = 0;
  @State private plan: TtPlan = new TtPlan();
  @State private ttReady: boolean = false;
  @State private hwItems: WatchHwItem[] = [];
  @State private hwReady: boolean = false;
  @State private ntItems: WatchNtItem[] = [];
  @State private ntReady: boolean = false;
  @State private ntPending: number = 0;
  @State private ntUrgent: number = 0;
  @State private powerQ: string = '';
  @State private powerUnit: string = '度';
  @State private powerLabel: string = '';
  @State private powerState: string = 'idle';
  @State private powerUpd: string = '';
  @State private powerDrop: string = '';
  @State private powerDays: string = '';
  @State private powerBars: number[] = [];
  @State private powerReady: boolean = false;
  @State private offline: boolean = false;
  @State private syncing: boolean = false;
  @State private lastSync: number = 0;
  @State private dataVersion: number = 0;
  @State private screenW: number = 400;
  @State private screenH: number = 400;

  @State private menuOpen: boolean = false;
  @State private logoutOpen: boolean = false;
  @State private detailOpen: boolean = false;
  @State private detailTitle: string = '';
  @State private detailStatus: string = '';
  @State private detailSummary: string = '';
  @State private detailPoints: string[] = [];
  @State private detailKey: string = '';
  @State private toast: string = '';

  private controller: SwiperController = new SwiperController();
  private ntMap: Map<string, NoticeCard> = new Map<string, NoticeCard>();

  aboutToAppear(): void {
    this.load(false);
  }

  private px(base: number): number {
    const h: number = this.screenH > 0 ? this.screenH : 400;
    const factor: number = Math.max(0.8, Math.min(1.2, h / 400));
    return Math.round(base * factor);
  }

  private hPad(): number {
    const w: number = this.screenW > 0 ? this.screenW : 400;
    // 圆屏安全区：内容宽度约 70%，避开上下圆弧
    return Math.round(Math.max(22, Math.min(76, w * 0.15)));
  }

  private buzz(ms: number = 12): void {
    try {
      vibrator.startVibration({ type: 'time', duration: ms }, { id: 0, usage: 'notification' });
    } catch (e) {
      // 无振动权限/设备不支持时忽略
    }
  }

  private flash(text: string): void {
    this.toast = text;
    setTimeout(() => {
      this.toast = '';
    }, 1800);
  }

  /** 并发刷新：每个分页独立更新，网络慢也不会卡住整屏。 */
  private async load(force: boolean): Promise<void> {
    const now: number = Date.now();
    this.syncing = true;
    this.offline = false;
    const prefs: PowerPrefsData = PowerPrefs.read(Services.userdata.currentSections());
    const tasks: Promise<void>[] = [
      this.loadTimetable(now, force),
      this.loadHomework(now, force),
      this.loadNotices(now, force),
      this.loadPower(now, force, prefs)
    ];
    await Promise.all(tasks);
    this.dataVersion = this.dataVersion + 1;
    this.syncing = false;
    this.lastSync = Date.now();
  }

  private async loadTimetable(now: number, force: boolean): Promise<void> {
    try {
      const tt: TtResult = await Services.timetable.load(force);
      this.plan = TtCalendar.plan(tt.snapshot, now);
      this.ttReady = true;
    } catch (e) {
      this.ttReady = true;
    }
  }

  private async loadHomework(now: number, force: boolean): Promise<void> {
    try {
      const hw: HomeworkResult = await Services.homework.load(force);
      this.applyHomework(hw.rows, now);
      this.hwReady = true;
    } catch (e) {
      this.hwReady = true;
    }
  }

  private applyHomework(rows: HomeworkRow[], now: number): void {
    let snapshot = Services.marks.marks();
    const open: HomeworkRow[] = HomeDigest.hwOpen(rows, (id: string) => snapshot.isDone(MarkKind.HW, id));
    const items: WatchHwItem[] = [];
    for (let i = 0; i < open.length; i++) {
      const row: HomeworkRow = open[i];
      const item: WatchHwItem = new WatchHwItem();
      item.id = row.id;
      item.title = WatchLogic.short(row.subject.length > 0 ? row.subject : row.content, 22);
      const due: HomeworkDue | undefined = HomeworkDueCalculator.evaluate(row, now);
      if (due !== undefined) {
        item.sub = due.label;
        item.tone = toneOf(due.tone);
      } else {
        item.sub = row.date.length > 0 ? row.date : '无截止';
      }
      items.push(item);
    }
    this.hwItems = items;
  }

  private async loadNotices(now: number, force: boolean): Promise<void> {
    try {
      const nt: NoticesResult = await Services.notices.load(force);
      const cards: NoticeCard[] = NoticeCards.build(nt.entries, now);
      const snapshot = Services.marks.marks();
      const map: Map<string, NoticeCard> = new Map<string, NoticeCard>();
      const items: WatchNtItem[] = [];
      let pending: number = 0;
      let urgent: number = 0;
      for (let i = 0; i < cards.length; i++) {
        const card: NoticeCard = cards[i];
        if (card.definition || card.section !== '待处理') {
          continue;
        }
        if (snapshot.isDone(MarkKind.NT_DONE, card.key)) {
          continue;
        }
        pending += 1;
        const isUrgent: boolean = card.whenAt > 0 && card.whenAt - now <= 24 * 60 * 60 * 1000;
        if (isUrgent) {
          urgent += 1;
        }
        const item: WatchNtItem = new WatchNtItem();
        item.key = card.key;
        item.title = WatchLogic.short(card.title.length > 0 ? card.title : '班级通知', 22);
        item.sub = card.statusLabel.length > 0 ? card.statusLabel : card.cat;
        item.urgent = isUrgent;
        items.push(item);
        map.set(card.key, card);
      }
      items.sort((a: WatchNtItem, b: WatchNtItem) => {
        if (a.urgent !== b.urgent) {
          return a.urgent ? -1 : 1;
        }
        return 0;
      });
      this.ntPending = pending;
      this.ntUrgent = urgent;
      this.ntItems = items;
      this.ntMap = map;
      this.ntReady = true;
    } catch (e) {
      this.ntReady = true;
    }
  }

  private async loadPower(now: number, force: boolean, prefs: PowerPrefsData): Promise<void> {
    if (prefs.sel.length === 0) {
      this.powerReady = true;
      return;
    }
    try {
      this.powerLabel = PowerRooms.labelOf(prefs.sel);
      const rowResult: PowerRowResult = await Services.power.loadRow(prefs.sel, force);
      const row: PowerRow | undefined = rowResult.row;
      if (row !== undefined) {
        this.powerQ = HomeDigest.powerQText(row.q, row.hasValue);
        this.powerUnit = row.unit.length > 0 ? row.unit : '度';
        this.powerState = HomeDigest.powerState(row.q, row.hasValue, prefs.low);
        this.powerUpd = HomeDigest.updText(row.updatedAt);
      }
      const history: PowerHistoryResult = await Services.power.loadHistory(prefs.sel, PowerRange.H24, force);
      this.applyPowerHistory(history.points, row, now);
      this.powerReady = true;
    } catch (e) {
      this.powerReady = true;
    }
  }

  private applyPowerHistory(points: PowerPoint[], row: PowerRow | undefined, now: number): void {
    if (points.length === 0) {
      this.powerBars = [];
      return;
    }
    const stats: RangeStats = PowerStats.deriveRange(points, PowerRange.H24, now);
    this.powerDrop = stats.valid
      ? ('24h 下降 ' + PowerStats.fmtDrop(stats.drop, true) + (row !== undefined ? row.unit : '度')) : '';
    const est: PowerEstimate = PowerStats.estimate(points);
    if (est.valid && row !== undefined && row.hasValue && est.ratePerDay > 0) {
      const days: number = PowerStats.daysLeft(row.q, est.ratePerDay);
      this.powerDays = days > 0 && days < 999 ? ('约可用 ' + days + ' 天') : '';
    } else {
      this.powerDays = '';
    }
    const view: PowerPoint[] = PowerStats.downsample(points, 18);
    let min: number = view[0].q;
    let max: number = view[0].q;
    for (let i = 1; i < view.length; i++) {
      min = Math.min(min, view[i].q);
      max = Math.max(max, view[i].q);
    }
    const span: number = max - min;
    const bars: number[] = [];
    for (let i = 0; i < view.length; i++) {
      const ratio: number = span > 0.001 ? (view[i].q - min) / span : 0.5;
      bars.push(Math.round(5 + ratio * 23));
    }
    this.powerBars = bars;
  }

  private refresh(): void {
    this.buzz(18);
    this.load(true);
  }

  private async completeHomework(item: WatchHwItem): Promise<void> {
    this.buzz(15);
    const next: WatchHwItem[] = [];
    for (let i = 0; i < this.hwItems.length; i++) {
      if (this.hwItems[i].id !== item.id) {
        next.push(this.hwItems[i]);
      }
    }
    this.hwItems = next;
    this.flash('已完成 · ' + item.title);
    const result: MarksUpdateResult = await Services.marks.setMark(MarkKind.HW, item.id, true);
    if (!result.ok) {
      this.flash('网络不佳，已本机记录稍后补发');
    }
  }

  private async completeNotice(key: string): Promise<void> {
    this.buzz(15);
    const next: WatchNtItem[] = [];
    for (let i = 0; i < this.ntItems.length; i++) {
      if (this.ntItems[i].key !== key) {
        next.push(this.ntItems[i]);
      }
    }
    this.ntItems = next;
    this.ntPending = Math.max(0, this.ntPending - 1);
    this.detailOpen = false;
    this.flash('已标记处理');
    await Services.marks.setMark(MarkKind.NT_DONE, key, true);
  }

  private openDetail(key: string): void {
    const card: NoticeCard | undefined = this.ntMap.get(key);
    if (card === undefined) {
      return;
    }
    this.buzz(10);
    this.detailKey = key;
    this.detailTitle = card.title;
    this.detailStatus = card.statusLabel;
    this.detailSummary = card.aiSummary.length > 0 ? card.aiSummary : card.summary;
    this.detailPoints = card.points;
    this.detailOpen = true;
  }

  private closeDetail(): void {
    this.detailOpen = false;
  }

  private openMenu(): void {
    this.buzz(15);
    this.menuOpen = true;
  }

  private closeMenu(): void {
    this.menuOpen = false;
  }

  private askLogout(): void {
    this.menuOpen = false;
    this.logoutOpen = true;
  }

  private nextSession(): SessionInfo | undefined {
    return this.plan.hasData ? this.plan.next : undefined;
  }

  private nextLabel(): string {
    if (!this.plan.hasData) {
      return this.ttReady ? '课表未同步' : '正在同步';
    }
    if (this.plan.today.length === 0) {
      const next: SessionInfo | undefined = this.plan.next;
      return next !== undefined ? next.name : '今天没课';
    }
    const next: SessionInfo | undefined = this.plan.next;
    if (next === undefined) {
      return '今日课程已结束';
    }
    return next.name;
  }

  private nextMeta(): string {
    const next: SessionInfo | undefined = this.nextSession();
    if (next === undefined) {
      return this.plan.hasData ? '' : '在手机上打开课表';
    }
    const room: string = next.room.length > 0 ? ' · ' + next.room : '';
    return next.dayText + ' ' + next.startText + room;
  }

  private countdownMinutes(): number {
    const next: SessionInfo | undefined = this.nextSession();
    if (next === undefined || next.startAt <= 0) {
      return -1;
    }
    return WatchLogic.minutesUntil(next.startAt, Date.now());
  }

  private ringValue(): number {
    const min: number = this.countdownMinutes();
    if (min < 0) {
      return this.plan.hasData ? 100 : 0;
    }
    // 以 7 天为满环：越接近上课，环越满
    const ratio: number = Math.min(1, min / (7 * 24 * 60));
    return Math.round((1 - ratio) * 100);
  }

  private countdownMain(): string {
    const min: number = this.countdownMinutes();
    if (min < 0) {
      return '—';
    }
    if (min <= 0) {
      return '上课中';
    }
    if (min >= 24 * 60) {
      return Math.floor(min / (24 * 60)) + '天';
    }
    if (min >= 60) {
      return Math.floor(min / 60) + 'h' + (min % 60 > 0 ? (min % 60) + 'm' : '');
    }
    return '' + min;
  }

  private countdownUnit(): string {
    const min: number = this.countdownMinutes();
    if (min < 0) {
      return this.ttReady ? '无课程' : '同步中';
    }
    if (min <= 0) {
      return '进行中';
    }
    if (min >= 24 * 60) {
      return '后上课';
    }
    return min >= 60 ? '后上课' : '分钟后';
  }

  private sessionColor(state: string): string {
    if (state === SessionState.ONGOING) {
      return '#E8A87C';
    }
    if (state === SessionState.DONE) {
      return '#5A5F63';
    }
    return Tokens.MIST_TEAL;
  }

  private toneColor(tone: string): string {
    if (tone === 'urgent' || tone === 'overdue') {
      return '#E8A87C';
    }
    if (tone === 'warn') {
      return '#E0C080';
    }
    return '#9AA0A6';
  }

  private syncText(): string {
    if (this.syncing) {
      return '同步中…';
    }
    if (this.lastSync <= 0) {
      return '点按刷新';
    }
    return '更新 ' + WatchLogic.clock(this.lastSync);
  }

  private powerTone(): string {
    if (this.powerState === 'low') {
      return '#E8A87C';
    }
    if (this.powerState === 'warn') {
      return '#E0C080';
    }
    return '#FFFFFF';
  }

  @Builder
  pageTitle(title: string, meta: string) {
    Row() {
      Text(title)
        .fontSize(this.px(12))
        .fontColor('#9AA0A6')
        .maxLines(1)
      Blank()
      Text(meta)
        .fontSize(this.px(9))
        .fontColor('#6E747A')
        .maxLines(1)
    }
    .width('100%')
    .padding({ bottom: this.px(4) })
  }

  @Builder
  todayHeader() {
    this.pageTitle('今天' + (this.plan.week !== undefined ? ' · 第 ' + this.plan.week + ' 周' : ''),
      this.plan.today.length + ' 节课')
  }

  @Builder
  hwHeader() {
    this.pageTitle('作业待交', this.hwItems.length + ' 项')
  }

  @Builder
  ntHeader() {
    this.pageTitle('通知待处理' + (this.ntUrgent > 0 ? ' · ' + this.ntUrgent + ' 紧急' : ''),
      this.ntItems.length + ' 条')
  }

  @Builder
  powerHeader() {
    this.pageTitle('宿舍电费', this.powerLabel.length > 0 ? this.powerLabel : '未关注')
  }

  @Builder
  moreHeader() {
    this.pageTitle('更多', this.syncText())
  }

  @Builder
  hintBlock(main: string, sub: string) {
    Column() {
      Text(main)
        .fontSize(this.px(12))
        .fontColor('#6E747A')
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text(sub)
        .fontSize(this.px(9))
        .fontColor('#4E5357')
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  todayEmpty() {
    this.hintBlock(this.plan.hasData ? '今天没有课' : (this.ttReady ? '课表未同步' : '正在同步课表'),
      '点按页面刷新')
  }

  @Builder
  hwEmpty() {
    this.hintBlock(this.hwReady ? '作业都完成了' : '正在同步作业', '点按页面刷新')
  }

  @Builder
  ntEmpty() {
    this.hintBlock(this.ntReady ? '暂无待处理通知' : '正在同步通知', '点按页面刷新')
  }

  @Builder
  powerEmpty() {
    this.hintBlock(this.powerReady ? '在手机上选择关注宿舍' : '正在同步电费', '点按页面刷新')
  }

  @Builder
  pageToday() {
    Column() {
      Row() {
        Text('今天' + (this.plan.week !== undefined ? ' · 第 ' + this.plan.week + ' 周' : ''))
          .fontSize(this.px(12))
          .fontColor('#9AA0A6')
          .maxLines(1)
        Blank()
        Text(this.plan.today.length + ' 节课')
          .fontSize(this.px(9))
          .fontColor('#6E747A')
          .maxLines(1)
      }
      .width('100%')
      .padding({ bottom: this.px(4) })

      Stack() {
        Progress({ value: this.ringValue(), total: 100, type: ProgressType.Ring })
          .width(this.px(96))
          .height(this.px(96))
          .color(Tokens.MIST_TEAL)
          .backgroundColor('#1E2A32')
          .style({ strokeWidth: this.px(6) })
        Column() {
          Text(this.countdownMain())
            .fontSize(this.px(26))
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
          Text(this.countdownUnit())
            .fontSize(this.px(9))
            .fontColor('#9AA0A6')
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(this.px(100))
      .margin({ top: this.px(2) })

      Text(this.nextLabel())
        .fontSize(this.px(15))
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: this.px(4) })
      Text(this.nextMeta())
        .fontSize(this.px(10))
        .fontColor('#9AA0A6')
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')

      if (this.plan.today.length > 0) {
        List({ space: this.px(3) }) {
          ForEach(this.plan.today, (s: SessionInfo, i: number) => {
            ListItem() {
              Row() {
                Text(s.startText + '-' + s.endText)
                  .fontSize(this.px(9))
                  .fontColor(this.sessionColor(s.state))
                  .width(this.px(58))
                  .maxLines(1)
                Text(s.name)
                  .fontSize(this.px(11))
                  .fontColor(s.state === SessionState.DONE ? '#5A5F63' : '#EAE5D9')
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (s.room.length > 0) {
                  Text(s.room)
                    .fontSize(this.px(9))
                    .fontColor('#6E747A')
                    .maxLines(1)
                }
              }
              .width('100%')
              .padding({ top: this.px(3), bottom: this.px(3) })
            }
          }, (s: SessionInfo, i: number) => 's_' + i + '_' + s.name + '_' + this.dataVersion)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: this.px(4) })
        .scrollBar(BarState.Off)
        .clip(true)
        .focusable(true)
        .focusOnTouch(true)
      } else {
        Column() {
          Text(this.plan.hasData ? '今天没有课' : (this.ttReady ? '课表未同步' : '正在同步课表'))
            .fontSize(this.px(12))
            .fontColor('#6E747A')
            .textAlign(TextAlign.Center)
            .maxLines(2)
          Text('点按页面刷新')
            .fontSize(this.px(9))
            .fontColor('#4E5357')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad(), top: this.px(64), bottom: this.px(58) })
    .onClick(() => {
      if (!this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        this.refresh();
      }
    })
  }

  @Builder
  pageHomework() {
    Column() {
      Row() {
        Text('作业待交')
          .fontSize(this.px(12))
          .fontColor('#9AA0A6')
        Blank()
        Text(this.hwItems.length + ' 项')
          .fontSize(this.px(9))
          .fontColor('#6E747A')
      }
      .width('100%')
      .padding({ bottom: this.px(4) })
      if (this.hwItems.length > 0) {
        List({ space: this.px(4) }) {
          ForEach(this.hwItems, (item: WatchHwItem, i: number) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.title)
                    .fontSize(this.px(11))
                    .fontColor('#EAE5D9')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.sub)
                    .fontSize(this.px(9))
                    .fontColor(this.toneColor(item.tone))
                    .maxLines(1)
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(this.px(15))
                    .fontWeight(FontWeight.Medium)
                    .fontColor(['#9BC9BB'])
                }
                .width(this.px(30))
                .height(this.px(30))
                .border({ width: 1, color: '#33424A' })
                .borderRadius(15)
              }
              .width('100%')
              .padding(this.px(5))
              .backgroundColor('#151A1E')
              .borderRadius(this.px(9))
              .onClick(() => {
                this.completeHomework(item);
              })
            }
          }, (item: WatchHwItem, i: number) => 'hw_' + item.id + '_' + this.dataVersion)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: this.px(2) })
        .scrollBar(BarState.Off)
        .clip(true)
        .focusable(true)
        .focusOnTouch(true)
      } else {
        Column() {
          Text(this.hwReady ? '作业都完成了' : '正在同步作业')
            .fontSize(this.px(12))
            .fontColor('#6E747A')
            .textAlign(TextAlign.Center)
          Text('点按页面刷新')
            .fontSize(this.px(9))
            .fontColor('#4E5357')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad(), top: this.px(64), bottom: this.px(58) })
    .onClick(() => {
      if (!this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        this.refresh();
      }
    })
  }

  @Builder
  pageNotices() {
    Column() {
      Row() {
        Text('通知待处理' + (this.ntUrgent > 0 ? ' · ' + this.ntUrgent + ' 紧急' : ''))
          .fontSize(this.px(12))
          .fontColor('#9AA0A6')
          .maxLines(1)
        Blank()
        Text(this.ntItems.length + ' 条')
          .fontSize(this.px(9))
          .fontColor('#6E747A')
      }
      .width('100%')
      .padding({ bottom: this.px(4) })
      if (this.ntItems.length > 0) {
        List({ space: this.px(4) }) {
          ForEach(this.ntItems, (item: WatchNtItem, i: number) => {
            ListItem() {
              Row() {
                if (item.urgent) {
                  Rect()
                    .width(3)
                    .height(this.px(28))
                    .fill('#E8A87C')
                    .radius(2)
                    .margin({ right: this.px(6) })
                }
                Column() {
                  Text(item.title)
                    .fontSize(this.px(11))
                    .fontColor(item.urgent ? '#F0D9C8' : '#EAE5D9')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.sub)
                    .fontSize(this.px(9))
                    .fontColor(item.urgent ? '#E8A87C' : '#6E747A')
                    .maxLines(1)
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(this.px(14))
        .fontColor(['#4E5357'])
              }
              .width('100%')
              .padding(this.px(5))
              .backgroundColor('#151A1E')
              .borderRadius(this.px(9))
              .onClick(() => {
                this.openDetail(item.key);
              })
            }
          }, (item: WatchNtItem, i: number) => 'nt_' + item.key + '_' + this.dataVersion)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: this.px(2) })
        .scrollBar(BarState.Off)
        .clip(true)
        .focusable(true)
        .focusOnTouch(true)
      } else {
        Column() {
          Text(this.ntReady ? '暂无待处理通知' : '正在同步通知')
            .fontSize(this.px(12))
            .fontColor('#6E747A')
            .textAlign(TextAlign.Center)
          Text('点按页面刷新')
            .fontSize(this.px(9))
            .fontColor('#4E5357')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad(), top: this.px(64), bottom: this.px(58) })
    .onClick(() => {
      if (!this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        this.refresh();
      }
    })
  }

  @Builder
  pagePower() {
    Column() {
      Row() {
        Text('宿舍电费')
          .fontSize(this.px(12))
          .fontColor('#9AA0A6')
        Blank()
        Text(this.powerLabel.length > 0 ? this.powerLabel : '未关注')
          .fontSize(this.px(9))
          .fontColor('#6E747A')
          .maxLines(1)
      }
      .width('100%')
      .padding({ bottom: this.px(4) })
      Stack() {
        Progress({ value: this.powerRing(), total: 100, type: ProgressType.Ring })
          .width(this.px(112))
          .height(this.px(112))
          .color(this.powerState === 'low' ? '#E8A87C' : Tokens.MIST_TEAL)
          .backgroundColor('#1E2A32')
          .style({ strokeWidth: this.px(7) })
        Column() {
          Row() {
            Text(this.powerQ.length > 0 ? this.powerQ : '—')
              .fontSize(this.px(26))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.powerTone())
              .maxLines(1)
            Text(this.powerUnit)
              .fontSize(this.px(10))
              .fontColor('#9AA0A6')
              .margin({ left: 2, top: this.px(8) })
          }
          Text(this.powerStateText())
            .fontSize(this.px(9))
            .fontColor(this.powerTone())
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(this.px(116))
      .margin({ top: this.px(1) })

      if (this.powerBars.length > 0) {
        Row({ space: 2 }) {
          ForEach(this.powerBars, (h: number, i: number) => {
            Rect()
              .width(this.px(3))
              .height(h)
              .fill(i === this.powerBars.length - 1 ? '#7FC4B4' : '#2E4A48')
              .radius(2)
          }, (h: number, i: number) => 'bar_' + i)
        }
        .width('100%')
        .height(this.px(32))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Bottom)
      }

      if (this.powerDrop.length > 0) {
        Text(this.powerDrop)
          .fontSize(this.px(10))
          .fontColor('#B9C7CB')
          .maxLines(1)
      }
      if (this.powerDays.length > 0) {
        Text(this.powerDays)
          .fontSize(this.px(9))
          .fontColor('#9AA0A6')
          .maxLines(1)
      }
      if (this.powerQ.length === 0) {
        Column() {
          Text(this.powerReady ? '在手机上选择关注宿舍' : '正在同步电费')
            .fontSize(this.px(12))
            .fontColor('#6E747A')
            .textAlign(TextAlign.Center)
          Text('点按页面刷新')
            .fontSize(this.px(9))
            .fontColor('#4E5357')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      Blank()
      Text(this.powerUpd.length > 0 ? '更新 ' + this.powerUpd : this.syncText())
        .fontSize(this.px(8))
        .fontColor('#4E5357')
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad(), top: this.px(64), bottom: this.px(58) })
    .onClick(() => {
      if (!this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        this.refresh();
      }
    })
  }

  @Builder
  actionRow(icon: Resource, title: string, sub: string, color: string, onTap: () => void) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize(this.px(16))
          .fontWeight(FontWeight.Medium)
          .fontColor([color])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      }
      .width(this.px(28))
      .height(this.px(20))
      Column() {
        Text(title)
          .fontSize(this.px(12))
          .fontColor('#EAE5D9')
        Text(sub)
          .fontSize(this.px(8))
          .fontColor('#6E747A')
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(this.px(14))
        .fontColor(['#4E5357'])
    }
    .width('100%')
    .padding(this.px(6))
    .backgroundColor('#151A1E')
    .borderRadius(this.px(9))
    .margin({ top: this.px(4) })
    .onClick(onTap)
  }

  @Builder
  overviewRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.bell'))
          .fontSize(this.px(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(['#9BC9BB'])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      }
      .width(this.px(28))
      .height(this.px(20))
      Column() {
        Text('待处理概览')
          .fontSize(this.px(12))
          .fontColor('#EAE5D9')
        Text(this.ntItems.length + ' 通知 · ' + this.hwItems.length + ' 作业')
          .fontSize(this.px(8))
          .fontColor('#6E747A')
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(this.px(14))
        .fontColor(['#4E5357'])
    }
    .width('100%')
    .padding(this.px(6))
    .backgroundColor('#151A1E')
    .borderRadius(this.px(9))
    .margin({ top: this.px(4) })
    .onClick(() => {
      this.page = 2;
    })
  }

  @Builder
  pageMore() {
    Column() {
      Row() {
        Text('更多')
          .fontSize(this.px(12))
          .fontColor('#9AA0A6')
        Blank()
        Text(this.syncText())
          .fontSize(this.px(9))
          .fontColor('#6E747A')
      }
      .width('100%')
      .padding({ bottom: this.px(4) })
      Row() {
        Circle()
          .width(this.px(26))
          .height(this.px(26))
          .fill('#1E2A32')
        Column() {
          Text(this.userName.length > 0 ? this.userName : '已登录')
            .fontSize(this.px(12))
            .fontColor('#FFFFFF')
            .maxLines(1)
          Text(this.offline ? '离线 · 显示缓存' : '已连接班级云')
            .fontSize(this.px(9))
            .fontColor(this.offline ? '#E8A87C' : '#7FC4B4')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: this.px(6) })
        .layoutWeight(1)
      }
      .width('100%')
      .padding(this.px(6))
      .backgroundColor('#101418')
      .borderRadius(this.px(9))

      this.actionRow($r('sys.symbol.arrow_clockwise'), '刷新全部', '作业 / 通知 / 课表 / 电费', Tokens.MIST_TEAL, () => {
        this.refresh();
      })
      this.overviewRow()
      this.actionRow($r('sys.symbol.xmark'), '退出登录', '需要重新输入学号与姓名', '#E8A87C', () => {
        this.askLogout();
      })
      Blank()
      Text('枫丹工具箱 · 1.0.10')
        .fontSize(this.px(8))
        .fontColor('#4E5357')
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad(), top: this.px(64), bottom: this.px(58) })
  }

  private powerRing(): number {
    const value: number = Number(this.powerQ);
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    if (this.powerState === 'low') {
      return Math.max(4, Math.round(Math.min(100, value)));
    }
    return Math.round(Math.min(100, Math.max(4, value)));
  }

  private powerStateText(): string {
    if (this.powerQ.length === 0) {
      return this.powerReady ? '未关注' : '同步中';
    }
    if (this.powerState === 'ok') {
      return '充足';
    }
    if (this.powerState === 'warn') {
      return '偏低';
    }
    if (this.powerState === 'low') {
      return '低电';
    }
    return '';
  }

  @Builder
  dots() {
    Row({ space: 5 }) {
      ForEach([0, 1, 2, 3, 4], (i: number) => {
        Circle()
          .width(this.page === i ? 7 : 5)
          .height(this.page === i ? 7 : 5)
          .fill(this.page === i ? Tokens.MIST_TEAL : '#4A4A4A')
      }, (i: number) => 'dot_' + i)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: 3 })
  }

  @Builder
  menuOverlay() {
    Column() {
      Text('操作')
        .fontSize(this.px(12))
        .fontColor('#9AA0A6')
        .margin({ bottom: this.px(4) })
      this.actionRow($r('sys.symbol.arrow_clockwise'), '刷新全部', this.syncText(), Tokens.MIST_TEAL, () => {
        this.closeMenu();
        this.refresh();
      })
      this.actionRow($r('sys.symbol.arrow_left'), '取消', '返回当前页面', '#9AA0A6', () => {
        this.closeMenu();
      })
    }
    .width('76%')
    .padding(this.px(8))
    .backgroundColor('#101418')
    .borderRadius(this.px(14))
    .border({ width: 1, color: '#2A3035' })
  }

  @Builder
  detailOverlay() {
    Column() {
      Row() {
        Text(this.detailStatus)
          .fontSize(this.px(9))
          .fontColor('#9BC9BB')
          .maxLines(1)
        Blank()
        Text('关闭')
          .fontSize(this.px(10))
          .fontColor('#6E747A')
      }
      .width('100%')
      Text(this.detailTitle)
        .fontSize(this.px(14))
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(3)
        .margin({ top: this.px(3) })
      Scroll() {
        Column() {
          if (this.detailSummary.length > 0) {
            Text(this.detailSummary)
              .fontSize(this.px(10))
              .fontColor('#B9C7CB')
              .width('100%')
              .margin({ top: this.px(4) })
          }
          ForEach(this.detailPoints, (p: string, i: number) => {
            Text('· ' + p)
              .fontSize(this.px(9))
              .fontColor('#8FA3A8')
              .width('100%')
              .margin({ top: this.px(2) })
          }, (p: string, i: number) => 'dp_' + i)
          Blank().height(this.px(4))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
        .clip(true)
      .focusable(true)
      .focusOnTouch(true)

      Row({ space: this.px(6) }) {
        Text('稍后')
          .fontSize(this.px(11))
          .fontColor('#9AA0A6')
          .layoutWeight(1)
          .height(this.px(30))
          .textAlign(TextAlign.Center)
          .backgroundColor('#1C2126')
          .borderRadius(this.px(15))
          .onClick(() => {
            this.closeDetail();
          })
        Text('标记已处理')
          .fontSize(this.px(11))
          .fontColor('#12332C')
          .layoutWeight(1)
          .height(this.px(30))
          .textAlign(TextAlign.Center)
          .backgroundColor('#9BC9BB')
          .borderRadius(this.px(15))
          .onClick(() => {
            this.completeNotice(this.detailKey);
          })
      }
      .width('100%')
      .margin({ top: this.px(4) })
    }
    .width('70%')
    .height('62%')
    .padding(this.px(9))
    .backgroundColor('#101418')
    .borderRadius(this.px(16))
    .border({ width: 1, color: '#2A3035' })
  }

  @Builder
  logoutOverlay() {
    Column() {
      Text('退出登录？')
        .fontSize(this.px(14))
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
      Text('退出后需要重新验证学号与姓名')
        .fontSize(this.px(9))
        .fontColor('#9AA0A6')
        .margin({ top: this.px(3) })
      Row({ space: this.px(6) }) {
        Text('取消')
          .fontSize(this.px(11))
          .fontColor('#9AA0A6')
          .layoutWeight(1)
          .height(this.px(30))
          .textAlign(TextAlign.Center)
          .backgroundColor('#1C2126')
          .borderRadius(this.px(15))
          .onClick(() => {
            this.logoutOpen = false;
          })
        Text('退出')
          .fontSize(this.px(11))
          .fontColor('#2A1A12')
          .layoutWeight(1)
          .height(this.px(30))
          .textAlign(TextAlign.Center)
          .backgroundColor('#E8A87C')
          .borderRadius(this.px(15))
          .onClick(() => {
            this.logoutOpen = false;
            this.onLogout();
          })
      }
      .width('100%')
      .margin({ top: this.px(10) })
    }
    .width('72%')
    .padding(this.px(10))
    .backgroundColor('#101418')
    .borderRadius(this.px(16))
    .border({ width: 1, color: '#2A3035' })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper(this.controller) {
        Column() {
          this.pageToday()
        }
        Column() {
          this.pageHomework()
        }
        Column() {
          this.pageNotices()
        }
        Column() {
          this.pagePower()
        }
        Column() {
          this.pageMore()
        }
      }
      .width('100%')
      .height('100%')
      .index(this.page)
      .loop(false)
      .indicator(false)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
      .onChange((index: number) => {
        this.page = index;
      })

      Column() {
        this.dots()
        Text('滑动翻页 · 长按操作')
          .fontSize(this.px(8))
          .fontColor('#5A5F63')
          .maxLines(1)
      }
      .width('100%')
      .padding({ bottom: this.px(14) })
      .hitTestBehavior(HitTestMode.None)

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(this.px(9))
          .fontColor('#EAE5D9')
          .backgroundColor('#2A3035')
          .borderRadius(this.px(10))
          .padding({ left: this.px(8), right: this.px(8), top: this.px(3), bottom: this.px(3) })
          .margin({ bottom: this.px(28) })
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.offline && !this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        Column() {
          Text('离线 · 显示缓存')
            .fontSize(this.px(9))
            .fontColor('#E8A87C')
            .padding({ left: 9, right: 9, top: 2, bottom: 2 })
            .backgroundColor('#1C1C1E')
            .borderRadius(9)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.px(6) })
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.menuOpen) {
        Column() {
          this.menuOverlay()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#99000000')
        .onClick(() => {
          this.closeMenu();
        })
        .transition(TransitionEffect.OPACITY)
      }

      if (this.detailOpen) {
        Column() {
          this.detailOverlay()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#99000000')
        .transition(TransitionEffect.OPACITY)
      }

      if (this.logoutOpen) {
        Column() {
          this.logoutOverlay()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#B3000000')
        .onClick(() => {
          this.logoutOpen = false;
        })
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .gesture(LongPressGesture().onAction(() => {
      if (!this.menuOpen && !this.detailOpen && !this.logoutOpen) {
        this.openMenu();
      }
    }))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w: number = Number(newValue.width);
      const h: number = Number(newValue.height);
      if (w > 0 && h > 0 && (Math.abs(w - this.screenW) > 1 || Math.abs(h - this.screenH) > 1)) {
        this.screenW = w;
        this.screenH = h;
      }
    })
  }
}

function toneOf(tone: HomeworkDueTone): string {
  if (tone === HomeworkDueTone.URGENT) {
    return 'urgent';
  }
  if (tone === HomeworkDueTone.OVERDUE) {
    return 'overdue';
  }
  if (tone === HomeworkDueTone.WARN) {
    return 'warn';
  }
  if (tone === HomeworkDueTone.SAFE) {
    return 'safe';
  }
  return 'neutral';
}
