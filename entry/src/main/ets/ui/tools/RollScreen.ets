import { showFeedback } from '../components/AppFeedback';
﻿import { RosterPicker } from '../components/RosterPicker';
import { Services } from '../../app/Services';
import { ClassMember, LeagueMember } from '../../data/member/ClassMember';
import { ClassMembersResult } from '../../data/member/ClassMembersRepository';
import { ClassLeagueResult } from '../../data/member/ClassLeagueRepository';
import { Blob } from '../../data/sync/JsonBlob';
import { ExportCardSpec, ExportNaming, ExportParam } from '../../features/export/ExportCard';
import { RollCodec, RollCounts, RollLogic, RollRow, RollScope, RollState, RollStatus } from '../../features/roll/RollModels';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Immersive } from '../theme/Immersive';
import { PageHeader } from '../components/PageHeader';
import { GlassSheet } from '../components/GlassSheet';
import { ExportPreview } from './ExportPreview';

/**
 * 点名工具：按范围点名（到 / 假），已处理沉底，统计 + 导出汇总。
 *
 * 数据：`userdata.roster` 的 `rollSt`（座号 → 到/假）与 `rollSel`；名单来自 `class_members`，
 * 团员范围来自 `class_league`。状态本机即时写回（整段 roster 保留其它字段）。
 */
@Component
export struct RollScreen {
  onClose: () => void = () => {
  };

  @State private members: ClassMember[] = [];
  @State private leagueSeats: number[] = [];
  @State private statuses: Map<number, string> = new Map<number, string>();
  @State private scope: RollScope = RollScope.ALL;
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private showExport: boolean = false;
  @State private selSeats: number[] = [];
  @State private draftSeats: number[] = [];
  @State private pickerOpen: boolean = false;
  @State private resetConfirm: boolean = false;
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

  private scroller: Scroller = new Scroller();
  private persistTimer: number = -1;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = this.members.length === 0;
    const state: RollState = RollCodec.read(Services.userdata.currentSections());
    this.statuses = state.rollSt;
    this.selSeats = state.rollSel.slice(0);
    const membersResult: ClassMembersResult = await Services.members.load(false);
    this.members = membersResult.members;
    if (this.selSeats.length === 0 && this.statuses.size > 0) {
      this.selSeats = this.members.map((member: ClassMember) => member.seat);
    }
    const leagueResult: ClassLeagueResult = await Services.league.load(false);
    const seats: number[] = [];
    for (let i = 0; i < leagueResult.members.length; i++) {
      seats.push(leagueResult.members[i].seat);
    }
    this.leagueSeats = seats;
    if (!membersResult.ok) {
      this.errorMsg = membersResult.message;
    }
    this.loading = false;
  }

  private scopeSeats(): Set<number> {
    const base: Set<number> = RollLogic.scopeSeats(this.members, this.leagueSeats, this.scope);
    return new Set<number>(this.selSeats.filter((seat: number) => this.scope === RollScope.ALL || base.has(seat)));
  }

  private async saveRoster(): Promise<void> {
    this.selSeats = this.draftSeats.slice().sort((a: number, b: number) => a - b);
    const kept: Map<number, string> = new Map<number, string>();
    this.selSeats.forEach((seat: number) => {
      const previous: string | undefined = this.statuses.get(seat);
      if (previous !== undefined) kept.set(seat, previous);
    });
    this.statuses = kept;
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.pickerOpen = false;
    });
    this.schedulePersist();
  }

  private openPicker(): void {
    this.draftSeats = this.selSeats.slice();
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.pickerOpen = true;
    });
  }

  private rows(): RollRow[] {
    const seats: Set<number> = this.scopeSeats();
    return seats.size > 0 ? RollLogic.rows(this.members, this.statuses, seats) : [];
  }

  private counts(): RollCounts {
    return RollLogic.counts(this.rows());
  }

  private async persist(): Promise<void> {
    const state: RollState = RollCodec.read(Services.userdata.currentSections());
    state.rollSt = this.statuses;
    state.rollSel = this.selSeats.slice(0);
    state.rollNames = this.members.filter((m: ClassMember) => state.rollSel.indexOf(m.seat) >= 0)
      .sort((a: ClassMember, b: ClassMember) => a.seat - b.seat)
      .map((m: ClassMember) => m.seat + ' ' + m.name).join('\n');
    const next: Blob = RollCodec.write(Services.userdata.currentSections(), state);
    await Services.userdata.updateCurrent(next);
  }

  private schedulePersist(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1;
      this.persist();
    }, 400);
  }

  private mark(seat: number, status: string): void {
    this.statuses = RollLogic.toggle(this.statuses, seat, status);
    this.schedulePersist();
  }

  private reset(): void {
    this.resetConfirm = false;
    this.statuses = RollLogic.clear(this.statuses, this.scopeSeats());
    showFeedback(this.getUIContext(), '已重置' + this.scope);
    this.schedulePersist();
  }

  private confirmReset(): void {
    if (this.scopeSeats().size === 0) return;
    this.getUIContext().showAlertDialog({
      title: '重置点名',
      message: '清空「' + this.scope + '」范围的到 / 假记录？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '重置',
        fontColor: Tokens.DANGER,
        action: () => {
          this.reset();
        }
      },
      systemMaterial: Immersive.dialogMaterial()
    });
  }

  private openExport(): void {
    const counts: RollCounts = this.counts();
    const rows: RollRow[] = this.rows();
    const now: number = Date.now();
    const spec: ExportCardSpec = new ExportCardSpec();
    spec.title = '点名汇总';
    spec.subtitle = this.scope + ' · 应到 ' + counts.total + ' 人';
    spec.recordId = ExportNaming.recordId('ROLL', now, ExportNaming.randomSuffix());
    spec.fileName = ExportNaming.safeName('点名汇总_' + ExportNaming.stamp(now) + '_'
      + this.scope + '_到' + counts.done + '_假' + counts.absent + '.png');
    spec.params = [
      new ExportParam('应到', '' + counts.total),
      new ExportParam('到', '' + counts.done),
      new ExportParam('假', '' + counts.absent),
      new ExportParam('未点', '' + counts.pending),
      new ExportParam('完成度', counts.progress() + '%')
    ];
    const lines: string[] = [];
    lines.push('到 ' + counts.done + ' 人 · 假 ' + counts.absent + ' 人 · 未点 ' + counts.pending + ' 人');
    const absentNames: string[] = RollLogic.namesOf(rows, RollStatus.ABSENT);
    if (absentNames.length > 0) {
      lines.push('请假：' + absentNames.join('、'));
    }
    const pendingNames: string[] = RollLogic.namesOf(rows, '');
    if (pendingNames.length > 0) {
      lines.push('未点：' + pendingNames.join('、'));
    }
    spec.linesLabel = '点名明细';
    spec.lines = lines;
    spec.footer = '生成时间 ' + ExportNaming.timeText(now) + ' · ' + this.scope;
    spec.generatedAt = now;
    this.exportSpec = spec;
    this.showExport = true;
  }

  private badgeColor(status: string): string {
    if (status === RollStatus.DONE) {
      return Tokens.MIST_TEAL;
    }
    if (status === RollStatus.ABSENT) {
      return Tokens.WARM_SAND;
    }
    return Tokens.TEXT_TERTIARY;
  }

  @Builder
  scopeChip(scope: RollScope) {
    Text(scope)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.scope === scope ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.scope === scope ? Tokens.SLATE_BLUE : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.scope = scope;
      })
  }

  @Builder
  summaryTile(kind: string) {
    Column() {
      Text(this.tileValue(kind))
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tileColor(kind))
      Text(this.tileLabel(kind))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .margin({ left: 6, right: 6 })
  }

  private tileValue(kind: string): string {
    const counts: RollCounts = this.counts();
    if (kind === 'done') {
      return '' + counts.done;
    }
    if (kind === 'absent') {
      return '' + counts.absent;
    }
    return '' + counts.pending;
  }

  private tileLabel(kind: string): string {
    if (kind === 'done') {
      return '到';
    }
    if (kind === 'absent') {
      return '假';
    }
    return '未点';
  }

  private tileColor(kind: string): string {
    if (kind === 'done') {
      return Tokens.MIST_TEAL;
    }
    if (kind === 'absent') {
      return Tokens.WARM_SAND;
    }
    return Tokens.TEXT_TERTIARY;
  }

  @Builder
  rowItem(row: RollRow) {
    Row() {
      Text('' + row.seat)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(34)
      Text(row.name)
        .fontSize(Tokens.F_BODY)
        .fontColor(row.processed ? Tokens.TEXT_TERTIARY : Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(1)

      Text('到')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(row.status === RollStatus.DONE ? '#FFFFFF' : Tokens.MIST_TEAL)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(row.status === RollStatus.DONE ? Tokens.MIST_TEAL : Tokens.CONTROL)
        .borderRadius(8)
        .margin({ right: 6 })
        .onClick(() => {
          this.mark(row.seat, RollStatus.DONE);
        })
      Text('假')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(row.status === RollStatus.ABSENT ? '#FFFFFF' : Tokens.WARM_SAND)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(row.status === RollStatus.ABSENT ? Tokens.WARM_SAND : Tokens.CONTROL)
        .borderRadius(8)
        .onClick(() => {
          this.mark(row.seat, RollStatus.ABSENT);
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
      progress: this.headerFade,
        title: '点名',
        actionText: '导出',
        actionText2: '重置',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.openExport();
        },
        onAction2: () => {
          this.confirmReset();
        }
      }) {
        Column() {
        Row({ space: 6 }) {
          this.scopeChip(RollScope.ALL)
          this.scopeChip(RollScope.COMMITTEE)
          this.scopeChip(RollScope.LEAGUE)
          Blank()
          Text('编辑名单')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(Tokens.CONTROL)
            .border({ width: 0.5, color: Tokens.CARD_EDGE })
            .borderRadius(Tokens.RADIUS_PILL)
            .onClick(() => {
              this.openPicker();
            })
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })

        Text('应点 ' + this.rows().length + ' 人' + (this.selSeats.length > 0 ? '（自定义名单）' : ''))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
          .margin({ top: 4 })

        Row() {
          this.summaryTile('done')
          this.summaryTile('absent')
          this.summaryTile('pending')
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING - 6, right: Tokens.PAGE_PADDING - 6 })
        .margin({ top: 10 })

        Row() {
          Text('完成度 ' + this.counts().progress() + '%')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
          Blank()
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
        .margin({ top: 6 })

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg.length > 0 && this.members.length === 0) {
          Text(this.errorMsg)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.DANGER)
            .width('100%')
            .padding(Tokens.PAGE_PADDING)
        } else {
          List({ scroller: this.scroller }) {
            ForEach(this.rows(), (row: RollRow) => {
              ListItem() {
                this.rowItem(row)
              }
              .transition(Motion.listItem())
            }, (row: RollRow) => '' + row.seat + '_' + row.status)
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 6 })
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
          .divider({ strokeWidth: 0.5, color: Tokens.DIVIDER })
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
        .padding({ top: 0 })
      }

      if (this.pickerOpen) {
        GlassSheet({ panelHeight: '80%' }) {
          Row() {
            Text('点名名单')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
            Text(' 已选 ' + this.draftSeats.length + ' 人')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
            Blank()
            Text('取消')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
              .padding({ left: 10, right: 4, top: 4, bottom: 4 })
              .onClick(() => {
                this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
                  this.pickerOpen = false;
                });
              })
          }
          .width('100%')
          Button('保存名单')
            .height(36).fontSize(Tokens.F_LABEL).backgroundColor('#356C61')
            .alignSelf(ItemAlign.End).onClick(() => { this.saveRoster(); })
          Scroll() {
            RosterPicker({ members: this.members, leagueSeats: this.leagueSeats, selected: this.draftSeats,
              onSelect: (seats: number[]) => { this.draftSeats = seats; } })
          }.width('100%').layoutWeight(1).align(Alignment.Top)
        }
      }

      if (this.showExport) {
        ExportPreview({
          spec: this.exportSpec,
          onClose: () => {
            this.showExport = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
