import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import {
  Course,
  SessionInfo,
  SessionState,
  TtPeriods,
  TtPlan,
  TtSnapshot
} from '../../data/timetable/TimetableModels';
import { TtCalendar } from '../../data/timetable/TtCalendar';
import { TimetableRepository, TtResult, TtSource } from '../../data/timetable/TimetableRepository';
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { ShareSpecs } from '../../features/share/ShareSpecs';
import { ExportCardSpec, ExportParam } from '../../features/export/ExportCard';
import { ExportCardView } from '../components/ExportCardView';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';

const ROW_H: number = 46;
const TIME_W: number = 46;
const JW_URL: string = 'http://210.34.74.77/sso.jsp';
const ALL_DAYS: number[] = [0, 1, 2, 3, 4, 5, 6];
const WEEK_PERIODS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/** 与小程序一致的 16 组课程色板（浅色底 + 深色字）。 */
const COURSE_BG: string[] = [
  '#DCE6F0', '#E7D9EC', '#DDEBDD', '#F1DDD9',
  '#F0E5CD', '#D9E3E8', '#EEDCE4', '#DFE6CD',
  '#D8E7E4', '#E8DBD2', '#DEDBEC', '#F2E3D4',
  '#D5E3F2', '#E9E2C9', '#E5D8DE', '#D3E5DB'
];
const COURSE_FG: string[] = [
  '#3D5872', '#5A4368', '#3F6047', '#6E4441',
  '#66572F', '#3E5A63', '#6B4356', '#546132',
  '#35605A', '#644A3A', '#474569', '#6D4F36',
  '#3B5578', '#625A33', '#5D4250', '#39604E'
];

/** 「全部课程」分组项（与小程序 groups 同口径）。 */
class TtGroupItem {
  name: string = '';
  pills: string[] = [];
  teachers: string[] = [];
  rooms: string[] = [];
  meta: string = '';
  bg: string = '';
  fg: string = '';
  course: Course = new Course();
}

/**
 * 课表工具：与微信小程序同款布局（单卡片 + 周/日视图 + 下一节 + 全部课程）。
 *
 * 布局：顶部周导航与周/日分段 → 操作行 → 下一节横幅 → 周表/日表 → 全部课程 → 底部说明。
 * 动效：周视图左右跟手滑动并飞出飞入切周、分段指示块滑动、日视图切换与列表项淡入上移、
 * 课程块/卡片按压回弹、全部课程展开收起。
 *
 * 数据：个人课表（`userdata.tt.ttUseMine + ttLocal`）优先，其次 `site_assets id=tt`；
 * 周次/单双周/下一节全部由 `TtCalendar` 计算。
 */
@Component
export struct TimetableScreen {
  onClose: () => void = () => {
  };
  onOpenMap: (room: string) => void = () => {};

  @State private snapshot: TtSnapshot | undefined = undefined;
  @State private plan: TtPlan = new TtPlan();
  @State private weekOffset: number = 0;
  @State private dayIdx: number = 0;
  @State private viewMode: string = 'week';
  @State private loading: boolean = true;
  @State private refreshing: boolean = false;
  private scroller: Scroller = new Scroller();
  @State private errorMsg: string = '';
  @State private source: string = '';
  @State private now: number = Date.now();
  @State private gridWidth: number = 0;
  @State private dragX: number = 0;
  @State private weekBusy: boolean = false;
  @State private detailCourse: Course | undefined = undefined;
  @State private detailOpen: boolean = false;
  @State private detailDate: string = '';
  @State private allOpen: boolean = false;
  @State private groups: TtGroupItem[] = [];
  private shareSpec: ExportCardSpec = new ExportCardSpec();

  private clockTimer: number = -1;
  private currentSession(): SessionInfo | undefined {
    return this.plan.today.find((s: SessionInfo) => s.state === SessionState.ONGOING) ?? this.plan.next;
  }
  aboutToDisappear(): void {
    clearInterval(this.clockTimer);
  }
  aboutToAppear(): void {
    this.clockTimer = setInterval(() => {
      this.now = Date.now();
      this.plan = TtCalendar.plan(this.snapshot, this.now);
    }, 30000);
    this.dayIdx = TtCalendar.dayIndex(new Date(Date.now()));
    this.reload(false);
  }

  private async reload(force: boolean): Promise<void> {
    this.loading = this.snapshot === undefined;
    this.errorMsg = '';
    const result: TtResult = await Services.timetable.load(force);
    this.now = Date.now();
    this.snapshot = result.snapshot;
    this.plan = TtCalendar.plan(result.snapshot, this.now);
    this.groups = this.buildGroups(result.snapshot !== undefined ? result.snapshot.c : []);
    this.source = result.source === TtSource.PERSONAL ? '我的课表'
      : (result.source === TtSource.CACHE ? '本机缓存' : '班级课表');
    if (!result.ok) {
      this.errorMsg = result.message;
    } else if (result.message.length > 0) {
      this.errorMsg = result.message;
    }
    this.loading = false;
  }

  private async pullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.reload(true);
    this.refreshing = false;
  }

  private baseWeek(): number {
    return this.plan.week !== undefined ? this.plan.week : 1;
  }

  private displayWeek(): number {
    const week: number = this.baseWeek() + this.weekOffset;
    return week < 1 ? 1 : week;
  }

  private termStart(): Date | undefined {
    return this.snapshot !== undefined ? TtCalendar.parseTermStart(this.snapshot.termStart()) : undefined;
  }

  private monday(): Date {
    const term: Date | undefined = this.termStart();
    const base: Date = term !== undefined ? term : new Date(this.now);
    return TtCalendar.mondayOfWeek(base, this.displayWeek());
  }

  private dateAt(day: number): Date {
    const monday: Date = this.monday();
    return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + day, 0, 0, 0);
  }

  private selectedDate(): Date {
    return this.dateAt(this.dayIdx);
  }

  private sessions(): SessionInfo[] {
    if (this.snapshot === undefined) {
      return [];
    }
    return TtCalendar.sessionsOn(this.snapshot.c, this.termStart(), this.selectedDate(), this.now);
  }

  private coursesOf(day: number): Course[] {
    if (this.snapshot === undefined) {
      return [];
    }
    return TtCalendar.coursesOn(this.snapshot.c, this.termStart(), this.dateAt(day));
  }

  private weekLabel(): string {
    if (this.plan.week === undefined) {
      return this.snapshot !== undefined && this.snapshot.c.length > 0 ? '学期未开始' : '—';
    }
    return '第 ' + this.displayWeek() + ' 周';
  }

  private rangeText(): string {
    const monday: Date = this.monday();
    const sunday: Date = this.dateAt(6);
    return (monday.getMonth() + 1) + '-' + monday.getDate() + ' ~ '
      + (sunday.getMonth() + 1) + '-' + sunday.getDate();
  }

  private todayIdx(): number {
    return TtCalendar.dayIndex(new Date(this.now));
  }

  /** 周视图只展示有课的周末列（与小程序一致：5/6/7 天自适应列宽）。 */
  private activeDays(): number[] {
    const out: number[] = [0, 1, 2, 3, 4];
    if (this.coursesOf(5).length > 0) {
      out.push(5);
    }
    if (this.coursesOf(6).length > 0) {
      out.push(6);
    }
    return out;
  }

  private colWidth(): number {
    const days: number = this.activeDays().length;
    if (this.gridWidth <= TIME_W || days <= 0) {
      return 42;
    }
    return (this.gridWidth - TIME_W) / days;
  }

  private colorIndexOf(name: string): number {
    let hash: number = 0;
    for (let i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.charCodeAt(i)) % 9973;
    }
    return hash % COURSE_BG.length;
  }

  private courseBg(name: string): string {
    return COURSE_BG[this.colorIndexOf(name)];
  }

  private courseFg(name: string): string {
    return COURSE_FG[this.colorIndexOf(name)];
  }

  private metaOf(course: Course): string {
    const parts: string[] = [];
    if (course.teacher.trim().length > 0) {
      parts.push(course.teacher.trim());
    }
    if (course.room.trim().length > 0) {
      parts.push(course.room.trim());
    }
    return parts.join(' · ');
  }

  private weeksText(course: Course): string {
    const base: string = course.weeks.trim().length > 0 ? course.weeks + ' 周' : '全学期';
    if (course.parity === 'odd') {
      return base + ' · 单周';
    }
    if (course.parity === 'even') {
      return base + ' · 双周';
    }
    return base;
  }

  private buildGroups(courses: Course[]): TtGroupItem[] {
    const out: TtGroupItem[] = [];
    const map: Map<string, TtGroupItem> = new Map<string, TtGroupItem>();
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      const key: string = course.name.trim().length > 0 ? course.name.trim() : '课程';
      let group: TtGroupItem | undefined = map.get(key);
      if (group === undefined) {
        group = new TtGroupItem();
        group.name = key;
        group.course = course;
        group.bg = this.courseBg(key);
        group.fg = this.courseFg(key);
        map.set(key, group);
        out.push(group);
      }
      const pill: string = TtPeriods.DAY_LABELS[course.day] + ' ' + course.start + '-' + course.end;
      if (group.pills.indexOf(pill) < 0) {
        group.pills.push(pill);
      }
      if (course.teacher.trim().length > 0 && group.teachers.indexOf(course.teacher.trim()) < 0) {
        group.teachers.push(course.teacher.trim());
      }
      if (course.room.trim().length > 0 && group.rooms.indexOf(course.room.trim()) < 0) {
        group.rooms.push(course.room.trim());
      }
    }
    for (let i = 0; i < out.length; i++) {
      const group: TtGroupItem = out[i];
      const parts: string[] = [];
      if (group.teachers.length > 0) {
        parts.push(group.teachers.join('、'));
      }
      if (group.rooms.length > 0) {
        parts.push(group.rooms.join(' / '));
      }
      group.meta = parts.join(' · ');
    }
    out.sort((a: TtGroupItem, b: TtGroupItem) => {
      const diff: number = a.course.day - b.course.day;
      return diff !== 0 ? diff : (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
    });
    return out;
  }

  private nextTextOf(course: Course): string {
    const term: Date | undefined = this.termStart();
    const today: Date = new Date(this.now);
    for (let offset = 0; offset < 14; offset++) {
      const date: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset, 0, 0, 0);
      if (TtCalendar.dayIndex(date) !== course.day) {
        continue;
      }
      const week: number | undefined = TtCalendar.weekOf(term, date);
      if (!TtCalendar.isActive(course, week)) {
        continue;
      }
      const startAt: number = TtCalendar.at(date, TtPeriods.startText(course.start));
      if (startAt <= this.now) {
        continue;
      }
      return (date.getMonth() + 1) + '-' + date.getDate() + ' '
        + TtPeriods.DAY_LABELS[course.day] + ' 第' + course.start + '-' + course.end + '节';
    }
    return '暂无后续课程';
  }

  private clampDrag(x: number): number {
    const limit: number = this.gridWidth > 0 ? this.gridWidth * 0.6 : 200;
    if (x > limit) {
      return limit;
    }
    if (x < -limit) {
      return -limit;
    }
    return x;
  }

  private weekOpacity(): number {
    const width: number = this.gridWidth > 0 ? this.gridWidth : 300;
    const ratio: number = Math.abs(this.dragX) / width;
    return 1 - Math.min(0.35, ratio * 0.5);
  }

  /** 翻周：旧内容飞出 → 换周 → 新内容从另一侧飞入。 */
  private commitWeek(delta: number): void {
    if (this.weekBusy) {
      return;
    }
    this.weekBusy = true;
    const width: number = this.gridWidth > 0 ? this.gridWidth : 300;
    const out: number = delta > 0 ? -width * 0.45 : width * 0.45;
    this.getUIContext().animateTo({ duration: 150, curve: Motion.ease() }, () => {
      this.dragX = out;
    });
    setTimeout(() => {
      this.weekOffset = this.weekOffset + delta;
      this.dragX = -out;
      this.getUIContext().animateTo({ duration: 230, curve: Motion.ease() }, () => {
        this.dragX = 0;
      });
      setTimeout(() => {
        this.weekBusy = false;
      }, 240);
    }, 160);
  }

  private onWeekSwipeEnd(offsetX: number): void {
    const width: number = this.gridWidth > 0 ? this.gridWidth : 300;
    const threshold: number = Math.min(64, width * 0.18);
    if (offsetX < -threshold) {
      this.commitWeek(1);
    } else if (offsetX > threshold) {
      this.commitWeek(-1);
    } else {
      this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.spring() }, () => {
        this.dragX = 0;
      });
    }
  }

  private switchView(mode: string): void {
    if (this.viewMode === mode) {
      return;
    }
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.viewMode = mode;
      this.dragX = 0;
    });
  }

  private pickDay(index: number): void {
    if (this.dayIdx === index) {
      return;
    }
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.spring() }, () => {
      this.dayIdx = index;
    });
  }

  private toggleAll(): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.allOpen = !this.allOpen;
    });
  }

  private openCourse(course: Course, day: number): void {
    this.detailCourse = course;
    const date: Date = this.dateAt(day);
    this.detailDate = TtPeriods.DAY_LABELS[day] + ' ' + (date.getMonth() + 1) + '-' + date.getDate();
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.detailOpen = true;
    });
  }

  private closeCourse(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.detailOpen = false;
    });
  }

  private openJw(): void {
    const context = AppGlobal.context;
    if (context === undefined) {
      this.errorMsg = '无法打开教务系统';
      return;
    }
    try {
      context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: JW_URL
      }).catch(() => {
        this.errorMsg = '无法打开浏览器';
      });
    } catch (e) {
      this.errorMsg = '无法打开浏览器';
    }
  }

  @Builder
  navButton(label: string, delta: number) {
    Text(label)
      .fontSize(26)
      .fontWeight(FontWeight.Medium)
      .fontColor(Tokens.TEXT_SECONDARY)
      .width(36)
      .height(36)
      .textAlign(TextAlign.Center)
      .backgroundColor(Tokens.CONTROL)
      .border({ width: 0.5, color: Tokens.CARD_EDGE })
      .borderRadius(11)
      .stateStyles({
        pressed: {
          .scale({ x: 0.92, y: 0.92 })
        }
      })
      .animation({ duration: Motion.FAST, curve: Motion.ease() })
      .onClick(() => {
        this.commitWeek(delta);
      })
  }

  @Builder
  segmentControl() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(39)
        .height(28)
        .margin({ left: 3, top: 3 })
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .shadow({ radius: 4, color: '#1A3D4A46', offsetX: 0, offsetY: 1 })
        .translate({ x: this.viewMode === 'week' ? 0 : 39 })
        .animation({ duration: Motion.NORMAL, curve: Motion.spring() })

      Row() {
        Text('周')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.viewMode === 'week' ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY)
          .width(39)
          .height(34)
          .textAlign(TextAlign.Center)
          .animation({ duration: Motion.FAST, curve: Motion.ease() })
          .onClick(() => {
            this.switchView('week');
          })
        Text('日')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.viewMode === 'day' ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY)
          .width(39)
          .height(34)
          .textAlign(TextAlign.Center)
          .animation({ duration: Motion.FAST, curve: Motion.ease() })
          .onClick(() => {
            this.switchView('day');
          })
      }
    }
    .width(84)
    .height(34)
    .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.06))
    .borderRadius(10)
  }

  @Builder
  weekHead() {
    Row() {
      this.navButton('‹', -1)

      Column() {
        Text(this.weekLabel())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.rangeText())
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 6, right: 6 })

      this.navButton('›', 1)
      this.segmentControl()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  pillButton(label: string, accent: boolean) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(accent ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY)
      .height(30)
      .padding({ left: 14, right: 14 })
      .backgroundColor(accent ? Tokens.tint(Tokens.MIST_TEAL, 0.10) : Tokens.CONTROL)
      .border({ width: 0.5, color: accent ? Tokens.tint(Tokens.MIST_TEAL, 0.35) : Tokens.CARD_EDGE })
      .borderRadius(9)
      .stateStyles({
        pressed: {
          .scale({ x: 0.94, y: 0.94 })
        }
      })
      .animation({ duration: Motion.FAST, curve: Motion.ease() })
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      if (this.weekOffset !== 0) {
        Column() {
          this.pillButton('本周', false)
        }
        .transition(Motion.popIn())
        .onClick(() => {
          this.commitWeek(0 - this.weekOffset);
        })
      }

      Column() {
        this.pillButton('分享', false)
      }
      .onClick(() => {
        this.sharePlan();
      })

      Blank()

      Text(this.snapshot !== undefined ? this.snapshot.c.length + ' 门 · ' + this.source : this.source)
        .fontSize(10)
        .fontColor(this.errorMsg.length > 0 ? Tokens.WARM_SAND : Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ top: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  nextCard(session: SessionInfo) {
    Row({ space: 14 }) {
      Column() {
        Text(session.state === SessionState.ONGOING ? '正在上课' : '下一节')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.MIST_TEAL)
        Text(session.startText)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.tint(Tokens.MIST_TEAL, 0.92))
          .margin({ top: 2 })
      }
      .width(64)
      .alignItems(HorizontalAlign.Center)

      Divider()
        .vertical(true)
        .height(38)
        .strokeWidth(0.5)
        .color(Tokens.tint(Tokens.MIST_TEAL, 0.25))

      Column() {
        Text(session.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(session.dayText + ' 第' + session.start + '-' + session.end + '节'
          + (session.room.length > 0 ? ' · ' + session.room : ''))
          .fontSize(11)
          .fontColor(Tokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .linearGradient({
      angle: 135,
      colors: [
        ['#EAF4EF', 0.0],
        ['#F8F1E9', 1.0]
      ]
    })
    .borderRadius(14)
    .margin({ top: 12 })
    .transition(Motion.listItem())
    .onClick(() => {
      const course: Course | undefined = this.findCourseByName(session.name);
      if (course !== undefined) {
        this.openCourse(course, course.day);
      }
    })
  }

  private findCourseByName(name: string): Course | undefined {
    if (this.snapshot === undefined) {
      return undefined;
    }
    for (let i = 0; i < this.snapshot.c.length; i++) {
      if (this.snapshot.c[i].name.trim() === name.trim()) {
        return this.snapshot.c[i];
      }
    }
    return undefined;
  }

  @Builder
  weekHeaderCell(day: number) {
    Column() {
      Text(TtPeriods.DAY_LABELS[day].substring(1))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isToday(day) ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY)
      Row({ space: 3 }) {
        Text('' + this.dateAt(day).getDate())
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isToday(day) ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
        if (this.isToday(day)) {
          Text('今天')
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.MIST_TEAL)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.12))
            .borderRadius(Tokens.RADIUS_PILL)
        }
      }
      .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(38)
    .justifyContent(FlexAlign.Center)
  }

  private isToday(day: number): boolean {
    return this.weekOffset === 0 && this.plan.week !== undefined && day === this.todayIdx();
  }

  @Builder
  courseBlock(course: Course, day: number) {
    Column() {
      Text(course.name)
        .fontSize(Math.max(10, Math.min(15, this.colWidth() / 4.5)))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.courseFg(course.name))
        .maxLines(course.end > course.start ? 4 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (course.room.length > 0 && course.end > course.start) {
        Text(TtCalendar.roomShort(course.room))
          .fontSize(8)
          .fontColor(this.courseFg(course.name))
          .opacity(0.78)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      if (course.end > course.start && this.colWidth() >= 62) {
        Text('第' + course.start + '-' + course.end + '节')
          .fontSize(8)
          .fontColor(this.courseFg(course.name))
          .opacity(0.7)
          .maxLines(1)
          .width('100%')
          .margin({ top: 1 })
      }
    }
    .width(this.colWidth() - 4)
    .height((course.end - course.start + 1) * ROW_H - 4)
    .padding({ left: 3, right: 3, top: 4, bottom: 4 })
    .backgroundColor(this.courseBg(course.name))
    .borderRadius(8)
    .shadow({ radius: 4, color: '#1A3D4A46', offsetX: 0, offsetY: 1 })
    .clip(true)
    .stateStyles({
      pressed: {
        .scale({ x: 0.95, y: 0.95 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 })))
    .onClick(() => {
      this.openCourse(course, day);
    })
  }

  @Builder
  dayColumn(day: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(WEEK_PERIODS, (period: number) => {
          Column()
            .width('100%')
            .height(ROW_H - 2)
            .margin({ top: 1, bottom: 1 })
            .backgroundColor(this.isToday(day) ? Tokens.tint(Tokens.MIST_TEAL, 0.06) : '#FBFCFB')
            .borderRadius(7)
        }, (period: number) => 'cell_' + day + '_' + period)
      }
      .width('100%')
      .height(12 * ROW_H)

      ForEach(this.coursesOf(day), (course: Course, index: number) => {
        Column() {
          this.courseBlock(course, day)
        }
        .position({
          x: 2,
          y: (course.start - 1) * ROW_H + 2
        })
      }, (course: Course, index: number) => 'cb_' + this.weekOffset + '_' + day + '_' + index + '_' + course.name)
    }
    .layoutWeight(1)
    .height(12 * ROW_H)
    .clip(true)
  }

  @Builder
  weekGrid() {
    Column() {
      Row() {
        Text('节次')
          .width(TIME_W)
          .fontSize(9)
          .fontColor(Tokens.TEXT_TERTIARY)
          .textAlign(TextAlign.Center)
        ForEach(this.activeDays(), (day: number) => {
          this.weekHeaderCell(day)
        }, (day: number) => 'wh_' + day)
      }
      .width('100%')

      Row() {
        Column() {
          ForEach(WEEK_PERIODS, (period: number) => {
            Column() {
              Text('' + period)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(Tokens.TEXT_SECONDARY)
              Text(TtPeriods.startText(period))
                .fontSize(8)
                .fontColor(Tokens.TEXT_TERTIARY)
              Text(TtPeriods.endText(period))
                .fontSize(8)
                .fontColor(Tokens.TEXT_TERTIARY)
            }
            .width(TIME_W)
            .height(ROW_H)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F4F7F4')
            .borderRadius(7)
            .margin({ top: 1, bottom: 1 })
          }, (period: number) => 'tp_' + period)
        }
        .width(TIME_W)
        .height(12 * ROW_H)

        ForEach(this.activeDays(), (day: number) => {
          this.dayColumn(day)
        }, (day: number) => 'wd_' + day)
      }
      .width('100%')
      .height(12 * ROW_H)
    }
    .width('100%')
    .translate({ x: this.dragX })
    .opacity(this.weekOpacity())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);
      if (width > 0 && Math.abs(width - this.gridWidth) > 1) {
        this.gridWidth = width;
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 18 })
        .onActionStart(() => {
          this.dragX = 0;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.dragX = this.clampDrag(event.offsetX);
        })
        .onActionEnd((event: GestureEvent) => {
          this.onWeekSwipeEnd(event.offsetX);
        })
    )
  }

  @Builder
  dayChip(index: number) {
    Column() {
      Text(TtPeriods.DAY_LABELS[index].substring(1))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dayIdx === index ? Tokens.MIST_TEAL
          : (index === this.todayIdx() && this.weekOffset === 0 ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY))
      Text('' + this.dateAt(index).getDate())
        .fontSize(9)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ top: 1 })
      if (this.coursesOf(index).length > 0) {
        Column()
          .width(4)
          .height(4)
          .backgroundColor(Tokens.MIST_TEAL)
          .borderRadius(2)
          .margin({ top: 3 })
      } else {
        Column()
          .height(4)
          .margin({ top: 3 })
      }
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.dayIdx === index ? Tokens.tint(Tokens.MIST_TEAL, 0.10) : Tokens.CONTROL)
    .border({
      width: this.dayIdx === index ? 1 : 0.5,
      color: this.dayIdx === index ? Tokens.tint(Tokens.MIST_TEAL, 0.40) : Tokens.CARD_EDGE
    })
    .borderRadius(12)
    .stateStyles({
      pressed: {
        .scale({ x: 0.94, y: 0.94 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .onClick(() => {
      this.pickDay(index);
    })
  }

  @Builder
  dayCourseCard(course: Course) {
    Row() {
      Column()
        .width(4)
        .height(38)
        .backgroundColor(this.courseFg(course.name))
        .borderRadius(2)
        .margin({ top: 2 })

      Column() {
        Text(TtPeriods.startText(course.start))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text('第' + course.start + '-' + course.end + '节')
          .fontSize(9)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 1 })
      }
      .width(58)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      Column() {
        Text(course.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.metaOf(course).length > 0) {
          Text(this.metaOf(course))
            .fontSize(11)
            .fontColor(Tokens.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 3 })
        }
        Text(this.weeksText(course))
          .fontSize(9)
          .fontColor(Tokens.TEXT_TERTIARY)
          .padding({ left: 8, right: 8, top: 1, bottom: 1 })
          .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.04))
          .borderRadius(Tokens.RADIUS_PILL)
          .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 12, top: 12, bottom: 12 })
    .backgroundColor(Tokens.CARD_STRONG)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(14)
    .shadow({ radius: 8, color: Tokens.CARD_SHADOW, offsetX: 0, offsetY: 2 })
    .stateStyles({
      pressed: {
        .scale({ x: 0.985, y: 0.985 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .transition(Motion.listItem())
    .onClick(() => {
      this.openCourse(course, course.day);
    })
  }

  @Builder
  dayView() {
    Column() {
      Row({ space: 4 }) {
        this.dayChip(0)
        this.dayChip(1)
        this.dayChip(2)
        this.dayChip(3)
        this.dayChip(4)
        this.dayChip(5)
        this.dayChip(6)
      }
      .width('100%')
      .margin({ top: 12 })

      if (this.coursesOf(this.dayIdx).length === 0) {
        Text('这天没课')
          .fontSize(12)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 36, bottom: 36 })
      } else {
        Column({ space: 8 }) {
          ForEach(this.coursesOf(this.dayIdx), (course: Course, index: number) => {
            this.dayCourseCard(course)
          }, (course: Course, index: number) => 'dc_' + this.weekOffset + '_' + this.dayIdx + '_'
            + index + '_' + course.name)
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 })))
  }

  @Builder
  groupRow(group: TtGroupItem) {
    Row() {
      Column()
        .width(7)
        .height(7)
        .backgroundColor(group.fg)
        .borderRadius(3)
        .margin({ top: 6 })

      Column() {
        Text(group.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(group.pills, (pill: string) => {
            Text(pill)
              .fontSize(9)
              .fontColor(Tokens.TEXT_SECONDARY)
              .padding({ left: 7, right: 7, top: 1, bottom: 1 })
              .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.05))
              .borderRadius(Tokens.RADIUS_PILL)
              .margin({ right: 5, top: 4 })
          }, (pill: string) => group.name + '_' + pill)
        }
        .width('100%')

        if (group.meta.length > 0) {
          Text(group.meta)
            .fontSize(10)
            .fontColor(Tokens.TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 5 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: Tokens.DIVIDER })
    .onClick(() => {
      this.openCourse(group.course, group.course.day);
    })
  }

  @Builder
  groupsPanel() {
    Column() {
      Row({ space: 6 }) {
        Text('全部课程')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.MIST_TEAL)
        Text(this.groups.length + ' 门')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
        Blank()
        Text('⌄')
          .fontSize(13)
          .fontColor(Tokens.MIST_TEAL)
          .rotate({ angle: this.allOpen ? 180 : 0 })
          .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Tokens.CONTROL)
      .border({ width: 0.5, color: Tokens.CARD_EDGE })
      .borderRadius(11)
      .onClick(() => {
        this.toggleAll();
      })

      if (this.allOpen) {
        Column() {
          ForEach(this.groups, (group: TtGroupItem) => {
            this.groupRow(group)
          }, (group: TtGroupItem) => 'grp_' + group.name)
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        .transition(Motion.listItem())
      }
    }
    .width('100%')
    .margin({ top: 14 })
  }

  private notify(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /** 分享当前视图（日 / 周）：先渲染分享卡图片，再走系统图片分享。 */
  private sharePlan(): void {
    if (this.snapshot === undefined || this.snapshot.c.length === 0) {
      this.notify('暂无可分享的课表');
      return;
    }
    const lines: string[] = [];
    let courseCount: number = 0;
    let subtitle: string = '';
    if (this.viewMode === 'day') {
      const date: Date = this.selectedDate();
      subtitle = TtPeriods.DAY_LABELS[this.dayIdx] + ' ' + (date.getMonth() + 1) + '-' + date.getDate();
      const sessions: SessionInfo[] = this.sessions();
      courseCount = sessions.length;
      if (sessions.length === 0) {
        lines.push('今天没课');
      }
      for (let i = 0; i < sessions.length; i++) {
        const session: SessionInfo = sessions[i];
        lines.push(session.startText + '–' + session.endText + '  ' + session.name
          + (session.room.length > 0 ? '  · ' + session.room : ''));
      }
    } else {
      subtitle = this.rangeText() + ' · 整周';
      for (let day = 0; day < 7; day++) {
        const courses: Course[] = this.coursesOf(day);
        courseCount += courses.length;
        lines.push(TtPeriods.DAY_LABELS[day]);
        if (courses.length === 0) {
          lines.push('  没课');
        }
        for (let i = 0; i < courses.length; i++) {
          const course: Course = courses[i];
          lines.push('  ' + TtPeriods.startText(course.start) + '–' + TtPeriods.endText(course.end)
            + '  ' + course.name + (course.room.length > 0 ? '  · ' + course.room : ''));
        }
        if (day < 6) {
          lines.push('');
        }
      }
    }
    const now: number = Date.now();
    const params: ExportParam[] = [
      new ExportParam('周次', '第 ' + this.displayWeek() + ' 周'),
      new ExportParam('日期', this.rangeText()),
      new ExportParam('课程', courseCount + ' 节')
    ];
    this.shareSpec = ShareSpecs.textCard('TIMETABLE', '第 ' + this.displayWeek() + ' 周课表',
      subtitle, '课表', params, lines, '课程安排', now);
    const builder: CustomBuilder = (): void => {
      this.sharePoster();
    };
    NativeShare.shareCard(this.getUIContext(), builder, this.shareSpec.fileName,
      this.shareSpec.title, this.shareSpec.subtitle).then((result: ShareResult) => {
      if (!result.ok) {
        this.notify(result.message);
      }
    });
  }

  /** 单门课程详情 → 分享卡图片。 */
  private shareCourse(): void {
    if (this.detailCourse === undefined) {
      return;
    }
    const course: Course = this.detailCourse;
    const now: number = Date.now();
    const params: ExportParam[] = [
      new ExportParam('日期', this.detailDate),
      new ExportParam('时间', TtPeriods.startText(course.start) + '–' + TtPeriods.endText(course.end)),
      new ExportParam('节次', TtCalendar.spanText(course.start, course.end)),
      new ExportParam('地点', course.room.length > 0 ? course.room : '—'),
      new ExportParam('教师', course.teacher.length > 0 ? course.teacher : '—'),
      new ExportParam('周次', (course.weeks.length > 0 ? course.weeks : '全学期')
        + ' · ' + (course.parity === 'odd' ? '单周' : (course.parity === 'even' ? '双周' : '每周')))
    ];
    this.shareSpec = ShareSpecs.textCard('COURSE', course.name,
      this.detailDate + (course.room.length > 0 ? ' · ' + course.room : ''),
      '课程_' + course.name, params, ['在「班级工具 → 课表」中查看完整课程安排。'], '课程说明', now);
    const builder: CustomBuilder = (): void => {
      this.sharePoster();
    };
    NativeShare.shareCard(this.getUIContext(), builder, this.shareSpec.fileName,
      this.shareSpec.title, this.shareSpec.subtitle).then((result: ShareResult) => {
      if (!result.ok) {
        this.notify(result.message);
      }
    });
  }

  @Builder
  sharePoster() {
    ExportCardView({ spec: this.shareSpec })
  }

  @Builder
  detailRow(key: string, value: string) {
    Row() {
      Text(key)
        .fontSize(12)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(48)
      Text(value)
        .fontSize(13)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 0.5 }, color: Tokens.DIVIDER })
  }

  @Builder
  courseDetail() {
    Column() {
      Row() {
        Text('课程详情')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('分享')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.shareCourse();
          })
        Text('关闭')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.closeCourse();
          })
      }
      .width('100%')

      if (this.detailCourse !== undefined) {
        Row({ space: 8 }) {
          Column()
            .width(9)
            .height(9)
            .backgroundColor(this.courseFg(this.detailCourse.name))
            .borderRadius(3)
          Text(this.detailCourse.name)
            .fontSize(Tokens.F_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 10, bottom: 4 })

        Text(this.detailDate
          + (this.detailCourse.room.length > 0 ? ' · ' + this.detailCourse.room : ''))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')

        Column() {
          this.detailRow('教师', this.detailCourse.teacher.length > 0 ? this.detailCourse.teacher : '—')
          this.detailRow('时间', TtPeriods.startText(this.detailCourse.start) + '–'
            + TtPeriods.endText(this.detailCourse.end) + ' · '
            + TtCalendar.spanText(this.detailCourse.start, this.detailCourse.end))
          this.detailRow('教室', this.detailCourse.room.length > 0 ? this.detailCourse.room : '—')
          this.detailRow('周次', this.weeksText(this.detailCourse))
          this.detailRow('下次', this.nextTextOf(this.detailCourse))
        }
        .width('100%')
        .margin({ top: 6 })

        if (this.detailCourse.room.trim().length > 0) {
          Button() {
            SymbolGlyph($r('sys.symbol.map')).fontSize(21).fontColor(['#FFFFFF'])
          }
            .accessibilityText('在地图查看教室')
            .height(44)
            .width(44)
            .backgroundColor(Tokens.MIST_TEAL)
            .fontColor('#FFFFFF')
            .margin({ top: 10 })
            .onClick(() => {
              const room: string = this.detailCourse?.room ?? '';
              this.detailOpen = false;
              this.onOpenMap(room);
            })
        }
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Tokens.SHEET)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  @Builder
  stateCard() {
    Column({ space: 12 }) {
      if (this.loading) {
        LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
        Text('课表加载中…')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      } else {
        Text(this.errorMsg.length > 0 ? this.errorMsg : '课表还是空的')
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
        if (this.errorMsg.length === 0) {
          Text('教务课表同步后会自动出现')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        Button(this.errorMsg.length > 0 ? '重试' : '刷新')
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .height(38)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.reload(true);
          })
      }
    }
    .width('100%')
    .padding({ top: 40, bottom: 40, left: 18, right: 18 })
    .backgroundColor(Tokens.CARD)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(20)
    .shadow({ radius: 18, color: Tokens.CARD_SHADOW, offsetX: 0, offsetY: 6 })
    .justifyContent(FlexAlign.Center)
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
        progress: this.headerFade,
        title: '课表',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        }
      }) {
        Column() {
          if (this.loading || this.snapshot === undefined || this.snapshot.c.length === 0) {
            Column() {
              this.stateCard()
            }
            .width('100%')
            .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 12 })
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              Scroll(this.scroller) {
                Column() {
                  Column() {
                    this.weekHead()
                    this.actionsRow()

                    if (this.currentSession() !== undefined) {
                      Column() {
                        this.nextCard(this.currentSession()!)
                      }
                      .transition(Motion.popIn())
                    }

                    Column() {
                      if (this.viewMode === 'week') {
                        Column() {
                          this.weekGrid()
                        }
                        .width('100%')
                        .margin({ top: 12 })
                        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -10 })))
                      } else {
                        this.dayView()
                      }
                    }
                    .width('100%')

                    this.groupsPanel()

                    Row() {
                      Text(this.source === '我的课表'
                        ? '个人课表来自网页/安卓端教务登录同步'
                        : '个人课表需在网页/安卓端完成教务登录后同步')
                        .fontSize(10)
                        .fontColor(Tokens.TEXT_TERTIARY)
                        .layoutWeight(1)
                      Text('教务系统')
                        .fontSize(10)
                        .fontColor(Tokens.SLATE_BLUE)
                        .onClick(() => {
                          this.openJw();
                        })
                    }
                    .width('100%')
                    .margin({ top: 14 })
                  }
                  .width('100%')
                  .padding(14)
                  .backgroundColor(Tokens.CARD)
                  .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
                  .border({ width: 0.5, color: Tokens.CARD_EDGE })
                  .borderRadius(20)
                  .shadow({ radius: 18, color: Tokens.CARD_SHADOW, offsetX: 0, offsetY: 6 })
                  .clip(true)
                }
                .width('100%')
                .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 10, bottom: 24 })
              }
              .width('100%')
              .height('100%')
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
              .onDidScroll((offset: number) => {
                const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
                if (Math.abs(next - this.headerFade) > 0.03) {
                  this.headerFade = next;
                }
              })
            }
            .layoutWeight(1)
            .onRefreshing(() => {
              this.pullRefresh();
            })
          }
        }
        .width('100%')
        .height('100%')
      }

      if (this.detailOpen) {
        Column() {
          Column() {
            Blank()
            this.courseDetail()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Tokens.SCRIM)
          .justifyContent(FlexAlign.End)
          .transition(Motion.scrim())
          .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
