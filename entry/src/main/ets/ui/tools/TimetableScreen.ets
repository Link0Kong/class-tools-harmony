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
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';

const ROW_H: number = 52;
const TIME_W: number = 46;
const JW_URL: string = 'http://210.34.74.77/sso.jsp';
const ACCENTS: string[] = ['#4E9082', '#6E8CA8', '#B98F63', '#8A6A92', '#5F8F5B', '#4A88A8', '#B06A55'];

/**
 * 课表工具：日视图 + 周视图（7 列 × 12 节网格）、左右滑动切周、课程详情、个人/班级课表切换。
 *
 * 数据：个人课表（`userdata.tt.ttUseMine + ttLocal`）优先，其次 `site_assets id=tt`；
 * 周次/单双周/下一节全部由 `TtCalendar` 计算。教务登录依赖网页/安卓端完成（PGP 加密链路，HarmonyOS 端仅提供入口）。
 */
@Component
export struct TimetableScreen {
  onClose: () => void = () => {
  };

  @State private snapshot: TtSnapshot | undefined = undefined;
  @State private plan: TtPlan = new TtPlan();
  @State private weekOffset: number = 0;
  @State private dayIdx: number = 0;
  @State private viewMode: string = 'day';
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private source: string = '';
  @State private now: number = Date.now();
  @State private gridWidth: number = 0;
  @State private slide: number = 0;
  @State private detailCourse: Course | undefined = undefined;
  @State private detailOpen: boolean = false;
  @State private detailDate: string = '';

  aboutToAppear(): void {
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
    this.source = result.source === TtSource.PERSONAL ? '我的课表'
      : (result.source === TtSource.CACHE ? '本机缓存' : '班级课表');
    if (!result.ok) {
      this.errorMsg = result.message;
    } else if (result.message.length > 0) {
      this.errorMsg = result.message;
    }
    this.loading = false;
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

  private accentOf(course: Course): string {
    let hash: number = 0;
    for (let i = 0; i < course.name.length; i++) {
      hash = (hash * 31 + course.name.charCodeAt(i)) % 9973;
    }
    return ACCENTS[hash % ACCENTS.length];
  }

  private stateColor(state: SessionState): string {
    if (state === SessionState.ONGOING) {
      return Tokens.MIST_TEAL;
    }
    if (state === SessionState.DONE) {
      return Tokens.TEXT_TERTIARY;
    }
    return Tokens.TEXT_SECONDARY;
  }

  private shiftWeek(delta: number): void {
    const target: number = this.weekOffset + delta;
    this.slide = delta > 0 ? 44 : -44;
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.weekOffset = target;
      this.slide = 0;
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
  dayChip(index: number) {
    Column() {
      Text(TtPeriods.DAY_LABELS[index])
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.dayIdx === index ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      Text('' + this.dateAt(index).getDate())
        .fontSize(10)
        .fontColor(this.dayIdx === index ? '#E8F2EF' : Tokens.TEXT_TERTIARY)
        .margin({ top: 1 })
    }
    .width(44)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.dayIdx === index ? Tokens.MIST_TEAL : Tokens.BG)
    .borderRadius(9)
    .onClick(() => {
      this.dayIdx = index;
    })
  }

  @Builder
  viewChip(mode: string, label: string) {
    Text(label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.viewMode === mode ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.viewMode === mode ? Tokens.SLATE_BLUE : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ left: 6 })
      .onClick(() => {
        this.viewMode = mode;
      })
  }

  @Builder
  sessionCard(session: SessionInfo) {
    Row() {
      Column() {
        Text(session.startText + '–' + session.endText)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.stateColor(session.state))
        Text(session.span)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .width(96)

      Column() {
        Text(session.name)
          .fontSize(Tokens.F_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(2)
        Row({ space: 8 }) {
          if (session.room.length > 0) {
            Text(session.room)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
          }
          if (session.state === SessionState.ONGOING) {
            Text('进行中')
              .fontSize(Tokens.F_CAPTION)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(Tokens.MIST_TEAL)
              .borderRadius(6)
          }
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .stateStyles({
      pressed: {
        .scale({ x: 0.99, y: 0.99 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
  }

  @Builder
  nextCard(session: SessionInfo) {
    Column() {
      Row() {
        Text('下一节')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.MIST_TEAL)
        Blank()
        Text(session.dayText + ' ' + session.dateText)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Text(session.name)
        .fontSize(Tokens.F_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 6 })

      Text(session.startText + '–' + session.endText + (session.room.length > 0 ? ' · ' + session.room : ''))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.08))
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  courseBlock(course: Course, day: number) {
    Column() {
      Text(course.name)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (course.room.length > 0) {
        Text(TtCalendar.roomShort(course.room))
          .fontSize(9)
          .fontColor('#EAF2F0')
          .maxLines(1)
          .width('100%')
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .height((course.end - course.start + 1) * ROW_H - 4)
    .padding(4)
    .backgroundColor(this.accentOf(course))
    .borderRadius(7)
    .onClick(() => {
      this.openCourse(course, day);
    })
  }

  @Builder
  weekGrid() {
    Column() {
      Row() {
        Column()
          .width(TIME_W)
        ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => {
          Column() {
            Text(TtPeriods.DAY_LABELS[day].substring(1))
              .fontSize(10)
              .fontColor(day === TtCalendar.dayIndex(new Date(this.now)) ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
            Text('' + this.dateAt(day).getDate())
              .fontSize(9)
              .fontColor(Tokens.TEXT_TERTIARY)
          }
          .layoutWeight(1)
          .height(26)
          .justifyContent(FlexAlign.Center)
        }, (day: number) => 'wh_' + day)
      }
      .width('100%')

      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          Column() {
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (period: number) => {
              Column() {
                Text('' + period)
                  .fontSize(9)
                  .fontColor(Tokens.TEXT_TERTIARY)
                Text(TtPeriods.startText(period))
                  .fontSize(8)
                  .fontColor(Tokens.TEXT_TERTIARY)
              }
              .width(TIME_W)
              .height(ROW_H)
              .justifyContent(FlexAlign.Center)
            }, (period: number) => 'tp_' + period)
          }
          .width(TIME_W)

          ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => {
            Column() {
              ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (period: number) => {
                Divider()
                  .strokeWidth(0.5)
                  .color(Tokens.DIVIDER)
                  .height(ROW_H)
              }, (period: number) => 'd' + day + '_' + period)
            }
            .layoutWeight(1)
            .height(12 * ROW_H)
            .backgroundColor(day === TtCalendar.dayIndex(new Date(this.now))
              ? Tokens.tint(Tokens.MIST_TEAL, 0.05) : Color.Transparent)
          }, (day: number) => 'wc_' + day)
        }
        .width('100%')
        .height(12 * ROW_H)

        ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => {
          ForEach(this.coursesOf(day), (course: Course, index: number) => {
            Column() {
              this.courseBlock(course, day)
            }
            .width((this.gridWidth - TIME_W) / 7 - 2)
            .position({
              x: TIME_W + day * ((this.gridWidth - TIME_W) / 7) + 1,
              y: (course.start - 1) * ROW_H + 2
            })
          }, (course: Course, index: number) => 'cb_' + day + '_' + index + '_' + course.name)
        }, (day: number) => 'wd_' + day)
      }
      .width('100%')
      .height(12 * ROW_H)
      .margin({ top: 2 })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const width: number = Number(newArea.width);
        if (width > 0 && Math.abs(width - this.gridWidth) > 1) {
          this.gridWidth = width;
        }
      })
    }
    .width('100%')
    .padding({ left: 6, right: 6, bottom: 6 })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .translate({ x: this.slide })
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
        Text('关闭')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.closeCourse();
          })
      }
      .width('100%')
      if (this.detailCourse !== undefined) {
        Text(this.detailCourse.name)
          .fontSize(Tokens.F_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 8 })
        Text(this.detailDate
          + (this.detailCourse.room.length > 0 ? ' · ' + this.detailCourse.room : ''))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 4 })
        Text(TtPeriods.startText(this.detailCourse.start) + '–' + TtPeriods.endText(this.detailCourse.end)
          + ' · ' + TtCalendar.spanText(this.detailCourse.start, this.detailCourse.end)
          + (this.detailCourse.teacher.length > 0 ? ' · ' + this.detailCourse.teacher : ''))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 8 })
        Text('周次 ' + (this.detailCourse.weeks.length > 0 ? this.detailCourse.weeks : '全学期')
          + ' · ' + (this.detailCourse.parity === 'odd' ? '单周'
            : (this.detailCourse.parity === 'even' ? '双周' : '每周')))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Tokens.CARD)
    .borderRadius({ topLeft: Tokens.RADIUS_CARD, topRight: Tokens.RADIUS_CARD })
    .alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: '课表',
          actionText: this.loading ? '' : '刷新',
          onBack: () => {
            this.onClose();
          },
          onAction: () => {
            this.reload(true);
          }
        })

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
            Text('加载课表…').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.snapshot === undefined || this.snapshot.c.length === 0) {
          Column({ space: 12 }) {
            Text(this.errorMsg.length > 0 ? this.errorMsg : '暂无课表数据')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Button('重试')
              .backgroundColor(Tokens.MIST_TEAL)
              .fontColor('#FFFFFF')
              .height(40)
              .borderRadius(Tokens.RADIUS_PILL)
              .onClick(() => {
                this.reload(true);
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding(Tokens.PAGE_PADDING)
        } else {
          Scroll() {
            Column() {
              Row() {
                Text(this.weekLabel())
                  .fontSize(Tokens.F_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Tokens.TEXT_PRIMARY)
                Text(' · ' + this.rangeText())
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .margin({ left: 4 })
                Blank()
                Text('‹')
                  .fontSize(18)
                  .fontColor(Tokens.SLATE_BLUE)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.shiftWeek(-1);
                  })
                Text('本周')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_SECONDARY)
                  .padding({ left: 4, right: 4 })
                  .onClick(() => {
                    this.weekOffset = 0;
                  })
                Text('›')
                  .fontSize(18)
                  .fontColor(Tokens.SLATE_BLUE)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.shiftWeek(1);
                  })
              }
              .width('100%')
              .margin({ top: 6 })

              Row() {
                Text(this.snapshot.c.length + ' 门课 · ' + this.source
                  + (this.errorMsg.length > 0 ? ' · ' + this.errorMsg : ''))
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(this.errorMsg.length > 0 ? Tokens.WARM_SAND : Tokens.TEXT_TERTIARY)
                Blank()
                this.viewChip('day', '日')
                this.viewChip('week', '周')
              }
              .width('100%')
              .margin({ top: 6 })

              if (this.viewMode === 'day') {
                Row({ space: 6 }) {
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

                if (this.weekOffset === 0 && this.dayIdx === TtCalendar.dayIndex(new Date(this.now))
                  && this.plan.next !== undefined) {
                  Column() {
                    this.nextCard(this.plan.next)
                  }
                  .margin({ top: 14 })
                }

                if (this.sessions().length === 0) {
                  Column() {
                    Text('这一天没有课')
                      .fontSize(Tokens.F_LABEL)
                      .fontColor(Tokens.TEXT_TERTIARY)
                  }
                  .width('100%')
                  .padding({ top: 40, bottom: 40 })
                } else {
                  Column({ space: 10 }) {
                    ForEach(this.sessions(), (session: SessionInfo) => {
                      this.sessionCard(session)
                    }, (session: SessionInfo) => '' + session.startAt + '_' + session.name + '_' + session.state)
                  }
                  .width('100%')
                  .margin({ top: 14 })
                  .transition(Motion.listItem())
                }
              } else {
                Column() {
                  this.weekGrid()
                }
                .width('100%')
                .margin({ top: 10 })
                .gesture(
                  PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
                    .onActionEnd((event: GestureEvent) => {
                      if (event.offsetX < -40) {
                        this.shiftWeek(1);
                      } else if (event.offsetX > 40) {
                        this.shiftWeek(-1);
                      }
                    })
                )
                Text('左右滑动切换周')
                  .fontSize(10)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 8 })
              }

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
              .margin({ top: 14, bottom: 20 })
            }
            .width('100%')
            .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
          }
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Tokens.BG)

      if (this.detailOpen) {
        Column() {
          Column() {
            Blank()
            this.courseDetail()
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
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
