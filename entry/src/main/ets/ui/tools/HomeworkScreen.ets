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
import { ReminderAgent, ReminderPublishResult } from '../../data/reminder/ReminderAgent';
import { ReminderRecord, ReminderStore } from '../../data/reminder/ReminderStore';
import { ReminderPlanner } from '../../features/reminder/ReminderModels';
import { HidePrefs } from '../../data/home/HidePrefs';
import { Blob } from '../../data/sync/JsonBlob';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';

/**
 * 作业工具：列表 + 截止倒计时 + 详情（全文/附件）+ 完成勾选 + 截止提醒。
 *
 * - 数据：`GET homework`（10 分钟 TTL）；完成状态 marks kind='hw'（乐观更新 + 补发）；
 * - 提醒：`reminderAgentManager` 系统日历提醒（失败降级为立即通知），本机按 homeworkId 记录提醒 id；
 * - 附件：图片内联预览、URL 文件可打开，data URI 文件只展示元信息。
 */
@Component
export struct HomeworkScreen {
  onClose: () => void = () => {
  };

  @State private rows: HomeworkRow[] = [];
  @State private doneIds: string[] = [];
  @State private filter: HomeworkFilter = HomeworkFilter.UNFINISHED;
  @State private loading: boolean = true;
  @State private refreshing: boolean = false;
  @State private errorMsg: string = '';
  @State private notice: string = '';
  @State private now: number = Date.now();

  @State private detailOpen: boolean = false;
  @State private detail: HomeworkItem | undefined = undefined;
  @State private advance: number = 30;
  @State private reminderIds: Map<string, number> = new Map<string, number>();
  @State private previewOpen: boolean = false;
  @State private previewSrc: string = '';
  @State private hiddenCount: number = 0;

  aboutToAppear(): void {
    this.reload(false);
    this.loadReminders();
  }

  private async loadReminders(): Promise<void> {
    const record: ReminderRecord = await ReminderStore.load(Services.currentSid);
    this.advance = ReminderPlanner.normalizeAdvance(record.advance);
    this.reminderIds = record.ids;
  }

  private async persistReminders(): Promise<void> {
    const record: ReminderRecord = new ReminderRecord();
    record.advance = this.advance;
    record.ids = this.reminderIds;
    await ReminderStore.save(Services.currentSid, record);
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
    this.closeDetail();
    this.notice = '已隐藏（仅你不可见）';
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
    const plan = ReminderPlanner.plan(item.row, Date.now(), this.advance);
    if (plan === undefined) {
      this.notice = '该作业没有可用的截止时间';
      return;
    }
    const result: ReminderPublishResult = await ReminderAgent.publish(plan);
    if (result.ok) {
      this.reminderIds.set(item.row.id, result.reminderId);
      this.reminderIds = new Map<string, number>(this.reminderIds);
      await this.persistReminders();
      this.notice = '已设置提醒：截止前 ' + this.advance + ' 分钟';
    } else {
      this.notice = result.message.length > 0 ? result.message : '提醒设置失败';
    }
  }

  private async cancelReminder(item: HomeworkItem): Promise<void> {
    const value: number | undefined = this.reminderIds.get(item.row.id);
    if (value !== undefined) {
      await ReminderAgent.cancel(value);
      this.reminderIds.delete(item.row.id);
      this.reminderIds = new Map<string, number>(this.reminderIds);
      await this.persistReminders();
    }
    this.notice = '已取消提醒';
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

  private dueColor(tone: HomeworkDueTone): string {
    if (tone === HomeworkDueTone.OVERDUE) {
      return Tokens.DANGER;
    }
    if (tone === HomeworkDueTone.URGENT || tone === HomeworkDueTone.WARN) {
      return Tokens.WARM_SAND;
    }
    if (tone === HomeworkDueTone.SAFE) {
      return Tokens.MIST_TEAL;
    }
    return Tokens.TEXT_TERTIARY;
  }

  @Builder
  filterChip(filter: HomeworkFilter) {
    Row({ space: 6 }) {
      Text(filter)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.filter === filter ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      Text('' + this.countOf(filter))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.filter === filter ? '#E8F2EF' : Tokens.TEXT_TERTIARY)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .backgroundColor(this.filter === filter ? Tokens.MIST_TEAL : Tokens.CARD)
    .borderRadius(Tokens.RADIUS_PILL)
    .onClick(() => {
      this.filter = filter;
    })
  }

  @Builder
  advanceChip(value: number) {
    Text('提前 ' + (value >= 60 ? (value / 60) + ' 小时' : value + ' 分钟'))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.advance === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.advance === value ? Tokens.SLATE_BLUE : Tokens.BG)
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
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(Tokens.WARM_SAND)
              .borderRadius(6)
              .margin({ right: 6 })
          }
          Text(item.title())
            .fontSize(Tokens.F_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.done ? Tokens.TEXT_TERTIARY : Tokens.TEXT_PRIMARY)
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
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }

        Row({ space: 10 }) {
          if (item.due !== undefined) {
            Text('截止 ' + HomeworkDueCalculator.dueText(item.due.atMillis))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
          }
          if (item.attachments.length > 0) {
            Text('附件 ' + item.attachments.length)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
          }
          if (this.hasReminder(item.row.id)) {
            Text('已设提醒')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
          }
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(item.done ? '✓' : '')
        .fontSize(15)
        .fontColor('#FFFFFF')
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor(item.done ? Tokens.MIST_TEAL : Tokens.BG)
        .border({ width: 1, color: item.done ? Tokens.MIST_TEAL : Tokens.DIVIDER })
        .borderRadius(14)
        .margin({ left: 12 })
        .onClick(() => {
          this.toggle(item);
        })
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
          .backgroundColor(Tokens.CARD)
          .onClick(() => {
            this.openPreview(HomeworkAttachments.dataOf((this.detail as HomeworkItem).row.attachments, meta.index));
          })
      }
      Row() {
        Text(meta.name)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(2)
        Text(meta.sizeText())
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  detailPanel() {
    Column() {
      Row() {
        Text('作业详情')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
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
              .fontColor(Tokens.TEXT_PRIMARY)
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
                  .fontColor(Tokens.TEXT_TERTIARY)
              }
              Blank()
            }
            .width('100%')
            .margin({ top: 6 })

            Text(this.detail.row.content.length > 0 ? this.detail.row.content : '（无正文）')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 10 })

            if (this.detail.attachments.length > 0) {
              Text('附件')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Medium)
                .fontColor(Tokens.TEXT_PRIMARY)
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
              .backgroundColor(Tokens.BG)
              .borderRadius(Tokens.RADIUS_CARD)
            }

            Text('截止提醒')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Medium)
              .fontColor(Tokens.TEXT_PRIMARY)
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
                .layoutWeight(1)
                .height(42)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.setReminder(this.detail as HomeworkItem);
                })
              if (this.hasReminder(this.detail.row.id)) {
                Button('取消提醒')
                  .layoutWeight(1)
                  .height(42)
                  .backgroundColor(Tokens.BG)
                  .fontColor(Tokens.DANGER)
                  .borderRadius(Tokens.RADIUS_PILL)
                  .onClick(() => {
                    this.cancelReminder(this.detail as HomeworkItem);
                  })
              }
            }
            .width('100%')
            .margin({ top: 8 })

            if (this.notice.length > 0) {
              Text(this.notice)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .width('100%')
                .margin({ top: 8 })
            }

            Button(this.detail.done ? '标记为未完成' : '标记为已完成')
              .width('100%')
              .height(44)
              .margin({ top: 10 })
              .backgroundColor(this.detail.done ? Tokens.BG : Tokens.MIST_TEAL)
              .fontColor(this.detail.done ? Tokens.TEXT_SECONDARY : '#FFFFFF')
              .borderRadius(Tokens.RADIUS_PILL)
              .onClick(() => {
                this.toggle(this.detail as HomeworkItem);
              })
            Button('隐藏（仅自己不可见）')
              .width('100%')
              .height(40)
              .margin({ top: 8, bottom: 12 })
              .backgroundColor(Tokens.BG)
              .fontColor(Tokens.TEXT_TERTIARY)
              .borderRadius(Tokens.RADIUS_PILL)
              .onClick(() => {
                this.hideCurrent();
              })
          }
          .width('100%')
          .padding({ bottom: 8 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('80%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: '作业',
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
            Text('加载作业…').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.rows.length === 0 && this.errorMsg.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorMsg)
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
                .fontColor(Tokens.TEXT_TERTIARY)
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
              .fontColor(Tokens.DANGER)
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 8 })
          }

          if (this.visibleItems().length === 0) {
            Column() {
              Text('暂无作业')
                .fontSize(Tokens.F_LABEL)
                .fontColor(Tokens.TEXT_TERTIARY)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ space: 10 }) {
                ForEach(this.visibleItems(), (item: HomeworkItem) => {
                  ListItem() {
                    this.itemCard(item)
                  }
                }, (item: HomeworkItem) => item.row.id + '_' + (item.done ? '1' : '0'))
              }
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
              .scrollBar(BarState.Off)
              .transition(Motion.listItem())
            }
            .layoutWeight(1)
            .margin({ top: 10 })
            .onRefreshing(() => {
              this.reload(true).then(() => {
                this.refreshing = false;
              });
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Tokens.BG)

      if (this.detailOpen) {
        Column() {
          this.detailPanel()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
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
