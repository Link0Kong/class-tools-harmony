import { Services } from '../../app/Services';
import { DrawSession } from '../../app/DrawSession';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { DrawEntry, DrawResult } from '../../features/draw/DrawModels';
import {
  GroupConfig,
  GroupError,
  GroupErrorCode,
  GroupMember,
  GroupMode,
  groupModeLabel,
  GroupResult,
  GroupSource,
  groupSourceLabel,
  GroupStep,
  GroupValidation,
  MemberGroup
} from '../../features/group/GroupModels';
import { defaultGroupRandom, GroupEngine } from '../../features/group/GroupEngine';
import { GroupConfigCodec } from '../../features/group/GroupCodec';
import { GroupExportFactory, ExportCardSpec, ExportNaming } from '../../features/export/ExportCard';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';
import { ExportPreview } from './ExportPreview';

/**
 * 分组工具：配置（来源/方式/打乱/名单选择）→ 结果（两列组卡）→ 导出。
 *
 * 来源「上一步抽签序号」使用本次会话的抽签结果（DrawSession，进程内）；
 * 参数写回 `userdata.group`（source/mode/n/shuffle/sel，保留未知字段）。
 */
@Component
export struct GroupScreen {
  onClose: () => void = () => {
  };

  @State private step: GroupStep = GroupStep.CONFIG;
  @State private source: GroupSource = GroupSource.PREV;
  @State private mode: GroupMode = GroupMode.GROUPS;
  @State private n: number = GroupConfig.DEFAULT_N;
  @State private shuffle: boolean = false;
  @State private seats: number[] = [];
  @State private names: string[] = [];
  @State private selected: number[] = [];
  @State private groups: GroupResult | undefined = undefined;
  @State private errorMsg: string = '';
  @State private showExport: boolean = false;
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

  aboutToAppear(): void {
    this.restoreConfig();
    this.loadRoster();
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

  /** 当前来源的成员。 */
  private members(): GroupMember[] {
    if (this.source === GroupSource.NAMES) {
      const out: GroupMember[] = [];
      for (let i = 0; i < this.selected.length; i++) {
        const seat: number = this.selected[i];
        out.push(new GroupMember(seat, this.nameOf(seat)));
      }
      return out;
    }
    const last: DrawResult | undefined = DrawSession.lastResult;
    if (last === undefined) {
      return [];
    }
    const out: GroupMember[] = [];
    for (let i = 0; i < last.entries.length; i++) {
      const entry: DrawEntry = last.entries[i];
      out.push(new GroupMember(entry.number, entry.name));
    }
    return out;
  }

  private plannedGroups(): number {
    return GroupEngine.groupCount(this.members().length, this.currentConfig());
  }

  private toggleSeat(seat: number): void {
    const index: number = this.selected.indexOf(seat);
    if (index >= 0) {
      this.selected.splice(index, 1);
    } else {
      this.selected.push(seat);
    }
    this.selected = this.selected.slice(0);
    this.persistConfig();
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

  /** 来源 chip：active 在内部按 this.source 计算（@Builder 值参数不参与刷新）。 */
  @Builder
  sourceChip(source: GroupSource) {
    Text(groupSourceLabel(source))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.source === source ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.source === source ? Tokens.MIST_TEAL : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.source = source;
        if (source === GroupSource.NAMES && this.selected.length === 0) {
          this.selected = this.seats.slice(0);
        }
        this.persistConfig();
      })
  }

  /** 分组方式 chip（同上，active 内部计算）。 */
  @Builder
  modeChip(mode: GroupMode) {
    Text(groupModeLabel(mode))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.mode === mode ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(this.mode === mode ? Tokens.MIST_TEAL : Tokens.BG)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.mode = mode;
        this.persistConfig();
      })
  }

  @Builder
  seatChip(seat: number) {
    Text('' + seat)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.selected.indexOf(seat) >= 0 ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .width(44)
      .height(34)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.selected.indexOf(seat) >= 0 ? Tokens.SLATE_BLUE : Tokens.BG)
      .borderRadius(8)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.toggleSeat(seat);
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
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  configStep() {
    Scroll() {
      Column() {
        Column() {
          Text('成员来源')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 8 })
          Row() {
            this.sourceChip(GroupSource.PREV)
            this.sourceChip(GroupSource.NAMES)
          }
          .width('100%')

          Text(this.source === GroupSource.PREV
            ? (DrawSession.lastResult !== undefined
              ? '本次抽签 ' + DrawSession.lastResult.entries.length + ' 个序号'
              : '还没有抽签结果，请先到「抽签」抽一次')
            : '已选 ' + this.selected.length + ' 人')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.source === GroupSource.PREV && DrawSession.lastResult === undefined
              ? Tokens.DANGER : Tokens.TEXT_TERTIARY)
            .width('100%')

          if (this.source === GroupSource.NAMES) {
            Row() {
              Text('全选')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .margin({ right: 14 })
                .onClick(() => {
                  this.selected = this.seats.slice(0);
                  this.persistConfig();
                })
              Text('清空')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .onClick(() => {
                  this.selected = [];
                  this.persistConfig();
                })
            }
            .width('100%')
            .margin({ top: 10, bottom: 6 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.seats, (seat: number) => {
                this.seatChip(seat)
              }, (seat: number) => 'seat_' + seat)
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Tokens.CARD)
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
                .backgroundColor(Tokens.BG)
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
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
    }
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  resultStep() {
    Column() {
      Scroll() {
        Column() {
          Text(this.groups !== undefined
            ? '共 ' + this.groups.snapshot.total + ' 人 · ' + this.groups.snapshot.groupCount + ' 组'
            : '')
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
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 20 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Button('调整参数')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CARD)
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.step = GroupStep.CONFIG;
          })
        Button('重新分组')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CARD)
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.regroup();
          })
        Button('导出图片')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.openExport();
          })
      }
      .width('100%')
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 16, top: 10 })
    }
    .layoutWeight(1)
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: this.step === GroupStep.CONFIG ? '分组 · 配置' : '分组 · 结果',
          onBack: () => {
            if (this.step === GroupStep.RESULT) {
              this.step = GroupStep.CONFIG;
            } else {
              this.onClose();
            }
          }
        })

        if (this.step === GroupStep.CONFIG) {
          this.configStep()
        } else {
          this.resultStep()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Tokens.BG)

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
