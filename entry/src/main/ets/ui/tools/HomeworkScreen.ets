import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { MarksRefreshResult, MarksUpdateResult } from '../../data/marks/MarksRepository';
import {
  HomeworkAttachments,
  HomeworkAttachmentMeta,
  HomeworkDue,
  HomeworkDueCalculator,
  HomeworkDueTone,
  HomeworkAttachmentKind,
  HomeworkFilter,
  HomeworkItem,
  HomeworkRow
} from '../../data/homework/HomeworkModels';
import { HomeworkResult } from '../../data/homework/HomeworkRepository';
import { ReminderAgent } from '../../data/reminder/ReminderAgent';
import { HomeworkReminders } from '../../data/reminder/HomeworkReminders';
import { TaskRepository } from '../../data/tasks/TaskRepository';
import { PersonalTask } from '../../data/tasks/TaskModels';
import { NotifyCenter } from '../../data/notify/NotifyCenter';
import { ReminderRecord, ReminderStore } from '../../data/reminder/ReminderStore';
import { ReminderPlanner } from '../../features/reminder/ReminderModels';
import { HidePrefs } from '../../data/home/HidePrefs';
import { Blob } from '../../data/sync/JsonBlob';
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { ShareSpecs } from '../../features/share/ShareSpecs';
import { ExportCardSpec } from '../../features/export/ExportCard';
import { ExportCardView } from '../components/ExportCardView';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Immersive } from '../theme/Immersive';
import { PageHeader } from '../components/PageHeader';

/**
 * 作业工具：列表 + 截止倒计时 + 详情（全文/附件）+ 完成勾选 + 截止提醒。
 *
 * - 数据：`GET homework`（10 分钟 TTL）；完成状态 marks kind='hw'（乐观更新 + 补发）；
 * - 提醒：`reminderAgentManager` 系统日历提醒（失败降级为立即通知），本机按 homeworkId 记录提醒 id。
 * - 附件：图片内联预览、URL 文件可打开，data URI 文件只展示元信息。
 */
@Component
export struct HomeworkScreen {
  @Prop homeworkId: string = '';
  private target: string = '';
  @State private imported: string[] = [];
  onClose: () => void = () => {
  };

  @State private rows: HomeworkRow[] = [];
  @State private doneIds: string[] = [];
  @State private filter: HomeworkFilter = HomeworkFilter.UNFINISHED;
  @State private loading: boolean = true;
  @State private refreshing: boolean = false;
  private scroller: Scroller = new Scroller();
  private refreshTimer: number = -1;
  private refreshRunning: boolean = false;
  private refreshSeq: number = 0;
  @State private errorMsg: string = '';
  @State private notice: string = '';
  @State private now: number = Date.now();

  @State private detailOpen: boolean = false;
  @State private detail: HomeworkItem | undefined = undefined;
  @State private advance: number = 30;
  @State private desiredIds: string[] = [];
  @State private calendarFor: string = '';
  @State private reminderIds: Map<string, number> = new Map<string, number>();
  @State private previewOpen: boolean = false;
  @State private previewSrc: string = '';
  @State private hiddenCount: number = 0;
  private shareSpec: ExportCardSpec = new ExportCardSpec();

  aboutToAppear(): void {
    this.target = this.homeworkId;
    this.reload(false);
    this.loadImported();
    this.loadReminders();
  }

  private async loadReminders(): Promise<void> {
    const record: ReminderRecord = await ReminderStore.load(Services.currentSid);
    this.advance = ReminderPlanner.normalizeAdvance(record.advance);
    this.reminderIds = record.ids;
    this.desiredIds = Array.from(record.leads.keys());
  }

  private async loadImported(): Promise<void> {
    this.imported = (await TaskRepository.load(false)).map((task: PersonalTask) => task.sourceHwId);
  }

  private async importTask(item: HomeworkItem): Promise<void> {
    const count = await TaskRepository.importHomework([item.row]);
    this.notice = count ? '已加入个人任务' : '未加入，请检查任务列表';
    await this.loadImported();
  }

  private async persistReminders(): Promise<void> {
    await HomeworkReminders.setAdvance(Services.currentSid, this.advance);
  }

  /** 每次 onRefreshing 都独立安排收起，避免上一次未结束时第二次下拉永远停住。 */
  private refreshNow(): void {
    const token: number = this.refreshSeq + 1;
    this.refreshSeq = token;
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      if (token === this.refreshSeq) {
        this.refreshing = false;
        this.refreshTimer = -1;
      }
    }, 1200);
    if (this.refreshRunning) {
      return;
    }
    this.refreshRunning = true;
    this.runRefresh(token);
  }

  private async runRefresh(token: number): Promise<void> {
    try {
      await this.reload(true);
    } catch (e) {
      this.errorMsg = '刷新失败，请稍后重试';
    } finally {
      this.refreshRunning = false;
      if (token === this.refreshSeq) {
        if (this.refreshTimer >= 0) {
          clearTimeout(this.refreshTimer);
          this.refreshTimer = -1;
        }
        this.refreshing = false;
      }
    }
  }

  private async reload(force: boolean): Promise<void> {
    this.loading = this.rows.length === 0;
    this.errorMsg = '';
    const result: HomeworkResult = await Services.homework.load(force);
    const marksResult: MarksRefreshResult = await Services.marks.refresh(false);
    this.now = Date.now();
    const rows: HomeworkRow[] = [];
    const hidden = HidePrefs.read(Services.userdata.currentSections());
    for (let i = 0; i < result.rows.length; i++) {
      const due: HomeworkDue | undefined = HomeworkDueCalculator.evaluate(result.rows[i], this.now);
      if (due !== undefined && due.prunable) {
        continue;
      }
      if (hidden.hwHide.has(result.rows[i].id)) {
        continue;
      }
      rows.push(result.rows[i]);
    }
    this.rows = rows;
    this.hiddenCount = hidden.hwHide.size;
    const done: string[] = [];
    const snapshot = Services.marks.marks();
    for (let i = 0; i < rows.length; i++) {
      if (snapshot.isDone(MarkKind.HW, rows[i].id)) {
        done.push(rows[i].id);
      }
    }
    this.doneIds = done;
    if (!result.ok) {
      this.errorMsg = result.message;
    } else if (marksResult.error !== undefined) {
      this.errorMsg = '完成状态同步失败：' + marksResult.error.displayMessage();
    }
    this.loading = false;
    if (this.target) {
      const id = this.target;
      this.target = '';
      const item = this.items().find((i: HomeworkItem) => i.row.id === id);
      if (item) this.openDetail(item);
      else this.getUIContext().getPromptAction().showToast({ message: '这项班级作业已不可见' });
    }
  }

  private items(): HomeworkItem[] {
    const list: HomeworkItem[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      const row: HomeworkRow = this.rows[i];
      const item: HomeworkItem = new HomeworkItem();
      item.row = row;
      item.done = this.doneIds.indexOf(row.id) >= 0;
      item.due = HomeworkDueCalculator.evaluate(row, this.now);
      item.attachments = HomeworkAttachments.parse(row.attachments);
      list.push(item);
    }
    list.sort((a: HomeworkItem, b: HomeworkItem) => {
      if (a.done !== b.done) {
        return a.done ? 1 : -1;
      }
      const aDue: number = a.due !== undefined ? a.due.atMillis : Number.MAX_SAFE_INTEGER;
      const bDue: number = b.due !== undefined ? b.due.atMillis : Number.MAX_SAFE_INTEGER;
      return aDue - bDue;
    });
    return list;
  }

  private visibleItems(): HomeworkItem[] {
    const all: HomeworkItem[] = this.items();
    if (this.filter === HomeworkFilter.ALL) {
      return all;
    }
    const out: HomeworkItem[] = [];
    for (let i = 0; i < all.length; i++) {
      if (this.filter === HomeworkFilter.DONE && all[i].done) {
        out.push(all[i]);
      } else if (this.filter === HomeworkFilter.UNFINISHED && !all[i].done) {
        out.push(all[i]);
      }
    }
    return out;
  }

  private countOf(filter: HomeworkFilter): number {
    const all: HomeworkItem[] = this.items();
    if (filter === HomeworkFilter.ALL) {
      return all.length;
    }
    let count: number = 0;
    for (let i = 0; i < all.length; i++) {
      const done: boolean = all[i].done;
      if ((filter === HomeworkFilter.DONE && done) || (filter === HomeworkFilter.UNFINISHED && !done)) {
        count += 1;
      }
    }
    return count;
  }

  private openDetail(item: HomeworkItem): void {
    this.detail = item;
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.detailOpen = true;
    });
  }

  private closeDetail(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.detailOpen = false;
    });
  }

  private async restoreHidden(): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const data = HidePrefs.read(current);
    if (data.hwHide.size === 0) {
      return;
    }
    data.hwHide.clear();
    await Services.userdata.updateCurrent(HidePrefs.write(current, data));
    const keys: Set<string> = new Set<string>();
    keys.add('hide');
    await Services.userdata.push(false, keys);
    this.hiddenCount = 0;
    this.notice = '已恢复隐藏的作业';
    await this.reload(true);
  }

  private async hideCurrent(): Promise<void> {
    if (this.detail === undefined) {
      return;
    }
    const id: string = this.detail.row.id;
    const current: Blob = Services.userdata.currentSections();
    const data = HidePrefs.read(current);
    data.hwHide.add(id);
    await Services.userdata.updateCurrent(HidePrefs.write(current, data));
    const keys: Set<string> = new Set<string>();
    keys.add('hide');
    await Services.userdata.push(false, keys);
    const cancelled = await HomeworkReminders.cancel(id);
    this.loadReminders();
    NotifyCenter.syncAll(true);
    TaskRepository.onChange();
    this.closeDetail();
    this.notice = cancelled ? '已隐藏（仅你不可见）' : '已隐藏，系统未能取消原提醒';
    await this.reload(true);
  }

  private async toggle(item: HomeworkItem): Promise<void> {
    const id: string = item.row.id;
    const next: boolean = !item.done;
    if (next) {
      if (this.doneIds.indexOf(id) < 0) {
        this.doneIds.push(id);
      }
    } else {
      const index: number = this.doneIds.indexOf(id);
      if (index >= 0) {
        this.doneIds.splice(index, 1);
      }
    }
    this.doneIds = this.doneIds.slice(0);
    this.notice = '';
    const result: MarksUpdateResult = await Services.marks.setMark(MarkKind.HW, id, next);
    if (!result.ok) {
      this.notice = '网络不佳：已在本机标记，稍后自动补发';
    }
    if (next && !(await HomeworkReminders.cancel(id))) this.notice = '已完成，系统未能取消原提醒';
    this.loadReminders();
    NotifyCenter.syncAll(true);
    TaskRepository.onChange();
    if (this.detail !== undefined && this.detail.row.id === id) {
      const refreshed: HomeworkItem = new HomeworkItem();
      refreshed.row = item.row;
      refreshed.done = next;
      refreshed.due = item.due;
      refreshed.attachments = item.attachments;
      this.detail = refreshed;
    }
  }

  private hasReminder(id: string): boolean {
    const value: number | undefined = this.reminderIds.get(id);
    return value !== undefined && value >= 0;
  }

  private async setReminder(item: HomeworkItem): Promise<void> {
    const result = await HomeworkReminders.schedule(item.row, this.advance);
    this.calendarFor = result.code === 1700002 ? item.row.id : '';
    this.notice = result.ok ? '已设置提醒：截止前 ' + this.advance + ' 分钟' : result.message;
    await this.loadReminders();
  }

  private async addCalendar(item: HomeworkItem): Promise<void> {
    const plan = ReminderPlanner.plan(item.row, Date.now(), this.advance);
    this.notice = plan ? await ReminderAgent.calendar(plan) : '截止时间已过';
  }

  private async cancelReminder(item: HomeworkItem): Promise<void> {
    const cancelled = await HomeworkReminders.cancel(item.row.id);
    this.notice = cancelled ? '已取消提醒' : '系统未能取消提醒，请重试';
    await this.loadReminders();
  }

  private openPreview(src: string): void {
    this.previewSrc = src;
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.previewOpen = true;
    });
  }

  private closePreview(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.previewOpen = false;
    });
  }

  private openUrl(url: string): void {
    const context = AppGlobal.context;
    if (context === undefined) {
      this.notice = '无法打开链接';
      return;
    }
    try {
      context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }).catch(() => {
        this.notice = '无法打开该链接';
      });
    } catch (e) {
      this.notice = '无法打开该链接';
    }
  }

  private dueColor(tone: HomeworkDueTone): ResourceColor {
    if (tone === HomeworkDueTone.OVERDUE) {
      return $r('app.color.task_urgent');
    }
    if (tone === HomeworkDueTone.URGENT || tone === HomeworkDueTone.WARN) {
      return $r('app.color.task_soon');
    }
    if (tone === HomeworkDueTone.SAFE) {
      return $r('app.color.task_accent');
    }
    return $r('app.color.task_muted');
  }

  @Builder
  filterChip(filter: HomeworkFilter) {
    Row({ space: 6 }) {
      Text(filter)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.filter === filter ? '#FFFFFF' : $r('app.color.task_muted'))
      Text('' + this.countOf(filter))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.filter === filter ? '#E8F2EF' : $r('app.color.task_muted'))
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.filter === filter ? Tokens.MIST_TEAL : $r('app.color.task_control'))
    .borderRadius(Tokens.RADIUS_PILL)
    .onClick(() => {
      this.filter = filter;
    })
  }

  @Builder
  advanceChip(value: number) {
    Text('提前 ' + (value >= 60 ? (value / 60) + ' 小时' : value + ' 分钟'))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.advance === value ? '#FFFFFF' : $r('app.color.task_muted'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.advance === value ? Tokens.SLATE_BLUE : $r('app.color.task_control'))
      .borderRadius(8)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.advance = value;
        this.persistReminders();
      })
  }

  @Builder
  itemCard(item: HomeworkItem) {
    Row() {
      Column() {
        Row() {
          if (ReminderPlanner.urgency(item.due !== undefined ? item.due.atMillis : undefined, this.now).length > 0) {
            Text(ReminderPlanner.urgency(item.due !== undefined ? item.due.atMillis : undefined, this.now))
              .fontSize(Tokens.F_CAPTION)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(Tokens.WARM_SAND)
              .borderRadius(6)
              .margin({ right: 6 })
          }
          Text(item.title())
            .fontSize(Tokens.F_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.done ? $r('app.color.task_muted') : $r('app.color.task_text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.due !== undefined) {
            Text(item.due.label)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(this.dueColor(item.due.tone))
              .margin({ left: 8 })
          }
        }
        .width('100%')

        if (item.bodyPreview().length > 0) {
          Text(item.bodyPreview())
            .fontSize(Tokens.F_CAPTION)
            .fontColor($r('app.color.task_muted'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }

        Row({ space: 10 }) {
          if (item.due !== undefined) {
            Text('截止 ' + HomeworkDueCalculator.dueText(item.due.atMillis))
              .fontSize(Tokens.F_CAPTION)
              .fontColor($r('app.color.task_muted'))
          }
          if (item.attachments.length > 0) {
            Text('附件 ' + item.attachments.length)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
          }
          if (this.hasReminder(item.row.id)) {
            Text('已设提醒')
              .fontSize(Tokens.F_CAPTION)
              .fontColor($r('app.color.task_accent'))
          }
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor([item.done ? '#FFFFFF' : Color.Transparent])
      }
      .width(28)
      .height(28)
      .backgroundColor(item.done ? Tokens.MIST_TEAL : $r('app.color.task_control'))
      .border({ width: 1, color: item.done ? Tokens.MIST_TEAL : $r('app.color.task_line') })
      .borderRadius(14)
      .margin({ left: 12 })
        .onClick(() => {
          this.toggle(item);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.task_card'))
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .stateStyles({
      pressed: {
        .scale({ x: 0.99, y: 0.99 })
      }
    })
    .animation({ duration: Motion.FAST, curve: Motion.ease() })
    .onClick(() => {
      this.openDetail(item);
    })
  }



  @Builder
  detailAttachment(meta: HomeworkAttachmentMeta) {
    Column() {
      if (this.detail !== undefined && meta.isImage()) {
        Image(HomeworkAttachments.dataOf(this.detail.row.attachments, meta.index))
          .width('100%')
          .height(150)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.task_card'))
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .onClick(() => {
            this.openPreview(HomeworkAttachments.dataOf((this.detail as HomeworkItem).row.attachments, meta.index));
          })
      }
      Row() {
        Text(meta.name)
          .fontSize(Tokens.F_CAPTION)
          .fontColor($r('app.color.task_text'))
          .layoutWeight(1)
          .maxLines(2)
        Text(meta.sizeText())
          .fontSize(Tokens.F_CAPTION)
          .fontColor($r('app.color.task_muted'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /** 作业详情 → 分享卡图片 → 系统图片分享。 */
  private shareDetail(): void {
    if (this.detail === undefined) {
      return;
    }
    const item: HomeworkItem = this.detail;
    this.shareSpec = ShareSpecs.homework(item, Date.now());
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
        Text('作业详情')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.task_text'))
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

      if (this.detail !== undefined) {
        Scroll() {
          Column() {
            Text(this.detail.title())
              .fontSize(Tokens.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.task_text'))
              .width('100%')
            Row({ space: 10 }) {
              if (this.detail.due !== undefined) {
                Text(this.detail.due.label + ' · 截止 ' + HomeworkDueCalculator.dueText(this.detail.due.atMillis))
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(this.dueColor(this.detail.due.tone))
              }
              if (this.detail.row.author.length > 0) {
                Text(this.detail.row.author)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor($r('app.color.task_muted'))
              }
              Blank()
            }
            .width('100%')
            .margin({ top: 6 })

            Text(this.detail.row.content.length > 0 ? this.detail.row.content : '（无正文）')
              .fontSize(Tokens.F_CAPTION)
              .fontColor($r('app.color.task_muted'))
              .width('100%')
              .margin({ top: 10 })

            if (this.detail.attachments.length > 0) {
              Text('附件')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.task_text'))
                .width('100%')
                .margin({ top: 14 })
              Column() {
                ForEach(this.detail.attachments, (meta: HomeworkAttachmentMeta) => {
                  this.detailAttachment(meta)
                }, (meta: HomeworkAttachmentMeta) => 'att_' + meta.index + '_' + meta.name)
              }
              .width('100%')
              .padding({ left: 14, right: 14 })
              .margin({ top: 6 })
              .backgroundColor($r('app.color.task_control'))
              .borderRadius(Tokens.RADIUS_CARD)
            }

            Button(this.imported.includes(this.detail.row.id) ? '已加入个人任务' : '加入个人任务')
              .enabled(!this.imported.includes(this.detail.row.id)).margin({ top: 12 })
              .onClick(() => { this.importTask(this.detail as HomeworkItem); })

            Text('截止提醒')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.task_text'))
              .width('100%')
              .margin({ top: 14 })
            Row() {
              ForEach(ReminderPlanner.ADVANCE_OPTIONS, (value: number) => {
                this.advanceChip(value)
              }, (value: number) => 'adv_' + value)
              Blank()
            }
            .width('100%')
            .margin({ top: 6 })

            Row({ space: 10 }) {
              Button(this.hasReminder(this.detail.row.id) ? '更新提醒' : '设置提醒')
                .enabled(!this.detail.done && this.detail.due !== undefined && !this.detail.due.expired)
                .layoutWeight(1)
                .height(42)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.setReminder(this.detail as HomeworkItem);
                })
              if (this.desiredIds.includes(this.detail.row.id)) {
                Button('取消提醒')
                  .layoutWeight(1)
                  .height(42)
                  .backgroundColor($r('app.color.task_control'))
                  .fontColor($r('app.color.task_urgent'))
                  .borderRadius(Tokens.RADIUS_PILL)
                  .onClick(() => {
                    this.cancelReminder(this.detail as HomeworkItem);
                  })
              }
            }
            .width('100%')
            .margin({ top: 8 })

            if (this.calendarFor === this.detail.row.id) {
              Button('添加到系统日历').margin({ top: 8 }).onClick(() => { this.addCalendar(this.detail as HomeworkItem); })
            }
            if (this.notice.length > 0) {
              Text(this.notice)
                .fontSize(Tokens.F_CAPTION)
                .fontColor($r('app.color.task_soon'))
                .width('100%')
                .margin({ top: 8 })
            }

            Row({ space: 10 }) {
              Button(this.detail.done ? '标记为未完成' : '标记为已完成')
                .layoutWeight(2)
                .height(44)
                .backgroundColor(this.detail.done ? $r('app.color.task_control') : Tokens.MIST_TEAL)
                .fontColor(this.detail.done ? $r('app.color.task_muted') : '#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.toggle(this.detail as HomeworkItem);
                })
              Button('更多')
                .layoutWeight(1)
                .height(44)
                .backgroundColor($r('app.color.task_control'))
                .border({ width: 0.5, color: Tokens.CARD_EDGE })
                .fontColor($r('app.color.task_muted'))
                .borderRadius(Tokens.RADIUS_PILL)
                .bindMenu([
                  {
                    value: '隐藏（仅自己不可见）',
                    action: () => {
                      this.hideCurrent();
                    }
                  }
                ], { systemMaterial: Immersive.dialogMaterial() })
            }
            .width('100%')
            .margin({ top: 10, bottom: 12 })
          }
          .width('100%')
          .padding({ bottom: 8 })
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
    .height('80%')
    .padding(16)
    .backgroundColor($r('app.color.task_card'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({ taskColors: true,
      progress: this.headerFade,
        title: '班级作业',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        }
      }) {
        Column() {
          if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
            Text('加载作业…').fontSize(Tokens.F_CAPTION).fontColor($r('app.color.task_muted'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.rows.length === 0 && this.errorMsg.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_BODY)
              .fontColor($r('app.color.task_muted'))
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
          Row({ space: 8 }) {
            this.filterChip(HomeworkFilter.ALL)
            this.filterChip(HomeworkFilter.UNFINISHED)
            this.filterChip(HomeworkFilter.DONE)
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })

          if (this.hiddenCount > 0) {
            Row() {
              Text('已隐藏 ' + this.hiddenCount + ' 条（仅自己不可见）')
                .fontSize(Tokens.F_CAPTION)
                .fontColor($r('app.color.task_muted'))
                .layoutWeight(1)
              Text('恢复')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
                .onClick(() => {
                  this.restoreHidden();
                })
            }
            .width('100%')
            .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 6 })
          }
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor($r('app.color.task_urgent'))
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 8 })
          }

          if (this.visibleItems().length === 0) {
            Column() {
              Text('暂无作业')
                .fontSize(Tokens.F_LABEL)
                .fontColor($r('app.color.task_muted'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ scroller: this.scroller, space: 10 }) {
                ForEach(this.visibleItems(), (item: HomeworkItem) => {
                  ListItem() {
                    this.itemCard(item)
                  }
                }, (item: HomeworkItem) => item.row.id + '_' + (item.done ? '1' : '0'))
              }
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
              .scrollBar(BarState.Off)
              .onDidScroll((offset: number) => {
                const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
                if (Math.abs(next - this.headerFade) > 0.03) {
                  this.headerFade = next;
                }
              })
              .transition(Motion.listItem())
            }
            .layoutWeight(1)
            .margin({ top: 10 })
            .onRefreshing(() => {
              this.refreshNow();
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
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }

      if (this.previewOpen) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#E6000000')
            .onClick(() => {
              this.closePreview();
            })
          Image(this.previewSrc)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
        .transition(Motion.scrim())
      }
    }
    .width('100%')
    .height('100%')
  }
}
