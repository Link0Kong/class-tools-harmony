import { PageInsets } from '../theme/PageInsets';
﻿import { Services } from '../../app/Services';
import { ClassMember } from '../../data/member/ClassMember';
import { VisitLoadResult, VisitRow } from '../../data/visits/VisitsRepository';
import {
  VisitAccount,
  VisitClientCount,
  VisitDeviceGroup,
  VisitRange,
  VisitStats,
  VisitStatsReport,
  VisitTrendPoint,
  VisitVersionCount
} from '../../data/visits/VisitStats';
import { Breakpoints } from '../theme/Breakpoints';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/** 趋势图今天范围的刻度（契约 §3.3：00/03/…/21/23）。 */
const HOUR_LABELS: string[] = ['00', '03', '06', '09', '12', '15', '18', '21', '23'];

/** 页脚口径说明（契约 §4.8）。 */
const FOOTNOTE: string = '按访问次数排序（次数相同按最近访问）；同一账号同一登录端每小时记一次；'
  + '设备/版本自 2026-11-20 起记录，旧数据为「未记录」；已忽略测试账号。';

/**
 * 访问统计（仅管理员；契约 `web/统计多端_详细统计_契约_20261120.md` §4）。
 *
 * - 非管理员：**不发任何 `visits` 请求**，只显示「仅管理员可见」；
 * - 一次拉 7 天，页面内切换「今天 / 近 7 天」不重新请求；
 * - 摘要 4 格 → 趋势柱 → 登录端堆叠条 → 版本 / 设备分布 → 账号明细（一次只展开一个）；
 * - 全部聚合在 `VisitStats` 纯逻辑里，页面只渲染；`sid` / `did` 不显示。
 */
@Component
export struct StatsScreen {
  onClose: () => void = () => {
  };

  @State private isAdmin: boolean = false;
  @State private loading: boolean = false;
  @State private errorMsg: string = '';
  @State private range: VisitRange = VisitRange.TODAY;
  @State private report: VisitStatsReport = new VisitStatsReport();
  /** 当前展开的账号（sid 仅作内部展开键，不渲染）。 */
  @State private expandedKey: string = '';
  @State private layoutWidth: number = 0;
  @State private headerFade: number = 0;

  private rows: VisitRow[] = [];
  private names: Map<string, string> = new Map<string, string>();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.isAdmin = Services.currentIsAdmin;
    if (!this.isAdmin) {
      // 契约：非管理员不发请求。
      return;
    }
    this.refresh();
  }

  private async refresh(): Promise<void> {
    if (!this.isAdmin) {
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    const result: VisitLoadResult = await Services.visitsRepository.load();
    if (!result.ok) {
      this.rows = [];
      this.errorMsg = result.message.length > 0 ? result.message : '访问统计加载失败';
      this.report = new VisitStatsReport();
      this.loading = false;
      return;
    }
    this.rows = result.rows;
    await this.loadRosterNames();
    this.rebuild();
    this.loading = false;
  }

  /** 名单只作姓名兜底（visits 行没有姓名时），只读本机缓存、不发请求。 */
  private async loadRosterNames(): Promise<void> {
    const map: Map<string, string> = new Map<string, string>();
    try {
      const members: ClassMember[] = await Services.members.cached();
      for (let i = 0; i < members.length; i++) {
        const sid: string = members[i].sid.trim();
        if (sid.length > 0) {
          map.set(sid, members[i].name);
        }
      }
    } catch (e) {
      // 名单缓存不可用时只影响姓名兜底，不影响统计。
    }
    this.names = map;
  }

  private rebuild(): void {
    const names: Map<string, string> = this.names;
    const nameOf: (sid: string) => string = (sid: string): string => {
      const value: string | undefined = names.get(sid);
      return value !== undefined ? value : '';
    };
    this.report = VisitStats.build(this.rows, this.range, Date.now(), nameOf);
  }

  private selectRange(next: VisitRange): void {
    if (this.range === next) {
      return;
    }
    this.range = next;
    this.expandedKey = '';
    this.rebuild();
  }

  private isExpanded(account: VisitAccount): boolean {
    return this.expandedKey === account.key;
  }

  private toggleAccount(account: VisitAccount): void {
    this.expandedKey = this.isExpanded(account) ? '' : account.key;
  }

  private rankColor(rank: number): string {
    if (rank === 1) {
      return Tokens.MIST_TEAL;
    }
    if (rank === 2) {
      return Tokens.SLATE_BLUE;
    }
    return Tokens.WARM_SAND;
  }

  private barHeight(point: VisitTrendPoint): number {
    if (point.count <= 0) {
      return 3;
    }
    return Math.max(4, Math.round(point.ratio * 78));
  }

  private percentWidth(percent: number): string {
    let value: number = percent;
    if (value < 0) {
      value = 0;
    }
    if (value > 100) {
      value = 100;
    }
    return value + '%';
  }

  private accountBarPercent(account: VisitAccount): number {
    return Math.round(account.ratio * 100);
  }

  private deviceMeta(device: VisitDeviceGroup): string {
    let text: string = device.count + ' 次';
    if (device.lastTs > 0) {
      const time: string = VisitStats.formatTime(device.lastTs);
      if (time.length > 0) {
        text += ' · 最近 ' + time;
      }
    }
    return text;
  }

  @Builder
  rangeChip(label: string, value: VisitRange) {
    Text(label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.range === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .fontWeight(this.range === value ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .height(30)
      .layoutWeight(1)
      .backgroundColor(this.range === value ? Tokens.MIST_TEAL : Color.Transparent)
      .borderRadius(Tokens.RADIUS_PILL)
      .onClick(() => {
        this.selectRange(value);
      })
  }

  @Builder
  rangeBar() {
    Row() {
      this.rangeChip('今天', VisitRange.TODAY)
      this.rangeChip('近 7 天', VisitRange.WEEK)
    }
    .width('100%')
    .padding(2)
    .backgroundColor(Tokens.CONTROL)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_PILL)
    .margin({ top: Tokens.GAP })
  }

  @Builder
  metricTile(caption: string, value: number) {
    Column() {
      Text('' + value)
        .fontSize(Tokens.F_HEADING + 4)
        .fontWeight(FontWeight.Bold)
        .fontColor(Tokens.TEXT_PRIMARY)
        .maxLines(1)
      Text(caption)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(1)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  summaryGrid() {
    Column() {
      if (Breakpoints.isWide(this.layoutWidth)) {
        Row({ space: Tokens.GAP_SM }) {
          this.metricTile('访问账号', this.report.summary.accounts)
          this.metricTile('访问次数', this.report.summary.visits)
          this.metricTile('今日活跃', this.report.summary.activeToday)
          this.metricTile('访问设备', this.report.summary.devices)
        }
        .width('100%')
      } else {
        Row({ space: Tokens.GAP_SM }) {
          this.metricTile('访问账号', this.report.summary.accounts)
          this.metricTile('访问次数', this.report.summary.visits)
        }
        .width('100%')
        Row({ space: Tokens.GAP_SM }) {
          this.metricTile('今日活跃', this.report.summary.activeToday)
          this.metricTile('访问设备', this.report.summary.devices)
        }
        .width('100%')
        .margin({ top: Tokens.GAP_SM })
      }
    }
    .width('100%')
    .margin({ top: Tokens.GAP })
  }

  @Builder
  percentBar(percent: number, color: string) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(4)
        .borderRadius(2)
        .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.08))
      Row()
        .width(this.percentWidth(percent))
        .height(4)
        .borderRadius(2)
        .backgroundColor(color)
    }
    .width('100%')
    .height(4)
    .margin({ top: Tokens.SPACE_6 })
  }

  @Builder
  trendCard() {
    Column() {
      Row() {
        Text('趋势 · ' + this.report.trendTitle)
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(this.report.trendPeak)
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
      }
      .width('100%')

      Row() {
        ForEach(this.report.trend, (point: VisitTrendPoint, index: number) => {
          Column() {
            Text(point.count > 0 ? '' + point.count : '')
              .fontSize(this.range === VisitRange.WEEK ? 10 : 8)
              .fontColor(Tokens.TEXT_TERTIARY)
              .height(12)
              .width('100%')
              .maxLines(1)
              .textAlign(TextAlign.Center)
            Column()
              .width('100%')
              .height(this.barHeight(point))
              .borderRadius(3)
              .backgroundColor(point.highlight ? Tokens.WARM_SAND : Tokens.MIST_TEAL)
              .opacity(point.count > 0 ? 1 : 0.22)
          }
          .layoutWeight(1)
          .height(96)
          .justifyContent(FlexAlign.End)
          .padding({ left: 1, right: 1 })
        }, (point: VisitTrendPoint, index: number) => 'bar_' + index)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: Tokens.SPACE_6 })

      if (this.range === VisitRange.TODAY) {
        Row() {
          ForEach(HOUR_LABELS, (label: string) => {
            Text(label)
              .fontSize(9)
              .fontColor(Tokens.TEXT_TERTIARY)
          }, (label: string) => 'h_' + label)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: Tokens.SPACE_4 })
      } else {
        Row() {
          ForEach(this.report.trend, (point: VisitTrendPoint) => {
            Text(point.label)
              .fontSize(9)
              .fontColor(point.highlight ? Tokens.WARM_SAND : Tokens.TEXT_TERTIARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }, (point: VisitTrendPoint, index: number) => 'day_' + index)
        }
        .width('100%')
        .margin({ top: Tokens.SPACE_4 })
      }
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  clientCard() {
    Column() {
      Row() {
        Text('登录端')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(this.report.summary.visits + ' 次访问')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Row() {
        ForEach(this.report.clients, (item: VisitClientCount) => {
          if (item.percent > 0) {
            Column()
              .height(10)
              .width(this.percentWidth(item.percent))
              .backgroundColor(item.color)
          }
        }, (item: VisitClientCount) => 'seg_' + item.client)
      }
      .width('100%')
      .height(10)
      .borderRadius(5)
      .clip(true)
      .backgroundColor(Tokens.tint(Tokens.TEXT_PRIMARY, 0.08))
      .margin({ top: Tokens.SPACE_8 })

      ForEach(this.report.clients, (item: VisitClientCount) => {
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(item.color)
          Text(item.label)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_PRIMARY)
            .margin({ left: Tokens.SPACE_6 })
          Blank()
          Text(item.count + ' 次 · ' + item.percent + '%')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .width('100%')
        .height(24)
      }, (item: VisitClientCount) => 'legend_' + item.client)
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  versionRow(item: VisitVersionCount) {
    Column() {
      Row() {
        Text(item.label)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.count + ' 次')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
        Text(' ' + item.percent + '%')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      this.percentBar(item.percent, Tokens.SLATE_BLUE)
    }
    .width('100%')
    .padding({ top: Tokens.SPACE_6, bottom: Tokens.SPACE_4 })
  }

  @Builder
  versionCard() {
    Column() {
      Row() {
        Text('版本')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('最多 6 项')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      ForEach(this.report.versions, (item: VisitVersionCount) => {
        this.versionRow(item)
      }, (item: VisitVersionCount) => 'ver_' + item.label)
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  deviceRow(item: VisitDeviceGroup) {
    Column() {
      Row() {
        Circle()
          .width(6)
          .height(6)
          .fill(item.color)
        Text(item.clientLabel)
          .fontSize(10)
          .fontColor(item.color)
          .margin({ left: Tokens.SPACE_4 })
        Text(item.devLabel)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: Tokens.SPACE_6 })
        Text(item.count + ' 次')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
        Text(' ' + item.percent + '%')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      this.percentBar(item.percent, item.color)
    }
    .width('100%')
    .padding({ top: Tokens.SPACE_6, bottom: Tokens.SPACE_4 })
  }

  @Builder
  deviceCard() {
    Column() {
      Row() {
        Text('设备')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('最多 6 项')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      ForEach(this.report.devices, (item: VisitDeviceGroup) => {
        this.deviceRow(item)
      }, (item: VisitDeviceGroup) => 'dev_' + item.client + '|' + item.dev)
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  versionDeviceCards() {
    if (Breakpoints.isWide(this.layoutWidth)) {
      Row({ space: Tokens.GAP }) {
        Column() {
          this.versionCard()
        }
        .layoutWeight(1)

        Column() {
          this.deviceCard()
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    } else {
      this.versionCard()
      this.deviceCard()
    }
  }

  @Builder
  tag(text: string, color: string) {
    Text(text)
      .fontSize(10)
      .fontColor(color)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 190 })
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(Tokens.tint(color, 0.10))
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: Tokens.SPACE_4, bottom: Tokens.SPACE_4 })
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(46)
      Text(value.length > 0 ? value : '—')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: Tokens.SPACE_4 })
  }

  @Builder
  accountDetail(account: VisitAccount) {
    Column() {
      Text(account.detailText)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width('100%')
      this.detailRow('登录端', account.clientText())
      this.detailRow('版本', account.versionText())
      Row() {
        Text('设备')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width(46)
        Text(account.deviceCount + ' 台')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_PRIMARY)
      }
      .width('100%')
      .margin({ top: Tokens.SPACE_4 })

      ForEach(account.devices, (device: VisitDeviceGroup) => {
        Row() {
          Circle()
            .width(6)
            .height(6)
            .fill(device.color)
          Text(device.devLabel)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: Tokens.SPACE_6 })
          Text(this.deviceMeta(device))
            .fontSize(10)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ left: Tokens.SPACE_6 })
        }
        .width('100%')
        .height(24)
        .alignItems(VerticalAlign.Center)
      }, (device: VisitDeviceGroup) => 'accdev_' + device.client + '|' + device.dev)
    }
    .width('100%')
    .padding({ left: 32, bottom: Tokens.SPACE_10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  accountRow(account: VisitAccount, index: number) {
    Column() {
      Row() {
        Text('' + (index + 1))
          .fontSize(Tokens.F_CAPTION)
          .fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(index < 3 ? '#FFFFFF' : Tokens.TEXT_TERTIARY)
          .textAlign(TextAlign.Center)
          .width(22)
          .height(22)
          .backgroundColor(index < 3 ? this.rankColor(index + 1) : Tokens.CONTROL)
          .borderRadius(11)

        Column() {
          Row() {
            Text(account.name)
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(account.count + ' 次')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
              .margin({ left: Tokens.SPACE_6 })
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            this.tag(account.lastClientLabel(), Tokens.MIST_TEAL)
            this.tag(account.lastVerLabel(), Tokens.SLATE_BLUE)
            this.tag(account.lastDevLabel(), Tokens.TEXT_SECONDARY)
          }
          .width('100%')
          .margin({ top: Tokens.SPACE_4 })

          this.percentBar(this.accountBarPercent(account), Tokens.MIST_TEAL)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: Tokens.SPACE_10 })

        Text(this.isExpanded(account) ? '收起' : '详情')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: Tokens.SPACE_6, top: Tokens.SPACE_2 })
      }
      .width('100%')
      .padding({ top: Tokens.SPACE_10, bottom: Tokens.SPACE_10 })
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.toggleAccount(account);
      })

      if (this.isExpanded(account)) {
        this.accountDetail(account)
      }
    }
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: Tokens.DIVIDER })
  }

  @Builder
  accountCard() {
    Column() {
      Row() {
        Text('账号明细')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(this.report.accounts.length + ' 个账号')
          .fontSize(10)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      ForEach(this.report.accounts, (account: VisitAccount, index: number) => {
        this.accountRow(account, index)
      }, (account: VisitAccount) => account.key)
    }
    .width('100%')
    .padding({ left: Tokens.CARD_PADDING, right: Tokens.CARD_PADDING, top: Tokens.CARD_PADDING, bottom: 4 })
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  emptyCard() {
    Column() {
      Text(this.report.emptyText)
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_SECONDARY)
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
    .margin({ top: Tokens.GAP })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  errorCard() {
    Column() {
      Text(this.errorMsg)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.DANGER)
        .width('100%')
      Text('重试')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.MIST_TEAL)
        .margin({ top: Tokens.SPACE_8 })
        .onClick(() => {
          this.refresh();
        })
    }
    .width('100%')
    .padding(Tokens.CARD_PADDING)
    .margin({ top: Tokens.GAP })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  build() {
    Column() {
      PageHeader({
        progress: this.headerFade,
        title: '访问统计',
        actionText: this.isAdmin && !this.loading ? '刷新' : '',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.refresh();
        }
      }) {
        Column() {
          if (!this.isAdmin) {
            Column() {
              Text('仅管理员可见')
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_SECONDARY)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.loading) {
            Column() {
              LoadingProgress()
                .width(32)
                .height(32)
                .color(Tokens.MIST_TEAL)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.scroller) {
              Column() {
                Text('仅管理员 · 按访问次数 · 不显示学号')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .width('100%')

                this.rangeBar()

                if (this.errorMsg.length > 0) {
                  this.errorCard()
                } else {
                  this.summaryGrid()
                  if (this.report.empty) {
                    this.emptyCard()
                  } else {
                    this.trendCard()
                    this.clientCard()
                    this.versionDeviceCards()
                    this.accountCard()
                  }
                  Text(FOOTNOTE)
                    .fontSize(10)
                    .fontColor(Tokens.TEXT_TERTIARY)
                    .width('100%')
                    .margin({ top: Tokens.GAP })
                }
              }
              .width('100%')
              .constraintSize({ maxWidth: 960 })
              .padding({
                left: PageInsets.HORIZONTAL,
                right: PageInsets.HORIZONTAL,
                bottom: Tokens.SPACE_24
              })
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .onDidScroll((offset: number) => {
              const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
              if (Math.abs(next - this.headerFade) > 0.03) {
                this.headerFade = next;
              }
            })
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
