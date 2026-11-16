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
  @Prop quickIds: string[] = [];
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
  onOpenAll: () => void = () => {
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
  private startedAt: number = 0;

  onEpochChanged(): void {
    this.load(false);
  }

  aboutToAppear(): void {
    this.startedAt = Date.now();
    this.load(false);
    this.rotateTimer = setInterval(() => {
      this.rotateTick();
    }, 5000);
    this.shimmerTimer = setInterval(() => {
      this.getUIContext().animateTo({ duration: 700, curve: Motion.ease() }, () => {
        this.shimmer = !this.shimmer;
      });
    }, 700);
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
  }

  private quick(): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < this.quickIds.length && out.length < 4; i++) {
      const tool: ToolDef | undefined = ToolCatalog.byId(this.quickIds[i]);
      if (tool !== undefined) {
        out.push(tool);
      }
    }
    return out;
  }

  private async load(force: boolean): Promise<void> {
    const now: number = Date.now();
    try {
      const marks = await Services.marks.refresh(false);
      const snapshot = Services.marks.marks();
      // 课表
      const tt: TtResult = await Services.timetable.load(force);
      this.plan = TtCalendar.plan(tt.snapshot, now);
      this.ttLoaded = true;
      // 作业
      const hw: HomeworkResult = await Services.homework.load(force);
      const hidden = HidePrefs.read(Services.userdata.currentSections());
      const open: HomeworkRow[] = HomeDigest.hwOpen(hw.rows,
        (id: string) => snapshot.isDone(MarkKind.HW, id),
        (id: string) => hidden.hwHide.has(id));
      this.hwOpen = open.length;
      this.hwItems = HomeDigest.hwItems(open);
      // 通知
      const nt: NoticesResult = await Services.notices.load(force);
      const allCards: NoticeCard[] = NoticeCards.build(nt.entries, now);
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
      this.ntState = nt.ok ? 'ok' : (Services.currentSid.length === 0 ? 'off' : 'error');
      this.ntNew = await HomeNtBadge.update(Services.currentSid, Services.notices.currentSignature());
      // 电费（未选择 → 0 请求）
      const prefs = PowerPrefs.read(Services.userdata.currentSections());
      if (prefs.sel.length > 0) {
        this.powerHas = true;
        this.powerLabel = PowerRooms.labelOf(prefs.sel);
        this.powerQ = '—';
        this.powerState = 'idle';
        const rowResult: PowerRowResult = await Services.power.loadRow(prefs.sel, false);
        const row: PowerRow | undefined = rowResult.row;
        if (row !== undefined) {
          this.powerQ = HomeDigest.powerQText(row.q, row.hasValue);
          this.powerUnit = row.unit.length > 0 ? row.unit : '度';
          this.powerState = HomeDigest.powerState(row.q, row.hasValue, prefs.low);
          this.powerUpd = HomeDigest.updText(row.updatedAt);
        }
      }
    } catch (e) {
      this.ntState = 'error';
    }
    this.loading = false;
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
   * 工作台「今日」hero：中性深色（不铺大面积品牌绿，品牌绿只做小面积点缀）。
   * 内容：今日课程摘要 / 周次 / 问候 / 日期与角色。
   */
  @Builder
  heroCard() {
    Column() {
      Row() {
        Text('今日')
          .fontSize(Tokens.F_CAPTION)
          .fontColor('#DDF0EA')
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.22))
          .borderRadius(Tokens.RADIUS_PILL)
        Blank()
        Text(HomeDigest.weekText(this.plan.week).length > 0
          ? HomeDigest.weekText(this.plan.week) : '课表未同步')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.HERO_SUB)
      }
      .width('100%')

      Text(this.greeting() + '，' + this.userName)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.HERO_TEXT)
        .width('100%')
        .margin({ top: 12 })

      Text(this.subLine())
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.HERO_SUB)
        .width('100%')
        .margin({ top: 6 })

      Row() {
        Text(this.todaySummary())
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.HERO_TEXT)
          .layoutWeight(1)
          .maxLines(2)
        Text('课表 ›')
          .fontSize(Tokens.F_CAPTION)
          .fontColor('#DDF0EA')
          .padding({ left: 8 })
          .onClick(() => {
            this.onOpenTool('tt');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10 })
      .margin({ top: 10 })
      .border({ width: { top: 0.5 }, color: Tokens.HERO_DARK_SOFT })
    }
    .width('100%')
    .padding(18)
    .margin({ top: 4, bottom: 20 })
    .backgroundColor(Tokens.HERO_DARK)
    .borderRadius(24)
    .alignItems(HorizontalAlign.Start)
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
        Text(action)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
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
  taskCard(kind: string, icon: string, label: string, emptyText: string, onTap: () => void) {
    Row() {
      Text(icon)
        .fontSize(18)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor(Tokens.tint(Tokens.MIST_TEAL, 0.10))
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
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(Tokens.MIST_TEAL)
              .borderRadius(8)
              .margin({ left: 8 })
          }
          if (kind === 'nt' && this.ntNew) {
            Text('新通知')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
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
      Text('›')
        .fontSize(18)
        .fontColor(Tokens.TEXT_TERTIARY)
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
    .onClick(() => {
      onTap();
    })
  }
  @Builder
  quickGrid() {
    Row() {
      ForEach(this.quick(), (tool: ToolDef) => {
        Column() {
          Text(tool.glyph)
            .fontSize(18)
            .fontColor(tool.accent)
            .width(46)
            .height(46)
            .textAlign(TextAlign.Center)
            .backgroundColor(Tokens.tint(tool.accent, 0.12))
            .borderRadius(14)
          Text(tool.name)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .margin({ top: 6 })
            .maxLines(1)
        }
        .width('25%')
        .onClick(() => {
          this.onOpenTool(tool.id);
        })
      }, (tool: ToolDef) => tool.id)
    }
    .width('100%')
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
      .margin({ top: 28 })
      Column() {
        Row().width('22%').height(10).backgroundColor('#EDF1F2').borderRadius(4)
        Row().width('100%').height(54).backgroundColor('#E9EEEF').borderRadius(10).margin({ top: 12 })
      }
      .width('100%')
      .padding(14)
      .margin({ top: 20 })
      .backgroundColor(Tokens.CARD)
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
        .padding(14)
        .margin({ top: 12 })
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)
      }, (i: number) => 'sk_' + i)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
    .backgroundColor(Tokens.BG)
    .opacity(this.shimmer ? 0.55 : 1)
  }

  build() {
    Stack() {
    Refresh({ refreshing: this.refreshing }) {
      Scroll() {
      Row() {
      Column() {
        this.heroCard()

        // —— 今日课程 ——
        Column() {
          this.cardHeader('今天', '课表 ›', () => {
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
        .padding(14)
        .margin({ top: 20 })
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)
        .shadow({ radius: 18, color: '#0D1C2629', offsetX: 0, offsetY: 6 })
        .transition(Motion.listItem())

        // —— 宿舍电费 ——
        Column() {
          this.cardHeader('宿舍电费', this.powerHas ? '›' : '', () => {
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
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
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
        .padding(14)
        .margin({ top: 12 })
        .backgroundColor(Tokens.CARD)
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
          this.taskCard('hw', '📝', '作业待交', '作业都完成了', () => {
              this.onOpenTool('hw');
            })
        }
        .width('100%')
        .margin({ top: 12 })
        .transition(Motion.listItem())

        // —— 通知待处理 ——
        Column() {
          if (this.ntState === 'ok') {
            this.taskCard('nt', '📢', '通知待处理', '暂无待处理通知', () => {
                this.onOpenTool('nt');
              })
          } else {
            this.taskCard('nt', '📢', '通知待处理',
              this.ntState === 'off' ? '通知需联网同步'
                : (this.ntState === 'error' ? '通知同步失败，点开重试' : '通知同步中…'), () => {
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
          Text('全部 ›')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.SLATE_BLUE)
            .onClick(() => {
              this.onOpenAll();
            })
        }
        .width('100%')
        .margin({ top: 20, bottom: 10 })

        if (this.quick().length > 0) {
          Column() {
            this.quickGrid()
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Tokens.CARD)
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
                .margin({ top: 3 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('去勾选 ›')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Tokens.CARD)
          .borderRadius(Tokens.RADIUS_CARD)
          .onClick(() => {
            this.onEditQuick();
          })
        }

        Blank().height(24)
      }
      .width('100%')
      .constraintSize({ maxWidth: Breakpoints.contentMaxWidth(this.layoutWidth) })
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
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
    .backgroundColor(Tokens.BG)
    .onRefreshing(() => {
      this.load(true).then(() => {
        this.refreshing = false;
      });
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
