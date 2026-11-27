import { PageInsets } from '../theme/PageInsets';
﻿import { RosterPicker } from '../components/RosterPicker';
import { ClassMember, LeagueMember } from '../../data/member/ClassMember';
import { Services } from '../../app/Services';
import { Blob, JsonBlob, JsonValue } from '../../data/sync/JsonBlob';
import {
  DrawConfig,
  DrawEntry,
  DrawPoolSource,
  DrawReceipt,
  DrawResult,
  DrawSortMode,
  drawSortLabel
} from '../../features/draw/DrawModels';
import { defaultDrawRandom } from '../../features/draw/DrawRandom';
import { DrawProofRound, ProofEvent } from '../../data/draw/DrawProofPublisher';
import { NativeShare } from '../../features/share/NativeShare';
import { DrawConfigCodec } from '../../features/draw/DrawConfigCodec';
import { DrawStep, DrawTransition, DrawWorkflow, DrawWorkflowState } from '../../features/draw/DrawWorkflow';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';
import { GlassBar } from '../components/GlassBar';
import { DrawExportFactory, ExportCardSpec, ExportNaming } from '../../features/export/ExportCard';
import { DrawSession } from '../../app/DrawSession';
import { ExportPreview } from './ExportPreview';

/**
 * 抽签工具：STEP1 配置 → STEP2 候选 → STEP3 结果。
 *
 * - 参数写回 `userdata.draw`（脏检测 + 防抖推送，跨端一致）；
 * - 候选来源支持「号码范围 / 班级名单」（名单来源显示姓名，不显示学号）；
 * - 结果支持剔除补抽、重抽、切换排序（排序写回 config.sort）。
 */
@Component
export struct DrawScreen {
  onClose: () => void = () => {
  };

  @State private step: DrawStep = DrawStep.CONFIG;
  private scroller: Scroller = new Scroller();
  @State private start: number = 1;
  @State private end: number = 70;
  @State private count: number = 10;
  @State private dup: boolean = false;
  @State private excl: string = '';
  @State private sort: DrawSortMode = DrawSortMode.DRAW_ORDER;
  @State private source: DrawPoolSource = DrawPoolSource.RANGE;
  @State private candidates: DrawEntry[] = [];
  @State private result: DrawResult | undefined = undefined;
  private round?: DrawProofRound;
  private proofRevision: number = 0;
  private pendingProof: Promise<DrawReceipt | undefined> | undefined = undefined;
  @State private receipt: DrawReceipt | undefined = undefined;
  @State private proofStatus: string = '';
  @State private errorMsg: string = '';
  @State private seatNames: string[] = [];
  @State private seats: number[] = [];
  @State private selectedSeats: number[] = [];
  @State private leagueSeats: number[] = [];
  @State private membersList: ClassMember[] = [];
  @State private editingRoster: boolean = false;
  @State private showExport: boolean = false;
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

  aboutToAppear(): void {
    this.restoreConfig();
    this.loadRoster();
  }

  private restoreConfig(): void {
    const sections: Blob = Services.userdata.currentSections();
    const config: DrawConfig = DrawConfigCodec.fromJson(JsonBlob.get(sections, 'draw'));
    this.start = config.start;
    this.end = config.end;
    this.count = config.count;
    this.dup = config.allowDuplicates;
    this.excl = config.excludedText;
    this.sort = config.sort;
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
    this.selectedSeats = seats.slice();
    this.membersList = loaded.members;
    this.seatNames = names;
    const league = await Services.league.load(false);
    this.leagueSeats = league.members.map((m: LeagueMember) => m.seat);
  }

  private currentConfig(): DrawConfig {
    const config: DrawConfig = new DrawConfig();
    config.start = this.start;
    config.end = this.end;
    config.count = this.count;
    config.allowDuplicates = this.dup;
    config.excludedText = this.excl;
    config.sort = this.sort;
    config.poolSource = this.source;
    return config;
  }

  private nameOf(number: number): string {
    if (this.source !== DrawPoolSource.ROSTER) {
      return '';
    }
    const index: number = this.seats.indexOf(number);
    return index >= 0 && index < this.seatNames.length ? this.seatNames[index] : '';
  }

  /** 参数写回云端 `userdata.draw`（保留未知字段）。 */
  private async persistConfig(): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const existing: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'draw'));
    next['draw'] = DrawConfigCodec.toJson(this.currentConfig(), existing);
    await Services.userdata.updateCurrent(next);
  }

  private toPreview(): void {
    this.persistConfig();
    let state: DrawWorkflowState = new DrawWorkflowState();
    state.config = this.currentConfig();
    const transition: DrawTransition = DrawWorkflow.toPreview(state, this.selectedSeats, (n: number) => this.nameOf(n));
    if (!transition.ok || transition.state === undefined) {
      this.errorMsg = transition.error !== undefined ? transition.error.message : '无法生成候选';
      return;
    }
    this.errorMsg = '';
    this.candidates = transition.state.candidates;
    this.step = DrawStep.PREVIEW;
  }

  private swipeNext(): void {
    if (this.step === DrawStep.CONFIG) {
      this.toPreview();
    }
  }

  private startDraw(): void {
    let state: DrawWorkflowState = new DrawWorkflowState();
    state.step = DrawStep.PREVIEW;
    state.config = this.currentConfig();
    state.candidates = this.candidates;
    const round = new DrawProofRound(Services.currentSid);
    const transition: DrawTransition = DrawWorkflow.startDraw(state, round.random());
    if (!transition.ok || transition.state === undefined || transition.state.result === undefined) {
      this.errorMsg = transition.error !== undefined ? transition.error.message : '抽签失败';
      return;
    }
    this.errorMsg = '';
    this.result = transition.state.result;
    this.round = round;
    round.start(this.result);
    this.publishProof();
    DrawSession.set(this.result);
    this.step = DrawStep.RESULT;
  }

  private async publishProof(): Promise<void> {
    const round = this.round;
    if (!round) return;
    const rev = ++this.proofRevision;
    this.receipt = undefined;
    this.proofStatus = '正在存证…';
    const pending = round.publish(Services.api, () => Services.currentSid);
    this.pendingProof = pending;
    const receipt = await pending;
    if (this.round !== round || this.proofRevision !== rev) return;
    this.pendingProof = undefined;
    this.receipt = receipt;
    this.proofStatus = receipt ? '已存证 · 今日第 ' + receipt.sequence + ' 次（全班共 ' + receipt.total + ' 次）'
      : '未存证 · 点按重试';
  }

  private back(): void {
    if (this.step === DrawStep.RESULT) {
      this.step = DrawStep.PREVIEW;
      this.result = undefined;
      return;
    }
    if (this.step === DrawStep.PREVIEW) {
      this.step = DrawStep.CONFIG;
      this.candidates = [];
      return;
    }
    this.onClose();
  }

  private changeSort(mode: DrawSortMode): void {
    this.sort = mode;
    this.persistConfig();
    if (this.step !== DrawStep.RESULT || this.result === undefined) {
      return;
    }
    let state: DrawWorkflowState = new DrawWorkflowState();
    state.step = DrawStep.RESULT;
    state.config = this.currentConfig();
    state.result = this.result;
    const transition: DrawTransition = DrawWorkflow.changeSort(state, mode, defaultDrawRandom());
    if (transition.ok && transition.state !== undefined) {
      this.result = transition.state.result;
      DrawSession.set(this.result);
    }
  }

  private reroll(): void {
    if (this.result === undefined) {
      return;
    }
    let state: DrawWorkflowState = new DrawWorkflowState();
    state.step = DrawStep.RESULT;
    state.config = this.currentConfig();
    state.result = this.result;
    const round = new DrawProofRound(Services.currentSid);
    const transition: DrawTransition = DrawWorkflow.reroll(state, round.random());
    if (!transition.ok || transition.state === undefined) {
      this.errorMsg = transition.error !== undefined ? transition.error.message : '重抽失败';
      return;
    }
    this.errorMsg = '';
    this.result = transition.state.result;
    this.round = round;
    round.start(this.result!);
    this.publishProof();
    DrawSession.set(this.result);
  }

  private removeAt(index: number): void {
    if (this.result === undefined) {
      return;
    }
    let state: DrawWorkflowState = new DrawWorkflowState();
    state.step = DrawStep.RESULT;
    state.config = this.currentConfig();
    state.result = this.result;
    const transition: DrawTransition = DrawWorkflow.removeAndRedraw(state, index, true, defaultDrawRandom());
    if (!transition.ok || transition.state === undefined) {
      this.errorMsg = transition.error !== undefined ? transition.error.message : '剔除失败';
      return;
    }
    this.errorMsg = '';
    this.result = transition.state.result;
    const log = this.result?.log;
    if (this.round && log && log.length > 0) {
      const last = log[log.length - 1];
      this.round.events.push(new ProofEvent('remove', last.removed.number, last.added?.number ?? null));
      this.publishProof();
    }
    DrawSession.set(this.result);
  }

  private async openExport(): Promise<void> {
    if (this.result === undefined) {
      return;
    }
    if (this.pendingProof) {
      const revision = this.proofRevision;
      let timer = -1;
      try {
        await Promise.race([this.pendingProof, new Promise<undefined>((resolve) => {
          timer = setTimeout(() => resolve(undefined), 6000);
        })]);
      } finally {
        if (timer >= 0) clearTimeout(timer);
      }
      if (revision !== this.proofRevision || this.step !== DrawStep.RESULT || !this.result) return;
    }
    this.exportSpec = DrawExportFactory.create(this.result, Date.now(), ExportNaming.randomSuffix(), this.receipt);
    this.showExport = true;
  }

  @Builder
  sortChip(mode: DrawSortMode) {
    Text(drawSortLabel(mode))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.sort === mode ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.sort === mode ? Tokens.MIST_TEAL : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.changeSort(mode);
      })
  }

  @Builder
  sourceChip(source: DrawPoolSource, label: string) {
    Text(label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.source === source ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.source === source ? Tokens.SLATE_BLUE : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        this.source = source;
        this.persistConfig();
      })
  }

  @Builder
  numberField(label: string, value: number, onChange: (value: number) => void) {
    Column() {
      Text(label)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_SECONDARY)
      TextInput({ text: '' + value })
        .type(InputType.Number)
        .height(44)
        .margin({ top: 4 })
        .backgroundColor(Tokens.CONTROL)
        .borderRadius(10)
        .fontSize(Tokens.F_BODY)
        .onChange((text: string) => {
          const parsed: number = Number(text);
          if (Number.isFinite(parsed) && parsed > 0) {
            onChange(Math.round(parsed));
          }
        })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  configStep() {
    Scroll(this.scroller) {
      Column() {
        Column() {
          Row({ space: 12 }) {
            this.numberField('起始', this.start, (value: number) => {
              this.start = Math.min(value, 999);
            })
            this.numberField('结束', this.end, (value: number) => {
              this.end = Math.min(value, 999);
            })
          }
          .width('100%')

          Row({ space: 12 }) {
            this.numberField('抽取个数', this.count, (value: number) => {
              this.count = Math.min(value, 999);
            })
            Column() {
              Text('允许重复')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
              Toggle({ type: ToggleType.Switch, isOn: this.dup })
                .margin({ top: 6 })
                .selectedColor(Tokens.MIST_TEAL)
                .onChange((isOn: boolean) => {
                  this.dup = isOn;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width(110)
          }
          .width('100%')
          .margin({ top: 14 })

          Text('排除号')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 14 })
          TextInput({ placeholder: '如 3,7,10-12', text: this.excl })
            .height(44)
            .margin({ top: 4 })
            .backgroundColor(Tokens.CONTROL)
            .borderRadius(10)
            .fontSize(Tokens.F_BODY)
            .onChange((text: string) => {
              this.excl = text;
            })

          Text('候选来源')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 16, bottom: 8 })
          Row() {
            this.sourceChip(DrawPoolSource.RANGE, '号码范围')
            this.sourceChip(DrawPoolSource.ROSTER, '班级名单' + (this.seats.length > 0 ? ' · ' + this.seats.length : ''))
          }

          if (this.source === DrawPoolSource.ROSTER) {
            Button((this.editingRoster ? '收起名单' : '编辑名单') + ' · 已选 ' + this.selectedSeats.length + ' 人')
              .fontSize(Tokens.F_LABEL).fontColor('#285E54').backgroundColor(Tokens.TINT_TEAL)
              .onClick(() => { this.editingRoster = !this.editingRoster; })
            if (this.editingRoster) {
              RosterPicker({ members: this.membersList, leagueSeats: this.leagueSeats, selected: this.selectedSeats,
                onSelect: (seats: number[]) => { this.selectedSeats = seats; } })
            }
          }

          Text('结果排序')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 16, bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.sortChip(DrawSortMode.DRAW_ORDER)
            this.sortChip(DrawSortMode.ASCENDING)
            this.sortChip(DrawSortMode.DESCENDING)
            this.sortChip(DrawSortMode.RANDOM)
          }
        }
        .width('100%')
        .padding(16)
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

        Button('预览候选')
          .width('100%')
          .height(48)
          .margin({ top: 20 })
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .fontSize(Tokens.F_BODY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.toPreview();
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
  previewStep() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          Text('候选 ' + this.candidates.length + ' 个')
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Medium)
            .fontColor(Tokens.TEXT_PRIMARY)
            .width('100%')

          Text('参数固化后开始抽签；候选与实际抽签池一致')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 4, bottom: 12 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.candidates, (entry: DrawEntry) => {
              Text(entry.label())
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_PRIMARY)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Tokens.CONTROL)
                .borderRadius(Tokens.RADIUS_PILL)
                .margin({ right: 6, bottom: 6 })
            }, (entry: DrawEntry) => '' + entry.number)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Tokens.CARD)
        .border({ width: 0.5, color: Tokens.CARD_EDGE })
        .borderRadius(Tokens.RADIUS_CARD)
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
        Button('返回')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CONTROL)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.back();
          })
        Button('开始抽签')
          .layoutWeight(2)
          .height(48)
          .backgroundColor(Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.startDraw();
          })
      }
    }
    .layoutWeight(1)
  }

  @Builder
  resultStep() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          Column() {
            Text('结果 ' + (this.result !== undefined ? this.result.entries.length : 0) + ' 个')
              .fontSize(Tokens.F_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')

            Text('范围 ' + this.start + '–' + this.end + ' · ' + this.count + ' 个 · '
              + (this.dup ? '可重复' : '不重复') + ' · ' + drawSortLabel(this.sort))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 4, bottom: 10 })

            Row() {
              Text(this.proofStatus).fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY).layoutWeight(1)
                .onClick(() => { if (this.proofStatus.indexOf('重试') >= 0) this.publishProof(); })
              if (this.receipt) {
                Button('分享核验链接').fontSize(Tokens.F_CAPTION).height(34)
                  .onClick(() => {
                    if (this.receipt) NativeShare.shareLink(this.receipt.url(), '抽签存证核验', this.proofStatus);
                  })
              }
            }.width('100%').margin({ bottom: 8 })
            ForEach(this.result !== undefined ? this.result.entries : [], (entry: DrawEntry, index: number) => {
              Row() {
                Text('' + (index + 1))
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .width(28)
                Text(entry.label())
                  .fontSize(Tokens.F_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Tokens.TEXT_PRIMARY)
                  .layoutWeight(1)
                Text('剔除')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.DANGER)
                  .padding({ left: 8, right: 4, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.removeAt(index);
                  })
              }
              .width('100%')
              .height(44)
            }, (entry: DrawEntry, index: number) => '' + index + '_' + entry.number)

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.DANGER)
                .width('100%')
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Tokens.CARD)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .borderRadius(Tokens.RADIUS_CARD)

          Text('排序')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 16, bottom: 8 })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.sortChip(DrawSortMode.DRAW_ORDER)
            this.sortChip(DrawSortMode.ASCENDING)
            this.sortChip(DrawSortMode.DESCENDING)
            this.sortChip(DrawSortMode.RANDOM)
          }
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
        Button('重新抽一次')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Tokens.CONTROL)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .fontColor(Tokens.TEXT_PRIMARY)
          .borderRadius(Tokens.RADIUS_PILL)
          .onClick(() => {
            this.reroll();
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
    }
    .layoutWeight(1)
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
      progress: this.headerFade,
        title: '抽签 · ' + (this.step === DrawStep.CONFIG ? '配置'
          : (this.step === DrawStep.PREVIEW ? '候选' : '结果')),
        actionText: this.step === DrawStep.RESULT ? '调整参数' : '',
        scroller: this.scroller,
        onBack: () => {
          this.back();
        },
        onAction: () => {
          if (this.round) {
            this.round.events.push(new ProofEvent('reset'));
            this.round.publish(Services.api, () => Services.currentSid);
            this.round = undefined;
          }
          this.step = DrawStep.CONFIG;
          this.candidates = [];
          this.result = undefined;
        }
      }) {
        Column() {
          if (this.step === DrawStep.CONFIG) {
            Column() {
              this.configStep()
            }
            .width('100%')
            .layoutWeight(1)
            .transition(TransitionEffect.asymmetric(Motion.pageEnter(), Motion.pageExit()))
          } else if (this.step === DrawStep.PREVIEW) {
            Column() {
              this.previewStep()
            }
            .width('100%')
            .layoutWeight(1)
            .transition(TransitionEffect.asymmetric(Motion.pageEnter(), Motion.pageExit()))
          } else {
            Column() {
              this.resultStep()
            }
            .width('100%')
            .layoutWeight(1)
            .transition(TransitionEffect.asymmetric(Motion.pageEnter(), Motion.pageExit()))
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
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 60) {
            this.back();
          } else if (event.offsetX < -60) {
            this.swipeNext();
          }
        })
    )
  }
}
