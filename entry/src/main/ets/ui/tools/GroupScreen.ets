import { PageInsets } from '../theme/PageInsets';
import { showFeedback } from '../components/AppFeedback';
import { RosterPicker } from '../components/RosterPicker';
import { ClassMember, LeagueMember } from '../../data/member/ClassMember';
import { Services } from '../../app/Services';
import { DrawSession } from '../../app/DrawSession';
import { pasteboard } from '@kit.BasicServicesKit';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { DrawEntry, DrawResult } from '../../features/draw/DrawModels';
import {
  GroupConfig,
  GroupError,
  GroupMember,
  GroupMode,
  groupModeLabel,
  GroupResult,
  GroupSource,
  GroupStep,
  GroupValidation,
  MemberGroup
} from '../../features/group/GroupModels';
import { defaultGroupRandom, GroupEngine } from '../../features/group/GroupEngine';
import { GroupConfigCodec } from '../../features/group/GroupCodec';
import { GroupExportFactory, ExportCardSpec, ExportNaming } from '../../features/export/ExportCard';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';
import { GlassBar } from '../components/GlassBar';
import { ExportPreview } from './ExportPreview';

/**
 * 分组工具（独立）：配置（全班/最近抽签/手动选择、方式、打乱）→ 结果（组卡）→ 导出。
 *
 * 「最近抽签」读取本机持久化的最近一次抽签结果（DrawSession → DrawLastStore，按 sid 隔离），
 * 不依赖从抽签页跳转，进程重启后仍可用；参数写回 `userdata.group`
 * （source/mode/n/shuffle/sel，保留未知字段；「全班」仍等价于 names + 全选，不新增枚举）。
 */
@Component
export struct GroupScreen {
  onClose: () => void = () => {
  };

  @State private step: GroupStep = GroupStep.CONFIG;
  private scroller: Scroller = new Scroller();
  @State private source: GroupSource = GroupSource.PREV;
  @State private mode: GroupMode = GroupMode.GROUPS;
  @State private n: number = GroupConfig.DEFAULT_N;
  @State private shuffle: boolean = false;
  @State private membersList: ClassMember[] = [];
  @State private leagueSeats: number[] = [];
  @State private seats: number[] = [];
  @State private names: string[] = [];
  @State private selected: number[] = [];
  @State private lastResult: DrawResult | undefined = undefined;
  @State private lastAt: number = 0;
  @State private groups: GroupResult | undefined = undefined;
  @State private errorMsg: string = '';
  @State private showExport: boolean = false;
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

  aboutToAppear(): void {
    this.restoreConfig();
    this.loadRoster();
    this.loadLastDraw();
  }

  private restoreConfig(): void {
    const sections: Blob = Services.userdata.currentSections();
    const config: GroupConfig = GroupConfigCodec.fromJson(JsonBlob.get(sections, 'group'));
    this.source = config.source;
    this.mode = config.mode;
    this.n = config.n;
    this.shuffle = config.shuffle;
    this.selected = config.selectedSeats.slice(0);
  }

  private async loadRoster(): Promise<void> {
    const loaded = await Services.members.load(false);
    this.membersList = loaded.members;
    const league = await Services.league.load(false);
    this.leagueSeats = league.members.map((m: LeagueMember) => m.seat);
    const seats: number[] = [];
    const names: string[] = [];
    for (let i = 0; i < loaded.members.length; i++) {
      seats.push(loaded.members[i].seat);
      names.push(loaded.members[i].name);
    }
    this.seats = seats;
    this.names = names;
    if (this.selected.length === 0 && seats.length > 0 && this.source === GroupSource.NAMES) {
      this.selected = seats.slice(0);
    }
  }

  /** 读「最近抽签」：内存命中优先，否则读本机快照（跨进程重启仍可用）。 */
  private async loadLastDraw(): Promise<void> {
    const loaded: DrawResult | undefined = await DrawSession.load();
    this.lastResult = loaded;
    this.lastAt = DrawSession.lastAt;
  }

  private currentConfig(): GroupConfig {
    const config: GroupConfig = new GroupConfig();
    config.source = this.source;
    config.mode = this.mode;
    config.n = this.n;
    config.shuffle = this.shuffle;
    config.selectedSeats = this.selected.slice(0);
    return config;
  }

  private async persistConfig(): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const existing: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'group'));
    next['group'] = GroupConfigCodec.toJson(this.currentConfig(), existing);
    await Services.userdata.updateCurrent(next);
  }

  private nameOf(seat: number): string {
    const index: number = this.seats.indexOf(seat);
    return index >= 0 && index < this.names.length ? this.names[index] : '';
  }

  /** 当前来源的成员（最近抽签按快照序号 + 快照姓名/班级名单兜底）。 */
  private members(): GroupMember[] {
    if (this.source === GroupSource.NAMES) {
      const out: GroupMember[] = [];
      for (let i = 0; i < this.selected.length; i++) {
        const seat: number = this.selected[i];
        out.push(new GroupMember(seat, this.nameOf(seat)));
      }
      return out;
    }
    const last: DrawResult | undefined = this.lastResult;
    if (last === undefined) {
      return [];
    }
    const out: GroupMember[] = [];
    for (let i = 0; i < last.entries.length; i++) {
      const entry: DrawEntry = last.entries[i];
      // 名称优先级：抽签快照里的名称（名称映射/名单派生）> 当前班级名单派生名 > 空
      const name: string = entry.name.length > 0 ? entry.name : this.nameOf(entry.number);
      out.push(new GroupMember(entry.number, name));
    }
    return out;
  }

  /** 已选集合 == 全班集合（契约：全班不新增 source 值）。 */
  private isAllSelected(): boolean {
    return this.source === GroupSource.NAMES && this.seats.length > 0
      && this.selected.length === this.seats.length;
  }

  private isManualSelected(): boolean {
    return this.source === GroupSource.NAMES && !this.isAllSelected();
  }

  /** 「最近抽签」chip 文案：人数 + 时间（无结果时只显示标题并置灰）。 */
  private recentLabel(): string {
    const last: DrawResult | undefined = this.lastResult;
    if (last === undefined) {
      return '最近抽签';
    }
    return '最近抽签 ' + last.entries.length + ' 人' + GroupScreen.timeSuffix(this.lastAt);
  }

  private recentHint(): string {
    const last: DrawResult | undefined = this.lastResult;
    if (last === undefined) {
      return '还没有抽签结果，请先到「抽签」抽一次；抽签结果会保存在本机';
    }
    return '最近一次抽签 ' + last.entries.length + ' 个序号' + GroupScreen.timeSuffix(this.lastAt)
      + '，可直接沿用';
  }

  private namesHint(): string {
    if (this.isAllSelected()) {
      return '已选全班 ' + this.selected.length + ' 人';
    }
    if (this.selected.length === 0) {
      return '还没有选人：可点「全选」取全班，或逐个勾选座号';
    }
    return '已选 ' + this.selected.length + ' 人';
  }

  private static timeSuffix(at: number): string {
    if (at <= 0) {
      return '';
    }
    const date: Date = new Date(at);
    return ' · ' + GroupScreen.pad2(date.getMonth() + 1) + '-' + GroupScreen.pad2(date.getDate())
      + ' ' + GroupScreen.pad2(date.getHours()) + ':' + GroupScreen.pad2(date.getMinutes());
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + value : '' + value;
  }

  private plannedGroups(): number {
    return GroupEngine.groupCount(this.members().length, this.currentConfig());
  }

  private startGroup(): void {
    const members: GroupMember[] = this.members();
    const config: GroupConfig = this.currentConfig();
    const validation: GroupValidation = GroupEngine.validate(members, config);
    if (!validation.ok) {
      const error: GroupError | undefined = validation.error;
      this.errorMsg = error !== undefined ? error.message : '无法分组';
      return;
    }
    this.errorMsg = '';
    this.groups = GroupEngine.group(members, config, defaultGroupRandom());
    this.step = GroupStep.RESULT;
    this.persistConfig();
  }

  private regroup(): void {
    if (this.groups === undefined) {
      return;
    }
    const config: GroupConfig = this.currentConfig();
    this.groups = GroupEngine.group(this.members(), config, defaultGroupRandom());
  }

  private openExport(): void {
    if (this.groups === undefined) {
      return;
    }
    this.exportSpec = GroupExportFactory.create(this.groups, Date.now(), ExportNaming.randomSuffix());
    this.showExport = true;
  }

  /** 复制分组结果纯文本（与网页/小程序「复制」同口径，不含学号）。 */
  private async copyResult(): Promise<void> {
    if (this.groups === undefined) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        this.groups.copyText());
      await pasteboard.getSystemPasteboard().setData(data);
      showFeedback(this.getUIContext(), '已复制分组结果');
    } catch (e) {
      showFeedback(this.getUIContext(), '复制失败，请改用导出图片');
    }
  }

  /** 「全班」快捷：等价于 names + 全选（不新增 source 枚举）。 */
  @Builder
  allSourceChip() {
    Text('全班' + (this.seats.length > 0 ? ' ' + this.seats.length + ' 人' : ''))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.isAllSelected() ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.isAllSelected() ? Tokens.SLATE_BLUE : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.source = GroupSource.NAMES;
        this.selected = this.seats.slice(0);
        this.errorMsg = '';
        this.persistConfig();
      })
  }

  /** 「最近抽签」来源：无快照时置灰且不响应点击。 */
  @Builder
  prevSourceChip() {
    Text(this.recentLabel())
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.lastResult === undefined ? Tokens.TEXT_TERTIARY
        : (this.source === GroupSource.PREV ? '#FFFFFF' : Tokens.TEXT_SECONDARY))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.lastResult !== undefined && this.source === GroupSource.PREV
        ? Tokens.MIST_TEAL : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .opacity(this.lastResult === undefined ? 0.45 : 1)
      .onClick(() => {
        if (this.lastResult === undefined) {
          return;
        }
        this.source = GroupSource.PREV;
        this.errorMsg = '';
        this.persistConfig();
      })
  }

  /** 「手动选择」：展开班级名单座号。 */
  @Builder
  manualSourceChip() {
    Text('手动选择')
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.isManualSelected() ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.isManualSelected() ? Tokens.MIST_TEAL : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.source = GroupSource.NAMES;
        this.errorMsg = '';
        this.persistConfig();
      })
  }

  /** 分组方式 chip（同上，active 内部计算）。 */
  @Builder
  modeChip(mode: GroupMode) {
    Text(groupModeLabel(mode))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.mode === mode ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.mode === mode ? Tokens.MIST_TEAL : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.mode = mode;
        this.persistConfig();
      })
  }

  @Builder
  memberText(member: GroupMember) {
    Text(member.label())
      .fontSize(Tokens.F_CAPTION)
      .fontColor(Tokens.TEXT_PRIMARY)
      .margin({ right: 10, top: 6 })
  }

  @Builder
  groupCard(group: MemberGroup) {
    Column() {
      Row() {
        Text(group.label())
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text(group.size() + ' 人')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(group.members, (member: GroupMember) => {
          this.memberText(member)
        }, (member: GroupMember) => '' + group.index + '_' + member.seat)
      }
      .width('100%')
    }
    .width('48.5%')
    .padding(12)
    .margin({ bottom: 10 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  configStep() {
    Scroll(this.scroller) {
      Column() {
        Column() {
          Text('成员来源')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.allSourceChip()
            this.prevSourceChip()
            this.manualSourceChip()
          }
          .width('100%')

          Text(this.source === GroupSource.PREV ? this.recentHint() : this.namesHint())
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.source === GroupSource.PREV && this.lastResult === undefined
              ? Tokens.DANGER : Tokens.TEXT_TERTIARY)
            .width('100%')

          if (this.source === GroupSource.NAMES) {
            RosterPicker({ members: this.membersList, leagueSeats: this.leagueSeats, selected: this.selected,
              onSelect: (seats: number[]) => { this.selected = seats; this.persistConfig(); } })
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)

        Column() {
          Text('分组方式')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 8 })
          Row() {
            this.modeChip(GroupMode.GROUPS)
            this.modeChip(GroupMode.PER_GROUP)
          }
          .width('100%')

          Row() {
            Column() {
              Text(this.mode === GroupMode.GROUPS ? '组数' : '每组人数')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
              TextInput({ text: '' + this.n })
                .type(InputType.Number)
                .height(44)
                .margin({ top: 4 })
                .backgroundColor(Tokens.CONTROL)
                .borderRadius(10)
                .fontSize(Tokens.F_BODY)
                .onChange((text: string) => {
                  const parsed: number = Number(text);
                  if (Number.isFinite(parsed) && parsed > 0) {
                    this.n = Math.round(parsed);
                  }
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text('打乱成员')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
              Toggle({ type: ToggleType.Switch, isOn: this.shuffle })
                .margin({ top: 6 })
                .selectedColor(Tokens.MIST_TEAL)
                .onChange((isOn: boolean) => {
                  this.shuffle = isOn;
                  this.persistConfig();
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width(120)
          }
          .width('100%')
          .margin({ top: 6 })

          Text('将分成 ' + this.plannedGroups() + ' 组 · ' + this.members().length + ' 人 · '
            + (this.shuffle ? '打乱后随机分配' : '按原顺序轮流分配'))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 14 })
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.DANGER)
            .width('100%')
            .margin({ top: 12 })
        }

        Button('开始分组')
          .width('100%')
          .height(48)
          .margin({ top: 20 })
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .fontSize(Tokens.F_BODY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.startGroup();
          })
      }
      .width('100%')
      .padding({ left: PageInsets.HORIZONTAL, right: PageInsets.HORIZONTAL, bottom: 24 })
    }
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

  @Builder
  resultStep() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          Text(this.groups !== undefined ? this.groups.summary() : '')
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
            .width('100%')

          Text(this.groups !== undefined
            ? this.groups.snapshot.sourceLabel + ' · ' + this.groups.snapshot.modeLabel + ' · ' + this.groups.snapshot.innerLabel
            : '')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 4, bottom: 12 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.groups !== undefined ? this.groups.groups : [], (group: MemberGroup) => {
              this.groupCard(group)
            }, (group: MemberGroup) => 'group_' + group.index + '_' + group.size())
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: PageInsets.HORIZONTAL, right: PageInsets.HORIZONTAL, bottom: 20 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .onDidScroll((offset: number) => {
        const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
        if (Math.abs(next - this.headerFade) > 0.03) {
          this.headerFade = next;
        }
      })

      GlassBar() {
        Button('重新分组')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CONTROL)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.regroup();
          })
        Button('复制')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CONTROL)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.copyResult();
          })
        Button('导出图片')
          .layoutWeight(2)
          .height(48)
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.openExport();
          })
      }
    }
    .layoutWeight(1)
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
      progress: this.headerFade,
        title: this.step === GroupStep.CONFIG ? '分组' : '分组结果',
        actionText: this.step === GroupStep.RESULT ? '调整参数' : '',
        scroller: this.scroller,
        onBack: () => {
          if (this.step === GroupStep.RESULT) {
            this.step = GroupStep.CONFIG;
          } else {
            this.onClose();
          }
        },
        onAction: () => {
          this.step = GroupStep.CONFIG;
        }
      }) {
        Column() {
          if (this.step === GroupStep.CONFIG) {
            this.configStep()
          } else {
            this.resultStep()
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0 })
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
