import { RosterPicker } from '../components/RosterPicker';
import { Services } from '../../app/Services';
import { ClassMember, LeagueMember } from '../../data/member/ClassMember';
import { ClassMembersResult } from '../../data/member/ClassMembersRepository';
import {
  Poll,
  PollAudience,
  PollDetail,
  PollDetailResult,
  PollDraft,
  PollListResult,
  PollMode,
  PollOption,
  PollResultVisibility,
  PollSettings,
  PollSummary,
  PollVoter,
  VoteLimits,
  VoteResult,
  audienceLabel,
  audienceTag,
  visibilityLabel
} from '../../data/vote/VoteModels';
import { PollOptionRow, VoteLogic } from '../../data/vote/VoteLogic';
import { VoteRepository } from '../../data/vote/VoteRepository';
import { VoteImage } from '../../data/vote/VoteImage';
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { ShareSpecs } from '../../features/share/ShareSpecs';
import { ExportCardSpec } from '../../features/export/ExportCard';
import { ExportCardView } from '../components/ExportCardView';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Immersive } from '../theme/Immersive';
import { PageHeader } from '../components/PageHeader';

/**
 * 投票工具：列表（进行中/已结束）+ 详情投票（单选/多选、改票）+ 结果 + 发起 + 管理（结束/删除）。
 *
 * 契约 `web/vote/CONTRACT.md`：RPC 调用、匿名/实名、结果可见性、可见范围（全班/班委/团员）；
 * 响应不含学号；可见范围含全班/班委/团员/指定成员（座号多选）。
 */
@Component
export struct VoteScreen {
  onClose: () => void = () => {
  };

  @State private polls: PollSummary[] = [];
  @State private showClosed: boolean = false;
  @State private loading: boolean = true;
  @State private refreshing: boolean = false;
  private scroller: Scroller = new Scroller();
  @State private errorMsg: string = '';
  @State private now: number = Date.now();

  @State private detailOpen: boolean = false;
  @State private detailLoading: boolean = false;
  @State private detail: PollDetail = new PollDetail();
  @State private chosen: string[] = [];
  @State private detailError: string = '';
  @State private busy: boolean = false;

  @State private createOpen: boolean = false;
  @State private fTitle: string = '';
  @State private fDesc: string = '';
  @State private fOptions: string[] = ['', '', ''];
  @State private fImages: string[] = ['', '', ''];
  @State private fMulti: boolean = false;
  @State private fMax: number = 2;
  @State private fAnonymous: boolean = true;
  @State private fAllowChange: boolean = true;
  @State private fVisibility: string = PollResultVisibility.AFTER_VOTE;
  @State private fAudience: string = PollAudience.ALL;
  @State private fMinutes: number = 30;
  @State private fError: string = '';
  @State private editingId: string = '';
  @State private fSeats: number[] = [];
  @State private members: ClassMember[] = [];
  @State private leagueSeats: number[] = [];
  @State private extendOpen: boolean = false;
  @State private extendMinutes: number = 30;
  private shareSpec: ExportCardSpec = new ExportCardSpec();
  private timerId: number = -1;
  private tickCount: number = 0;

  aboutToAppear(): void {
    this.reload();
    this.loadMembers();
    this.timerId = setInterval(() => {
      this.tickCount += 1;
      this.now = Date.now();
      if (this.detailOpen && this.tickCount % 15 === 0) {
        this.silentRefreshDetail();
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private async loadMembers(): Promise<void> {
    const result: ClassMembersResult = await Services.members.load(false);
    this.members = result.members;
    const league = await Services.league.load(false);
    this.leagueSeats = league.members.map((m: LeagueMember) => m.seat);
  }

  private async silentRefreshDetail(): Promise<void> {
    if (this.detail.poll.id.length === 0 || this.busy) {
      return;
    }
    const result: PollDetailResult = await Services.vote.detail(this.detail.poll.id);
    if (result.ok) {
      this.detail = result.detail;
    }
  }

  private async reload(): Promise<void> {
    this.loading = this.polls.length === 0;
    this.errorMsg = '';
    const result: PollListResult = await Services.vote.list();
    this.now = Date.now();
    if (!result.ok) {
      this.errorMsg = result.message;
    }
    this.polls = result.list.polls;
    this.loading = false;
  }

  private visiblePolls(): PollSummary[] {
    return VoteLogic.filterForTab(this.polls, this.showClosed, this.now);
  }

  private async pullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.reload();
    this.refreshing = false;
  }

  private closeDetail(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.detailOpen = false;
    });
  }

  private closeCreate(): void {
    this.editingId = '';
    this.fSeats = [];
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.createOpen = false;
    });
  }

  private openDetail(pollId: string): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.detailOpen = true;
    });
    this.detailLoading = true;
    this.detailError = '';
    this.chosen = [];
    this.loadDetail(pollId);
  }

  private async loadDetail(pollId: string): Promise<void> {
    const result: PollDetailResult = await Services.vote.detail(pollId);
    this.detailLoading = false;
    if (!result.ok) {
      this.detailError = result.message;
      return;
    }
    this.detail = result.detail;
    this.now = Date.now();
    if (result.detail.hasVoted) {
      this.chosen = result.detail.myChoices.slice(0);
    } else {
      this.chosen = [];
    }
  }

  private detailClosed(): boolean {
    return VoteLogic.effectiveClosed(this.detail.poll, this.now);
  }

  /** 发起人管理动作收进次级菜单，避免详情页堆叠一排危险按钮。 */
  private manageMenuItems(): MenuElement[] {
    const items: MenuElement[] = [];
    if (!this.detailClosed()) {
      items.push({
        value: '延长投票',
        action: () => {
          this.openExtend();
        }
      });
    }
    if (this.detail.total === 0) {
      items.push({
        value: '编辑选项',
        action: () => {
          this.openEdit();
        }
      });
    }
    if (!this.detailClosed()) {
      items.push({
        value: '结束投票',
        action: () => {
          this.manage('close', 0, undefined);
        }
      });
    }
    items.push({
      value: '删除投票',
      action: () => {
        this.manage('delete', 0, undefined);
      }
    });
    return items;
  }

  private resultsVisible(): boolean {
    return VoteLogic.resultsVisible(this.detail.poll.settings, this.detailClosed(), this.detail.hasVoted)
      && !this.detail.resultsHidden;
  }

  private canSubmit(): boolean {
    if (this.detail.poll.id.length === 0) {
      return false;
    }
    if (this.detailClosed()) {
      return false;
    }
    if (this.detail.hasVoted && !this.detail.poll.settings.allowChange) {
      return false;
    }
    return true;
  }

  private toggleChoice(optionId: string): void {
    if (!this.canSubmit()) {
      return;
    }
    const settings: PollSettings = this.detail.poll.settings;
    if (!settings.multi) {
      this.chosen = [optionId];
      return;
    }
    if (this.chosen.indexOf(optionId) >= 0) {
      const next: string[] = [];
      for (let i = 0; i < this.chosen.length; i++) {
        if (this.chosen[i] !== optionId) {
          next.push(this.chosen[i]);
        }
      }
      this.chosen = next;
      return;
    }
    if (this.chosen.length >= settings.maxChoices) {
      this.detailError = '最多选 ' + settings.maxChoices + ' 项';
      return;
    }
    const next: string[] = this.chosen.slice(0);
    next.push(optionId);
    this.chosen = next;
    this.detailError = '';
  }

  private async submitVote(): Promise<void> {
    if (this.busy) {
      return;
    }
    const optionIds: string[] = [];
    for (let i = 0; i < this.detail.poll.options.length; i++) {
      optionIds.push(this.detail.poll.options[i].id);
    }
    const reason: string = VoteLogic.validateChoices(this.detail.poll.settings, this.chosen, optionIds);
    if (reason.length > 0) {
      this.detailError = reason;
      return;
    }
    this.busy = true;
    this.detailError = '';
    const result: VoteResult = await Services.vote.submit(this.detail.poll.id, this.chosen);
    this.busy = false;
    if (!result.ok) {
      this.detailError = result.message;
      return;
    }
    await this.loadDetail(this.detail.poll.id);
    await this.reload();
  }

  private async manage(action: string, deadline: number, draft: PollDraft | undefined): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const result: VoteResult = await Services.vote.manage(this.detail.poll.id, action, deadline, draft);
    this.busy = false;
    if (!result.ok) {
      this.detailError = result.message;
      return;
    }
    if (action === 'delete') {
      this.closeDetail();
    } else {
      await this.loadDetail(this.detail.poll.id);
    }
    await this.reload();
  }

  private openCreate(): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.createOpen = true;
    });
    this.fTitle = '';
    this.fDesc = '';
    this.fOptions = ['', '', ''];
    this.fImages = ['', '', ''];
    this.fMulti = false;
    this.fMax = 2;
    this.fAnonymous = true;
    this.fAllowChange = true;
    this.fVisibility = PollResultVisibility.AFTER_VOTE;
    this.fAudience = PollAudience.ALL;
    this.fMinutes = 30;
    this.fError = '';
    this.editingId = '';
    this.fSeats = [];
    this.loadMembers();
  }

  private openEdit(): void {
    const poll: Poll = this.detail.poll;
    this.editingId = poll.id;
    this.fTitle = poll.title;
    this.fDesc = poll.description;
    const opts: string[] = [];
    for (let i = 0; i < poll.options.length; i++) {
      opts.push(poll.options[i].text);
    }
    this.fOptions = opts.length >= 2 ? opts : ['', ''];
    const imgs: string[] = [];
    for (let i = 0; i < this.fOptions.length; i++) {
      imgs.push(poll.options.length > i ? poll.options[i].img : '');
    }
    this.fImages = imgs;
    this.fMulti = poll.settings.multi;
    this.fMax = poll.settings.maxChoices;
    this.fAnonymous = poll.settings.anonymous;
    this.fAllowChange = poll.settings.allowChange;
    this.fVisibility = poll.settings.resultVisibility;
    this.fAudience = poll.audience;
    this.fSeats = poll.audienceSeats.slice(0);
    this.fMinutes = 0;
    this.fError = '';
    this.closeDetail();
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.createOpen = true;
    });
  }

  private openExtend(): void {
    this.extendMinutes = 30;
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.extendOpen = true;
    });
  }

  private async confirmExtend(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const deadline: number = Date.now() + this.extendMinutes * 60 * 1000;
    const result: VoteResult = await Services.vote.manage(this.detail.poll.id, 'extend', deadline, undefined);
    this.busy = false;
    if (!result.ok) {
      this.detailError = result.message;
      return;
    }
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.extendOpen = false;
    });
    await this.loadDetail(this.detail.poll.id);
    await this.reload();
  }

  private updateOption(index: number, text: string): void {
    const next: string[] = this.fOptions.slice(0);
    next[index] = text;
    this.fOptions = next;
    this.fError = '';
  }

  private addOption(): void {
    if (this.fOptions.length >= VoteLimits.MAX_OPTIONS) {
      this.fError = '最多 ' + VoteLimits.MAX_OPTIONS + ' 个选项';
      return;
    }
    const next: string[] = this.fOptions.slice(0);
    next.push('');
    this.fOptions = next;
  }

  private removeOption(): void {
    if (this.fOptions.length <= 2) {
      this.fError = '至少 2 个选项';
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.fOptions.length - 1; i++) {
      next.push(this.fOptions[i]);
    }
    this.fOptions = next;
  }

  private async createPoll(): Promise<void> {
    if (this.busy) {
      return;
    }
    const now: number = Date.now();
    const editing: boolean = this.editingId.length > 0;
    const draft: PollDraft = new PollDraft();
    draft.id = editing ? this.editingId : VoteLogic.newPollId(now);
    draft.title = this.fTitle;
    draft.description = this.fDesc;
    draft.mode = this.fMinutes > 0 ? PollMode.QUICK : (editing ? this.detail.poll.mode : PollMode.LONG);
    draft.options = VoteLogic.normalizeOptions(this.draftOptions(now), now);
    const settings: PollSettings = new PollSettings();
    settings.multi = this.fMulti;
    settings.maxChoices = this.fMulti ? this.fMax : 1;
    settings.anonymous = this.fAnonymous;
    settings.allowChange = this.fAllowChange;
    settings.resultVisibility = this.fVisibility;
    draft.settings = settings;
    if (this.fMinutes > 0) {
      draft.deadline = VoteLogic.quickDeadline(now, this.fMinutes);
    } else {
      draft.deadline = editing ? this.detail.poll.deadline : 0;
    }
    draft.audience = this.fAudience;
    if (this.fAudience === PollAudience.CUSTOM) {
      const seats: number[] = VoteLogic.normalizeSeats(this.fSeats);
      draft.audienceSeats = seats;
      const audienceError: string = VoteLogic.validateAudience(this.fAudience, seats);
      if (audienceError.length > 0) {
        this.fError = audienceError;
        return;
      }
    }
    const reason: string = VoteLogic.validateDraft(draft, now);
    if (reason.length > 0) {
      this.fError = reason;
      return;
    }
    this.busy = true;
    this.fError = '';
    let result: VoteResult;
    if (editing) {
      result = await Services.vote.manage(this.editingId, 'edit', 0, draft);
    } else {
      result = await Services.vote.create(draft);
    }
    this.busy = false;
    if (!result.ok) {
      this.fError = result.message;
      return;
    }
    this.createOpen = false;
    this.showClosed = false;
    this.editingId = '';
    await this.reload();
    if (this.detail.poll.id.length > 0) {
      await this.loadDetail(this.detail.poll.id);
    }
  }

  private draftOptions(now: number): PollOption[] {
    const out: PollOption[] = [];
    for (let i = 0; i < this.fOptions.length; i++) {
      const option: PollOption = new PollOption();
      option.id = VoteLogic.newOptionId(now, i);
      option.text = this.fOptions[i];
      option.img = this.fImages.length > i ? this.fImages[i] : '';
      out.push(option);
    }
    return out;
  }

  @Builder
  tag(text: string, tint: string) {
    Text(text)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(tint)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(Tokens.tint(tint, 0.12))
      .borderRadius(6)
      .margin({ right: 4 })
  }

  @Builder
  pollCard(poll: PollSummary) {
    Column() {
      Row() {
        Text(poll.title)
          .fontSize(Tokens.F_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(2)
        if (poll.hasVoted) {
          Text('已投')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.MIST_TEAL)
            .margin({ left: 6 })
        }
      }
      .width('100%')

      Row({ space: 6 }) {
        this.tag(poll.mode === PollMode.QUICK ? '限时' : '长时', Tokens.SLATE_BLUE)
        this.tag(poll.settings.multi ? '多选' : '单选', Tokens.TEXT_SECONDARY)
        this.tag(poll.settings.anonymous ? '匿名' : '实名', Tokens.TEXT_SECONDARY)
        if (poll.settings.allowChange) {
          this.tag('可改票', Tokens.TEXT_SECONDARY)
        }
        if (audienceTag(poll.audience, poll.audienceCount).length > 0) {
          this.tag(audienceTag(poll.audience, poll.audienceCount), Tokens.WARM_SAND)
        }
        Blank()
      }
      .width('100%')
      .margin({ top: 6 })

      Row() {
        Text(poll.ownerName.length > 0 ? poll.ownerName : '—')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
        Text(' · ' + VoteLogic.deadlineText(poll.deadline))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(VoteLogic.effectiveClosed(poll, this.now) ? Tokens.TEXT_TERTIARY : Tokens.WARM_SAND)
        Blank()
        Text(poll.total + ' 人已投')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .onClick(() => {
      this.openDetail(poll.id);
    })
  }

  @Builder
  optionRow(row: PollOptionRow) {
    Column() {
      Row() {
        if (this.chosen.indexOf(row.option.id) >= 0) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(['#FFFFFF'])
          }
          .width(20)
          .height(20)
          .backgroundColor(Tokens.MIST_TEAL)
          .borderRadius(10)
          .margin({ right: 8 })
        } else {
          Text('')
            .width(20)
            .height(20)
            .border({ width: 1, color: Tokens.DIVIDER })
            .borderRadius(10)
            .margin({ right: 8 })
        }
        Text(row.option.text)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
        if (this.resultsVisible()) {
          Text(row.count + ' 票 · ' + VoteLogic.formatPercent(row.percent))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
      }
      .width('100%')

      if (row.option.img.length > 0) {
        Image(row.option.img)
          .width('100%')
          .height(140)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .margin({ top: 8 })
      }

      if (this.resultsVisible()) {
        Row() {
          Row()
            .width(row.percent + '%')
            .height(4)
            .backgroundColor(Tokens.MIST_TEAL)
            .borderRadius(2)
        }
        .width('100%')
        .height(4)
        .backgroundColor(Tokens.BG)
        .borderRadius(2)
        .margin({ top: 6 })
        if (row.voterNames.length > 0) {
          Text(row.voterNames.join('、'))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 2 })
        }
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.toggleChoice(row.option.id);
    })
  }

  /** 单选型 chip：kind/value 交由 onSelect 处理（避免向 @Builder 传闭包）。 */
  @Builder
  selectChip(text: string, active: boolean, kind: string, value: string) {
    Text(text)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(active ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(active ? Tokens.SLATE_BLUE : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.onSelect(kind, value);
      })
  }

  private onSelect(kind: string, value: string): void {
    this.fError = '';
    if (kind === 'multi') {
      this.fMulti = value === '1';
    } else if (kind === 'anon') {
      this.fAnonymous = value === '1';
    } else if (kind === 'change') {
      this.fAllowChange = !this.fAllowChange;
    } else if (kind === 'visibility') {
      this.fVisibility = value;
    } else if (kind === 'audience') {
      this.fAudience = value;
    } else if (kind === 'extend') {
      this.extendMinutes = Number(value);
    } else if (kind === 'minutes') {
      this.fMinutes = Number(value);
    } else if (kind === 'tab') {
      this.showClosed = value === '1';
    } else if (kind === 'max') {
      this.fMax = this.fMax >= 5 ? 2 : this.fMax + 1;
    }
  }

  /** 投票详情 → 分享卡图片 → 系统图片分享。 */
  private shareDetail(): void {
    const poll: Poll = this.detail.poll;
    if (poll.id.length === 0) {
      return;
    }
    this.shareSpec = ShareSpecs.vote(this.detail, this.resultsVisible(), Date.now());
    const builder: CustomBuilder = (): void => {
      this.sharePoster();
    };
    NativeShare.shareCard(this.getUIContext(), builder, this.shareSpec.fileName,
      this.shareSpec.title, this.shareSpec.subtitle).then((result: ShareResult) => {
      if (!result.ok) {
        this.getUIContext().getPromptAction().showToast({ message: result.message });
      }
    });
  }

  @Builder
  sharePoster() {
    ExportCardView({ spec: this.shareSpec })
  }

  @Builder
  detailPanel() {
    Column() {
      Row() {
        Text('投票详情')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('分享')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.shareDetail();
          })
        Text('关闭')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.closeDetail();
          })
      }
      .width('100%')

      if (this.detailLoading) {
        Text('加载中…')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 10 })
      } else if (this.detail.poll.id.length === 0) {
        Text(this.detailError.length > 0 ? this.detailError : '投票不存在')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.DANGER)
          .margin({ top: 10 })
      } else {
        Scroll() {
          Column() {
            Text(this.detail.poll.title)
              .fontSize(Tokens.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
            Text(this.detail.poll.ownerName + ' · ' + VoteLogic.deadlineText(this.detail.poll.deadline)
              + (this.detail.poll.deadline > 0 && !this.detailClosed()
                ? ' · ' + VoteLogic.formatRemaining(VoteLogic.countdown(this.detail.poll.deadline, this.now)) : ''))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 4 })
            Row({ space: 6 }) {
              this.tag(this.detail.poll.settings.multi ? '多选' : '单选', Tokens.TEXT_SECONDARY)
              this.tag(this.detail.poll.settings.anonymous ? '匿名' : '实名', Tokens.TEXT_SECONDARY)
              this.tag(visibilityLabel(this.detail.poll.settings.resultVisibility), Tokens.WARM_SAND)
              if (audienceTag(this.detail.poll.audience, this.detail.poll.audienceCount).length > 0) {
                this.tag(audienceTag(this.detail.poll.audience, this.detail.poll.audienceCount), Tokens.SLATE_BLUE)
              }
              Blank()
            }
            .width('100%')
            .margin({ top: 6 })

            if (this.detail.poll.description.length > 0) {
              Text(this.detail.poll.description)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 8 })
            }

            Column() {
              ForEach(this.rows(), (row: PollOptionRow) => {
                this.optionRow(row)
              }, (row: PollOptionRow) => row.option.id + '_' + row.count + (this.chosen.indexOf(row.option.id) >= 0 ? '_y' : '_n'))
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .margin({ top: 10 })
            .backgroundColor(Tokens.CONTROL)
            .borderRadius(Tokens.RADIUS_CARD)

            Text(this.detail.total + ' 人已投' + (this.detail.hasVoted ? ' · 你已投票' : ''))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 8 })

            if (this.detailError.length > 0) {
              Text(this.detailError)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.DANGER)
                .width('100%')
                .margin({ top: 6 })
            }

            Button(this.canSubmit() ? (this.detail.hasVoted ? '修改投票' : '提交投票') : '投票已结束')
              .width('100%')
              .height(44)
              .margin({ top: 10 })
              .enabled(this.canSubmit() && !this.busy)
              .backgroundColor(this.canSubmit() ? Tokens.MIST_TEAL : Tokens.CONTROL)
              .fontColor(this.canSubmit() ? '#FFFFFF' : Tokens.TEXT_TERTIARY)
              .borderRadius(Tokens.RADIUS_PILL)
              .onClick(() => {
                this.submitVote();
              })

            if (this.detail.canManage) {
              Row({ space: 10 }) {
                Text('由发起人管理：延长、结束或删除投票')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .layoutWeight(1)
                Button('管理')
                  .height(36)
                  .padding({ left: 18, right: 18 })
                  .backgroundColor(Tokens.CONTROL)
                  .border({ width: 0.5, color: Tokens.CARD_EDGE })
                  .fontColor(Tokens.SLATE_BLUE)
                  .fontSize(Tokens.F_CAPTION)
                  .borderRadius(Tokens.RADIUS_PILL)
                  .bindMenu(this.manageMenuItems(), { systemMaterial: Immersive.dialogMaterial() })
              }
              .width('100%')
              .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding({ bottom: 12 })
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
    }
    .width('100%')
    .height('88%')
    .padding(16)
    .backgroundColor(Tokens.SHEET)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  private rows(): PollOptionRow[] {
    const options: PollOption[] = this.detail.poll.options;
    const rows: PollOptionRow[] = [];
    for (let i = 0; i < options.length; i++) {
      const row: PollOptionRow = new PollOptionRow();
      row.option = options[i];
      row.count = this.detail.counts.get(options[i].id) !== undefined
        ? this.detail.counts.get(options[i].id) as number : 0;
      row.percent = VoteLogic.percent(row.count, this.detail.total);
      const names: string[] = [];
      for (let v = 0; v < this.detail.voters.length; v++) {
        const voter: PollVoter = this.detail.voters[v];
        if (voter.choices.indexOf(options[i].id) >= 0) {
          names.push(voter.name);
        }
      }
      row.voterNames = names;
      rows.push(row);
    }
    return rows;
  }

  @Builder
  optionInput(index: number) {
    Row() {
      TextInput({ text: this.fOptions[index], placeholder: '选项 ' + (index + 1) })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(Tokens.CONTROL)
        .borderRadius(8)
        .fontSize(Tokens.F_CAPTION)
        .onChange((value: string) => {
          this.updateOption(index, value);
        })
      if (this.fImages.length > index && this.fImages[index].length > 0) {
        Image(this.fImages[index])
          .width(40)
          .height(40)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .margin({ left: 8 })
          .onClick(() => {
            const next: string[] = this.fImages.slice(0);
            next[index] = '';
            this.fImages = next;
          })
      } else {
        Text('配图')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .padding({ left: 8, right: 8, top: 10, bottom: 10 })
          .onClick(async () => {
            const url: string = await VoteImage.pick();
            if (url.length > 0) {
              const next: string[] = this.fImages.slice(0);
              next[index] = url;
              this.fImages = next;
            }
          })
      }
    }
    .width('100%')
    .margin({ top: 8 })
  }

  @Builder
  createPanel() {
    Column() {
      Row() {
        Text(this.editingId.length > 0 ? '编辑投票' : '发起投票')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('关闭')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.closeCreate();
          })
      }
      .width('100%')

      Scroll() {
        Column() {
          TextInput({ text: this.fTitle, placeholder: '投票标题（≤80 字）' })
            .height(44)
            .backgroundColor(Tokens.CONTROL)
            .borderRadius(8)
            .fontSize(Tokens.F_BODY)
            .margin({ top: 10 })
            .onChange((text: string) => {
              this.fTitle = text;
              this.fError = '';
            })

          TextInput({ text: this.fDesc, placeholder: '说明（可选，≤500 字）' })
            .height(40)
            .backgroundColor(Tokens.CONTROL)
            .borderRadius(8)
            .fontSize(Tokens.F_CAPTION)
            .margin({ top: 8 })
            .onChange((text: string) => {
              this.fDesc = text;
            })

          this.optionInput(0)
          this.optionInput(1)
          if (this.fOptions.length > 2) {
            this.optionInput(2)
          }
          if (this.fOptions.length > 3) {
            this.optionInput(3)
          }
          if (this.fOptions.length > 4) {
            this.optionInput(4)
          }
          if (this.fOptions.length > 5) {
            this.optionInput(5)
          }

          Row({ space: 10 }) {
            Button('加选项')
              .layoutWeight(1)
              .height(36)
              .backgroundColor(Tokens.CONTROL)
              .fontColor(Tokens.TEXT_SECONDARY)
              .borderRadius(8)
              .onClick(() => {
                this.addOption();
              })
            Button('减选项')
              .layoutWeight(1)
              .height(36)
              .backgroundColor(Tokens.CONTROL)
              .fontColor(Tokens.TEXT_SECONDARY)
              .borderRadius(8)
              .onClick(() => {
                this.removeOption();
              })
          }
          .width('100%')
          .margin({ top: 8 })

          Text('规则')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 12 })

          Row({ space: 6 }) {
            this.selectChip('单选', !this.fMulti, 'multi', '0')
            this.selectChip('多选', this.fMulti, 'multi', '1')
            if (this.fMulti) {
              Text('最多选')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ left: 6 })
              Text(this.fMax + ' 项')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  this.fMax = this.fMax >= 5 ? 2 : this.fMax + 1;
                })
            }
            Blank()
          }
          .width('100%')
          .margin({ top: 6 })

          Row({ space: 6 }) {
            this.selectChip('匿名', this.fAnonymous, 'anon', '1')
            this.selectChip('实名', !this.fAnonymous, 'anon', '0')
            this.selectChip(this.fAllowChange ? '可改票' : '不可改票', true, 'change', '1')
            Blank()
          }
          .width('100%')

          Text('结果可见性')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 10 })

          Row({ space: 6 }) {
            this.selectChip('始终', this.fVisibility === PollResultVisibility.ALWAYS, 'visibility', PollResultVisibility.ALWAYS)
            this.selectChip('投票后', this.fVisibility === PollResultVisibility.AFTER_VOTE, 'visibility', PollResultVisibility.AFTER_VOTE)
            this.selectChip('截止后', this.fVisibility === PollResultVisibility.AFTER_CLOSE, 'visibility', PollResultVisibility.AFTER_CLOSE)
            Blank()
          }
          .width('100%')

          Text('可见范围')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 10 })

          Row({ space: 6 }) {
            this.selectChip('全班', this.fAudience === PollAudience.ALL, 'audience', PollAudience.ALL)
            this.selectChip('班委', this.fAudience === PollAudience.COMMITTEE, 'audience', PollAudience.COMMITTEE)
            this.selectChip('团员', this.fAudience === PollAudience.LEAGUE, 'audience', PollAudience.LEAGUE)
            this.selectChip('指定成员', this.fAudience === PollAudience.CUSTOM, 'audience', PollAudience.CUSTOM)
            Blank()
          }
          .width('100%')

          if (this.fAudience === PollAudience.CUSTOM) {
            RosterPicker({ members: this.members, leagueSeats: this.leagueSeats, selected: this.fSeats,
              onSelect: (seats: number[]) => { this.fSeats = seats; this.fError = ''; } })
          }

          Text('时长')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 10 })

          Row({ space: 6 }) {
            this.selectChip('30 分钟', this.fMinutes === 30, 'minutes', '30')
            this.selectChip('2 小时', this.fMinutes === 120, 'minutes', '120')
            this.selectChip('1 天', this.fMinutes === 1440, 'minutes', '1440')
            this.selectChip('不限时', this.fMinutes === 0, 'minutes', '0')
            Blank()
          }
          .width('100%')

          if (this.fError.length > 0) {
            Text(this.fError)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.DANGER)
              .width('100%')
              .margin({ top: 8 })
          }

          Button(this.busy ? '提交中…' : '发起')
            .width('100%')
            .height(44)
            .margin({ top: 12 })
            .enabled(!this.busy)
            .backgroundColor(Tokens.MIST_TEAL)
            .fontColor('#FFFFFF')
            .borderRadius(Tokens.RADIUS_PILL)
            .onClick(() => {
              this.createPoll();
            })
        }
        .width('100%')
        .padding({ bottom: 12 })
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
    .width('100%')
    .height('92%')
    .padding(16)
    .backgroundColor(Tokens.SHEET)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
      progress: this.headerFade,
        title: '投票',
        actionText: '发起',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.openCreate();
        }
      }) {
        Column() {
        Row({ space: 8 }) {
          this.selectChip('进行中', !this.showClosed, 'tab', '0')
          this.selectChip('已结束', this.showClosed, 'tab', '1')
          Blank()
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.DANGER)
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 8 })
          }
          if (this.visiblePolls().length === 0) {
            Text(this.showClosed ? '暂无已结束投票' : '暂无进行中投票')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ scroller: this.scroller, space: 10 }) {
                ForEach(this.visiblePolls(), (poll: PollSummary) => {
                  ListItem() {
                    this.pollCard(poll)
                  }
                }, (poll: PollSummary) => poll.id + '_' + poll.total + '_' + (poll.hasVoted ? 'y' : 'n'))
              }
              .width('100%')
              .height('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
              .scrollBar(BarState.Off)
              .onDidScroll((offset: number) => {
                const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
                if (Math.abs(next - this.headerFade) > 0.03) {
                  this.headerFade = next;
                }
              })
            }
            .layoutWeight(1)
            .margin({ top: 10 })
            .onRefreshing(() => {
              this.pullRefresh();
            })
          }
        }
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0 })
      }

      if (this.detailOpen) {
        Column() {
          this.detailPanel()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Tokens.SCRIM)
        .justifyContent(FlexAlign.End)
        .padding({ left: 0, right: 0, bottom: 0 })
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }
      if (this.createOpen) {
        Column() {
          this.createPanel()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Tokens.SCRIM)
        .justifyContent(FlexAlign.End)
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }

      if (this.extendOpen) {
        Column() {
          Column() {
            Row() {
              Text('延长截止')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
              Blank()
              Text('关闭')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
                    this.extendOpen = false;
                  });
                })
            }
            .width('100%')
            Row({ space: 6 }) {
              this.selectChip('30 分钟', this.extendMinutes === 30, 'extend', '30')
              this.selectChip('2 小时', this.extendMinutes === 120, 'extend', '120')
              this.selectChip('1 天', this.extendMinutes === 1440, 'extend', '1440')
              Blank()
            }
            .width('100%')
            .margin({ top: 10 })
            Text('新截止：' + VoteLogic.formatAt(Date.now() + this.extendMinutes * 60 * 1000))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 4 })
            Button('确认延长')
              .width('100%')
              .height(42)
              .margin({ top: 10 })
              .backgroundColor(Tokens.MIST_TEAL)
              .fontColor('#FFFFFF')
              .borderRadius(Tokens.RADIUS_PILL)
              .onClick(() => {
                this.confirmExtend();
              })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Tokens.SHEET)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Tokens.SCRIM)
        .justifyContent(FlexAlign.End)
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }
    }
    .width('100%')
    .height('100%')
  }
}
