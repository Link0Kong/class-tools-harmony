import { Services } from '../../app/Services';
import { ClassMember, LeagueMember } from '../../data/member/ClassMember';
import { ClassMembersResult } from '../../data/member/ClassMembersRepository';
import { ClassLeagueResult } from '../../data/member/ClassLeagueRepository';
import { Blob } from '../../data/sync/JsonBlob';
import { ExportCardSpec, ExportNaming, ExportParam } from '../../features/export/ExportCard';
import { RollCodec, RollCounts, RollLogic, RollRow, RollScope, RollState, RollStatus } from '../../features/roll/RollModels';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';
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
  @State private notice: string = '';
  @State private showExport: boolean = false;
  @State private selSeats: number[] = [];
  @State private pickerOpen: boolean = false;
  @State private resetConfirm: boolean = false;
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

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
    return RollLogic.intersect(base, this.selSeats);
  }

  private toggleSelSeat(seat: number): void {
    const index: number = this.selSeats.indexOf(seat);
    if (index >= 0) {
      this.selSeats.splice(index, 1);
    } else {
      this.selSeats.push(seat);
    }
    this.selSeats = this.selSeats.slice(0);
    if (this.selSeats.length === 0) {
      this.statuses = RollLogic.clear(this.statuses, new Set<number>());
    }
  }

  private async saveRoster(): Promise<void> {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.pickerOpen = false;
    });
    this.schedulePersist();
  }

  private openPicker(): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.pickerOpen = true;
    });
  }

  private openRosterAll(): void {
    this.selSeats = [];
    this.schedulePersist();
  }

  private rows(): RollRow[] {
    return RollLogic.rows(this.members, this.statuses, this.scopeSeats());
  }

  private counts(): RollCounts {
    return RollLogic.counts(this.rows());
  }

  private async persist(): Promise<void> {
    const state: RollState = RollCodec.read(Services.userdata.currentSections());
    state.rollSt = this.statuses;
    state.rollSel = this.selSeats.slice(0);
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
    this.notice = '';
    this.schedulePersist();
  }

  private reset(): void {
    if (!this.resetConfirm) {
      this.resetConfirm = true;
      this.notice = '再点一次「重置」确认清空当前范围';
      setTimeout(() => {
        this.resetConfirm = false;
      }, 3000);
      return;
    }
    this.resetConfirm = false;
    this.statuses = RollLogic.clear(this.statuses, this.scopeSeats());
    this.notice = '已重置' + this.scope;
    this.schedulePersist();
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
      .backgroundColor(this.scope === scope ? Tokens.SLATE_BLUE : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.scope = scope;
        this.notice = '';
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
        .backgroundColor(row.status === RollStatus.DONE ? Tokens.MIST_TEAL : Tokens.BG)
        .borderRadius(8)
        .margin({ right: 6 })
        .onClick(() => {
          this.mark(row.seat, RollStatus.DONE);
        })
      Text('假')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(row.status === RollStatus.ABSENT ? '#FFFFFF' : Tokens.WARM_SAND)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(row.status === RollStatus.ABSENT ? Tokens.WARM_SAND : Tokens.BG)
        .borderRadius(8)
        .onClick(() => {
          this.mark(row.seat, RollStatus.ABSENT);
        })
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: '点名',
          actionText: '导出',
          onBack: () => {
            this.onClose();
          },
          onAction: () => {
            this.openExport();
          }
        })

        Row({ space: 6 }) {
          this.scopeChip(RollScope.ALL)
          this.scopeChip(RollScope.COMMITTEE)
          this.scopeChip(RollScope.LEAGUE)
          Blank()
          Text('名单' + (this.selSeats.length > 0 ? ' ' + this.selSeats.length : ''))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
            .padding({ left: 6, right: 10 } )
            .onClick(() => {
              this.openPicker();
            })
          Text('重置')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.resetConfirm ? Tokens.DANGER : Tokens.TEXT_SECONDARY)
            .onClick(() => {
              this.reset();
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
          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
          }
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
          List() {
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
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Tokens.BG)

      if (this.pickerOpen) {
        Column() {
          Column() {
            Row() {
              Text('点名名单')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
              Text(' 已选 ' + this.selSeats.length + ' 人')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
              Blank()
              Text('关闭')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
                    this.pickerOpen = false;
                  });
                })
            }
            .width('100%')
            Row({ space: 10 }) {
              Text('全部')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(this.selSeats.length === 0 ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY)
                .onClick(() => {
                  this.openRosterAll();
                })
              Text('清空')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
                .onClick(() => {
                  this.selSeats = [];
                  this.schedulePersist();
                })
              Blank()
              Button('确定')
                .height(32)
                .fontSize(Tokens.F_CAPTION)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.saveRoster();
                })
            }
            .width('100%')
            .margin({ top: 8 })
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.members, (member: ClassMember) => {
                  Text(member.name)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(this.selSeats.indexOf(member.seat) >= 0 ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .margin({ right: 6, bottom: 6 })
                    .backgroundColor(this.selSeats.indexOf(member.seat) >= 0 ? Tokens.MIST_TEAL : Tokens.BG)
                    .borderRadius(8)
                    .onClick(() => {
                      this.toggleSelSeat(member.seat);
                    })
                }, (member: ClassMember) => 'rs_' + member.seat + (this.selSeats.indexOf(member.seat) >= 0 ? '_y' : '_n'))
              }
              .width('100%')
            }
            .layoutWeight(1)
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .margin({ top: 6 })
          }
          .width('100%')
          .height('80%')
          .padding(16)
          .backgroundColor(Tokens.CARD)
          .borderRadius(Tokens.RADIUS_CARD)
          .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.End)
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
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
