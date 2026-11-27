import { showFeedback } from '../components/AppFeedback';
import { LengthMetrics, window } from '@kit.ArkUI';
import { AppGlobal } from '../../app/AppGlobal';
import { DetailField, DetailSection, TaskAttachmentRow } from '../components/TaskDetailParts';
import { HomeworkAttachmentMeta } from '../../data/homework/HomeworkModels';
import { Services } from '../../app/Services';
import { MarkKind } from '../../data/marks/Marks';
import { HidePrefs } from '../../data/home/HidePrefs';
import { HomeworkDueCalculator, HomeworkItem, HomeworkRow } from '../../data/homework/HomeworkModels';
import { ReminderAgent } from '../../data/reminder/ReminderAgent';
import { ReminderPlan, ReminderPlanner } from '../../features/reminder/ReminderModels';
import { HomeworkReminders } from '../../data/reminder/HomeworkReminders';
import { ReminderStore } from '../../data/reminder/ReminderStore';
import { NotifyCenter } from '../../data/notify/NotifyCenter';
import { TaskAi } from '../../data/tasks/TaskAi';
import { TaskRepository } from '../../data/tasks/TaskRepository';
import { HomeworkBrief, PersonalTask, TaskCreateDraft, TaskDraftStep, TaskShare, TaskView, taskDay } from '../../data/tasks/TaskModels';
import { NativeShare } from '../../features/share/NativeShare';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';
import { Breakpoints } from '../theme/Breakpoints';
import { AppSymbols } from '../theme/AppSymbols';
import { GlassBar } from '../components/GlassBar';

Environment.envProp('colorMode', ColorMode.LIGHT);

@Styles function taskCardSurface() {
  .backgroundColor($r('app.color.task_glass_card'))
  .borderRadius(Tokens.RADIUS_CARD)
  .border({ width: 0.5, color: $r('app.color.task_glass_edge') })
}

@Styles function taskInputSurface() {
  .backgroundColor($r('app.color.task_glass_control'))
  .borderRadius(Tokens.RADIUS_INPUT)
  .border({ width: 0.5, color: $r('app.color.task_glass_edge') })
}

@Extend(TextInput) function taskInput() {
  .height(48)
  .fontSize(Tokens.F_BODY)
  .fontColor($r('app.color.task_text'))
  .placeholderColor($r('app.color.task_muted'))
}

@Extend(TextArea) function taskTextArea() {
  .fontSize(Tokens.F_BODY)
  .fontColor($r('app.color.task_text'))
  .placeholderColor($r('app.color.task_muted'))
}

@Extend(Button) function taskButton(primary: boolean, selected: boolean = false) {
  .type(ButtonType.Capsule)
  .constraintSize({ minHeight: 44 })
  .fontSize(Tokens.F_LABEL)
  .fontWeight(FontWeight.Medium)
  .fontColor(primary ? Color.White : $r('app.color.task_text'))
  .backgroundColor(primary ? $r('app.color.task_primary_button') :
    selected ? $r('app.color.task_control') : $r('app.color.task_glass_control'))
  .border({ width: primary ? 0 : 0.5, color: $r('app.color.task_glass_edge') })
  .padding({ left: Tokens.SPACE_12, right: Tokens.SPACE_12 })
}

@Component
export struct TaskScreen {
  @Prop taskId: string = '';
  @Prop taskShareUrl: string = '';
  onClose: () => void = () => {};
  onHomework: (id: string, fromTask?: string) => void = () => {};
  onNotice: (id: string, fromTask: string) => void = () => {};
  onAdvanced: () => void = () => {};
  onReminderSettings: () => void = () => {};
  @State private personal: PersonalTask[] = [];
  @StorageProp('colorMode') @Watch('updateSystemBars') private colorMode: ColorMode = ColorMode.LIGHT;
  @State private brief: HomeworkBrief = new HomeworkBrief();
  @State private selected: PersonalTask | undefined = undefined;
  @State private layoutWidth: number = 0;
  @State private listProgress: Map<string, number> = new Map<string, number>();
  @State private detailProgress: number = 0;
  private listScrollers: Map<string, Scroller> = new Map<string, Scroller>();
  private detailScroller: Scroller = new Scroller();
  private detailScrollId: string = '';
  @State private shared: TaskShare | undefined = undefined;
  @State private linkInput: boolean = false;
  @State private link: string = '';
  @State private title: string = '';
  @State private views: TaskView[] = TaskView.categories({});
  @State private activeView: string = 'all';
  @State private searching: boolean = false;
  @State private query: string = '';
  @State private quickDue: string = '';
  @State private quickStar: boolean = false;
  @State private editing: PersonalTask | undefined = undefined;
  @State private editTitle: string = '';
  @State private editNotes: string = '';
  @State private editDue: string = '';
  @State private editTime: string = '';
  @State private editStar: boolean = false;
  @State private editSteps: TaskDraftStep[] = [];
  @State private aiOpen: boolean = false;
  @State private aiText: string = '';
  @State private aiBusy: boolean = false;
  @State private aiError: string = '';
  @State private aiDrafts: TaskCreateDraft[] = [];
  @State private aiDraftIndex: number = -1;
  @State private aiSaving: boolean = false;
  @State private refreshing: boolean = false;
  @State private syncLabel: string = '';
  @State private hwStatus: string = '加载中';
  @State private reminderIds: string[] = [];
  @State private calendarFor: string = '';
  @State private imagePreview: string = '';
  private backLayer = (): boolean => {
    if (this.imagePreview) this.imagePreview = '';
    else if (this.editing || this.aiDraftIndex >= 0) this.closeEditor();
    else if (this.aiOpen) this.closeAi();
    else if (this.shared) this.shared = undefined;
    else if (this.selected) this.selectTask(undefined);
    else if (this.linkInput) this.linkInput = false;
    else if (this.searching) { this.searching = false; this.query = ''; }
    else return false;
    return true;
  };

  private rows: HomeworkRow[] = [];
  private excluded: Set<string> = new Set<string>();
  private active: boolean = false;
  private tick: number = -1;
  private initialId: string = '';
  private owner: string = '';
  private aiView: string = 'all';
  private aiRequest: number = 0;
  private nextStep: number = 0;
  private systemBarsBeforeTask?: window.SystemBarProperties;

  private wideLayout(): boolean {
    return Breakpoints.supportsToolPanes(this.layoutWidth);
  }

  private pageInset(): number {
    return this.wideLayout() ? Tokens.PAGE_PADDING : Breakpoints.pagePadding(this.layoutWidth);
  }

  private selectTask(task: PersonalTask | undefined): void {
    if (this.selected?.id !== task?.id) this.detailProgress = 0;
    this.selected = task;
  }

  private updateSystemBars(): void {
    if (!this.active) return;
    if (this.colorMode !== ColorMode.DARK) {
      this.restoreSystemBars();
      return;
    }
    try {
      const mainWindow = AppGlobal.context?.windowStage.getMainWindowSync();
      if (!mainWindow || this.systemBarsBeforeTask) return;
      this.systemBarsBeforeTask = mainWindow.getWindowSystemBarProperties();
      mainWindow.setWindowSystemBarProperties({ statusBarColor: '#1B2629', statusBarContentColor: '#EFF5F1',
        navigationBarContentColor: '#EFF5F1' }).catch(() => {});
    } catch (_) { /* 系统栏不可用时保留窗口原有设置。 */ }
  }

  private restoreSystemBars(): void {
    const previous = this.systemBarsBeforeTask;
    this.systemBarsBeforeTask = undefined;
    if (!previous) return;
    try {
      AppGlobal.context?.windowStage.getMainWindowSync().setWindowSystemBarProperties(previous).catch(() => {});
    } catch (_) { /* 窗口可能已销毁。 */ }
  }

  aboutToAppear(): void {
    AppGlobal.toolBack = this.backLayer;
    this.active = true;
    this.updateSystemBars();
    this.owner = Services.currentSid;
    this.initialId = this.taskId;
    if (this.taskShareUrl) this.preview(this.taskShareUrl);
    this.refresh(false);
    this.tick = setInterval(() => {
      this.updateBrief();
      if (!this.refreshing) this.refreshPersonal(true);
    }, 60000);
  }

  aboutToDisappear(): void {
    if (AppGlobal.toolBack === this.backLayer) AppGlobal.toolBack = undefined;
    this.active = false;
    this.restoreSystemBars();
    this.closeAi();
    clearInterval(this.tick);
  }

  private valid(): boolean { return this.active && this.owner === Services.currentSid; }

  private message(message: string): void {
    if (this.valid()) showFeedback(this.getUIContext(), message);
  }

  private updateBrief(): void {
    this.brief = HomeworkBrief.build(this.rows, this.excluded, this.personal, Date.now());
  }

  private async refreshPersonal(cloud: boolean): Promise<void> {
    const tasks = await TaskRepository.load(cloud);
    if (!this.valid()) return;
    this.personal = tasks;
    const views = TaskRepository.categories();
    if (views.length !== this.views.length || views.some((v: TaskView, i: number) =>
      this.views[i].key !== v.key || this.views[i].label !== v.label)) {
      this.activeView = views[TaskView.index(views, this.activeView)].key;
      this.views = views;
    }
    this.syncLabel = TaskRepository.status();
    this.updateBrief();
    if (this.initialId) {
      const found = tasks.find((t: PersonalTask) => t.id === this.initialId);
      if (found || cloud) {
        this.initialId = '';
        if (!found) this.message('未找到这项任务，请刷新或检查当前账号');
        this.selectTask(found);
      }
    } else if (this.selected) {
      const id = this.selected.id;
      this.selectTask(tasks.find((t: PersonalTask) => t.id === id));
    }
  }

  private async refreshWork(force: boolean): Promise<void> {
    const assignments = Services.homework.load(force);
    const marks = await Services.marks.refresh(force);
    const result = await assignments;
    if (!this.valid()) return;
    const hidden = HidePrefs.read(Services.userdata.currentSections()).hwHide;
    this.excluded = new Set<string>(Array.from(hidden));
    const marked = Services.marks.marks();
    for (const row of result.rows) {
      if (marked.isDone(MarkKind.HW, row.id)) this.excluded.add(row.id);
    }
    this.rows = result.rows;
    this.hwStatus = !result.ok ? result.message : result.message || marks.error ? '上次同步' : '';
    this.updateBrief();
    const record = await ReminderStore.load(this.owner);
    if (this.valid()) this.reminderIds = Array.from(record.ids.keys());
  }

  private async refresh(force: boolean): Promise<void> {
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      await this.refreshPersonal(false);
      await Promise.all([this.refreshPersonal(true), this.refreshWork(force)]);
    } finally {
      if (this.valid()) this.refreshing = false;
    }
  }

  private async afterEdit(): Promise<void> {
    await this.refreshPersonal(false);
    if (this.valid()) await this.refreshPersonal(true);
  }

  private async importRows(rows: HomeworkRow[]): Promise<void> {
    const count = await TaskRepository.importHomework(rows);
    if (!this.valid()) return;
    this.message(count ? '已加入 ' + count + ' 项个人任务' : '没有可加入的作业');
    await this.afterEdit();
  }

  private async remindHomework(item: HomeworkItem): Promise<void> {
    const prefs = await ReminderStore.load(this.owner);
    if (!this.valid()) return;
    const result = await HomeworkReminders.schedule(item.row, prefs.advance);
    if (!this.valid()) return;
    this.message(result.ok ? '已设置截止提醒' : result.message);
    this.calendarFor = result.code === 1700002 ? item.row.id : '';
    this.reminderIds = Array.from((await ReminderStore.load(this.owner)).ids.keys());
  }

  private async calendarForHomework(item: HomeworkItem): Promise<void> {
    const settings = await ReminderStore.load(this.owner);
    if (!this.valid()) return;
    const plan = ReminderPlanner.plan(item.row, Date.now(), settings.advance);
    if (!plan) { this.message('截止时间已过'); return; }
    this.message(await ReminderAgent.calendar(plan));
  }

  private async calendarForTask(task: PersonalTask): Promise<void> {
    const plan = new ReminderPlan();
    plan.taskId = task.id;
    plan.title = task.title;
    plan.content = task.notes;
    plan.triggerAt = task.snoozeUntil > Date.now() ? task.snoozeUntil : task.remindAt;
    const deadline = new Date(task.due + 'T' + (task.dueTime || '23:59') + ':00').getTime();
    plan.dueAt = Number.isFinite(deadline) && deadline >= plan.triggerAt ? deadline : plan.triggerAt;
    if (plan.triggerAt <= Date.now()) { this.message('请选择将来的提醒时间'); return; }
    this.message(await ReminderAgent.calendar(plan));
  }

  private async addQuickTask(): Promise<void> {
    if (!(await TaskRepository.add(this.title, undefined, this.quickDue, this.quickStar, this.activeView))) { this.message('请输入任务标题，最多可保存 2000 项'); return; }
    this.title = '';
    this.quickDue = '';
    this.quickStar = false;
    this.query = '';
    if (this.activeView === 'done') this.activeView = 'all';
    await this.afterEdit();
  }

  private quickDate(days: number): string {
    const date = new Date();
    date.setDate(date.getDate() + days);
    return taskDay(date);
  }

  private startEdit(task: PersonalTask): void {
    this.editTitle = task.title;
    this.editNotes = task.notes;
    this.editDue = task.due;
    this.editTime = task.dueTime;
    this.editStar = task.starred;
    this.editing = task;
  }

  private openAi(): void {
    this.aiView = this.activeView;
    this.aiOpen = true;
  }

  private closeAi(): void {
    this.aiRequest++;
    this.aiOpen = false;
    this.aiText = '';
    this.aiBusy = false;
    this.aiError = '';
    this.aiDrafts = [];
    this.aiDraftIndex = -1;
    this.editSteps = [];
  }

  private async suggestTasks(): Promise<void> {
    if (!this.valid() || this.aiBusy || !this.aiText.trim()) return;
    const request = ++this.aiRequest;
    const token = Services.currentToken;
    this.aiBusy = true;
    this.aiError = '';
    const result = await TaskAi.suggest(this.aiText, token);
    if (!this.valid() || !this.aiOpen || this.aiRequest !== request) return;
    this.aiBusy = false;
    if (Services.currentToken !== token) {
      this.aiError = '班级会话已更新，请重新整理';
      return;
    }
    if (result.error) {
      this.aiError = result.error;
      return;
    }
    result.drafts.forEach((draft: TaskCreateDraft) => { draft.starred = this.aiView === 'important'; });
    this.aiDrafts = result.drafts;
    if (this.aiDrafts.length === 1) this.editAiDraft(0);
  }

  private editAiDraft(index: number): void {
    const draft = this.aiDrafts[index];
    this.editTitle = draft.title;
    this.editNotes = draft.notes;
    this.editDue = draft.due;
    this.editTime = draft.dueTime;
    this.editStar = draft.starred;
    this.nextStep = 0;
    this.editSteps = draft.steps.map((step: TaskDraftStep) => new TaskDraftStep(step.text, step.note, this.nextStep++));
    this.aiDraftIndex = index;
  }

  private currentDraft(): TaskCreateDraft {
    const draft = new TaskCreateDraft();
    draft.title = this.editTitle;
    draft.notes = this.editNotes;
    draft.due = this.editDue.trim();
    draft.dueTime = this.editTime.trim();
    draft.starred = this.editStar;
    draft.steps = this.editSteps;
    return draft;
  }

  private closeEditor(): void {
    if (this.aiSaving) return;
    if (this.aiDraftIndex >= 0) {
      const draft = this.currentDraft();
      this.aiDrafts = this.aiDrafts.map((item: TaskCreateDraft, index: number) => index === this.aiDraftIndex ? draft : item);
      this.aiDraftIndex = -1;
      this.editSteps = [];
    } else {
      this.editing = undefined;
    }
  }

  private async saveAiDraft(): Promise<void> {
    if (!this.valid() || this.aiDraftIndex < 0 || this.aiSaving) return;
    const draft = this.currentDraft();
    if (!draft.title.trim()) { this.message('请输入任务标题'); return; }
    if (!PersonalTask.validDue(draft.due, draft.dueTime)) {
      this.message('请填写有效的截止日期和时间，全天任务可留空时间');
      return;
    }
    this.aiSaving = true;
    const saved = await TaskRepository.addDraft(draft, this.aiView);
    this.aiSaving = false;
    if (!this.valid()) return;
    if (!saved) { this.message('未能保存任务，请检查任务数量后重试'); return; }
    this.aiDrafts = this.aiDrafts.filter((_item: TaskCreateDraft, index: number) => index !== this.aiDraftIndex);
    this.aiDraftIndex = -1;
    this.editSteps = [];
    this.query = '';
    if (this.activeView === 'done' || (this.activeView === 'planned' && !draft.due) ||
      (this.activeView === 'important' && !draft.starred)) this.activeView = 'all';
    if (!this.aiDrafts.length) this.closeAi();
    this.message('已保存任务');
    await this.afterEdit();
  }

  private async saveEdit(): Promise<void> {
    const task = this.editing;
    if (!task) return;
    if (!this.editTitle.trim()) { this.message('请输入任务标题'); return; }
    if (!PersonalTask.validDue(this.editDue, this.editTime)) {
      this.message('请填写有效的截止日期和时间，全天任务可留空时间');
      return;
    }
    if (!(await TaskRepository.updateDetails(task, this.editTitle, this.editNotes, this.editDue,
      this.editTime, this.editStar))) { this.message('未能保存这项任务'); return; }
    this.editing = undefined;
    await this.afterEdit();
  }

  private async toggle(task: PersonalTask): Promise<void> {
    if (!(await TaskRepository.toggle(task.id, !task.done))) this.message('任务状态已变化，请刷新');
    await this.afterEdit();
  }

  private async remind(task: PersonalTask, stamp: number): Promise<void> {
    if (stamp > 0 && !(await NotifyCenter.currentSettings()).master) {
      this.message('请先在提醒设置中开启系统通知');
      this.onReminderSettings();
      return;
    }
    if (stamp > 0 && !(await NotifyCenter.ensurePermission())) { this.message('请在系统设置中允许通知'); return; }
    if (!this.valid()) return;
    const saved = await TaskRepository.remind(task.id, stamp);
    this.message(saved ? (stamp ? '已保存提醒时间' : '已清除提醒') : '未能保存提醒');
    await this.afterEdit();
  }

  private preview(link: string): void {
    const data = TaskShare.parse(link);
    if (!data) { this.message('请输入有效的枫丹工具箱任务链接'); return; }
    this.shared = data;
    this.linkInput = false;
    this.link = '';
  }

  private async acceptShare(): Promise<void> {
    const incoming = this.shared;
    if (!incoming) return;
    this.shared = undefined;
    if (!(await TaskRepository.add(incoming.title, incoming))) {
      this.shared = incoming;
      this.message('未能保存任务');
      return;
    }
    this.query = '';
    this.activeView = 'all';
    this.message('已保存为我的任务');
    await this.afterEdit();
  }

  @Builder
  action(label: string, run: () => void, selected: boolean = false) {
    Button(label).taskButton(false, selected).onClick(run)
  }

  @Builder
  homeworkCard() {
    Column({ space: Tokens.GAP_SM }) {
      Row({ space: Tokens.GAP_SM }) {
        SymbolGlyph(AppSymbols.HOMEWORK).fontSize(22).fontColor([$r('app.color.task_accent')])
        Text('班级作业').fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.task_text')).layoutWeight(1)
        this.action('全部作业', () => this.onHomework(''))
      }.width('100%')
      Text((this.hwStatus && !this.brief.pending.length) ? this.hwStatus : (this.brief.pending.length + ' 项可加入' +
        (this.brief.overdue ? ' · ' + this.brief.overdue + ' 项逾期' : '') +
        (this.brief.soon ? ' · ' + this.brief.soon + ' 项 24 小时内截止' : '') + (this.hwStatus ? ' · ' + this.hwStatus : '')))
        .fontSize(Tokens.F_LABEL).fontColor(this.brief.overdue ? $r('app.color.task_urgent') :
          this.brief.soon ? $r('app.color.task_soon') : $r('app.color.task_muted'))
      ForEach(this.brief.highlights, (item: HomeworkItem) => {
        Divider().color($r('app.color.task_line'))
        Column({ space: 5 }) {
          Text(item.row.content.trim().split('\n')[0] || item.row.subject || '班级作业').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.task_text')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text([item.row.subject, item.due ? HomeworkDueCalculator.dueText(item.due.atMillis) + ' · ' + item.due.label :
            item.row.due || '无截止日期'].filter((s: string) => !!s).join(' · ')).fontSize(13).fontColor($r('app.color.task_muted'))
        }.alignItems(HorizontalAlign.Start).width('100%').constraintSize({ minHeight: 44 })
          .justifyContent(FlexAlign.Center).onClick(() => this.onHomework(item.row.id))
        Row({ space: 8 }) {
          this.action('加入任务', () => { this.importRows([item.row]); })
          if (item.due && !item.due.expired) {
            this.action(this.reminderIds.includes(item.row.id) ? '调整提醒' : '提醒我', () => {
              if (this.reminderIds.includes(item.row.id)) this.onHomework(item.row.id);
              else this.remindHomework(item);
            })
          }
        }
        if (this.calendarFor === item.row.id) {
          this.action('添加到系统日历', () => { this.calendarForHomework(item); })
        }
      }, (item: HomeworkItem) => item.row.id + '_' + item.row.ts + '_' + (item.due?.label || '') + '_' + this.reminderIds.includes(item.row.id) + '_' + this.calendarFor)
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Tokens.GAP_SM), cross: LengthMetrics.vp(Tokens.GAP_SM) } }) {
        if (this.brief.pending.length > 1) {
          this.action('全部加入任务', () => { this.importRows(this.brief.pending.map((i: HomeworkItem) => i.row)); })
        }
        this.action('提醒设置', this.onReminderSettings)
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(Tokens.CARD_PADDING).taskCardSurface()
  }

  @Builder
  taskCard(task: PersonalTask) {
    Row({ space: Tokens.GAP_SM }) {
      Column({ space: Tokens.SPACE_4 }) {
        Text(task.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.task_text'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (task.notes && !task.title.includes(task.notes)) {
          Text(task.notes).fontSize(13).fontColor($r('app.color.task_muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (task.due || task.group || task.sourceHwId || task.sourceNoticeId || task.remindAt) {
          Text([task.sourceHwId ? '班级作业' : task.sourceNoticeId ? '班级通知' : task.group,
            task.dueLabel(), task.remindAt > Date.now() ? '已设提醒' : ''].filter((s: string) => !!s).join(' · '))
            .fontSize(Tokens.F_CAPTION).fontColor(task.statusLabel(Date.now()) === '已逾期' ?
              $r('app.color.task_urgent') : $r('app.color.task_muted'))
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).constraintSize({ minHeight: 44 })
        .justifyContent(FlexAlign.Center).onClick(() => { this.selectTask(task); })
      this.action(task.done ? '撤销完成' : '完成', () => { this.toggle(task); }, task.done)
    }.width('100%').padding(Tokens.CARD_PADDING).taskCardSurface()
      .border({ width: this.wideLayout() && this.selected?.id === task.id ? 1.5 : 0.5,
        color: this.wideLayout() && this.selected?.id === task.id ? $r('app.color.task_accent') : $r('app.color.task_glass_edge') })
  }

  private async shareTask(task: PersonalTask): Promise<void> {
    const result = await NativeShare.shareLink(TaskShare.link(task), task.title);
    if (!result.ok) this.message(result.message);
  }

  private scrollerForDetail(id: string): Scroller {
    if (this.detailScrollId !== id) {
      this.detailScrollId = id;
      this.detailScroller = new Scroller();
    }
    return this.detailScroller;
  }

  private scrollerForView(key: string): Scroller {
    const current = this.listScrollers.get(key);
    if (current) return current;
    const scroller = new Scroller();
    this.listScrollers.set(key, scroller);
    return scroller;
  }

  private scrollProgress(scroller: Scroller): number {
    return Math.min(1, Math.max(0, scroller.currentOffset().yOffset / 56));
  }

  private updateListProgress(key: string): void {
    const progress = this.scrollProgress(this.scrollerForView(key));
    const previous = this.listProgress.get(key) || 0;
    if (Math.abs(progress - previous) > 0.03 || (progress === 0 && previous > 0)) this.listProgress.set(key, progress);
  }

  @Builder
  selectedDetail() {
    if (this.selected) {
      ForEach([this.selected], (task: PersonalTask) => {
        this.detail(task)
      }, (task: PersonalTask) => JSON.stringify(task))
    }
  }

  @Builder
  detail(task: PersonalTask) {
    PageHeader({ taskColors: true, showAmbientBackground: true, progress: this.detailProgress,
      title: '任务详情', onBack: () => { this.selectTask(undefined); },
      actionText: '分享任务链接', onAction: () => { this.shareTask(task); },
      actionText2: '完整任务管理', onAction2: this.onAdvanced }) {
      Column() {
        Scroll(this.scrollerForDetail(task.id)) {
          Column({ space: Tokens.GAP }) {
            Column({ space: Tokens.GAP_SM }) {
              Text([task.statusLabel(Date.now()), task.starred ? '重要' : ''].filter((s: string) => !!s).join(' · '))
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor(task.statusLabel(Date.now()) === '已逾期' ?
                  $r('app.color.task_urgent') : $r('app.color.task_accent'))
              Text(task.title).fontSize(Tokens.F_TITLE).lineHeight(35).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.task_text')).copyOption(CopyOptions.InApp)
            }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 6 })
            DetailSection({ title: '任务安排', surface: $r('app.color.task_glass_card') }) {
              DetailField({ label: '截止时间', value: task.deadlineText() })
              DetailField({ label: '提醒时间', value: Math.max(task.remindAt, task.snoozeUntil) > 0 ?
                new Date(Math.max(task.remindAt, task.snoozeUntil)).toLocaleString() : '未设置' })
              if (task.repeatLabel) { DetailField({ label: '重复', value: task.repeatLabel }) }
              if (task.group) { DetailField({ label: '分组', value: task.group }) }
              if (task.myDay) { DetailField({ label: '我的一天', value: task.myDay }) }
              if (task.tags.length) { DetailField({ label: '标签', value: task.tags.join('、') }) }
              if (task.done && task.doneAt > 0) { DetailField({ label: '完成时间', value: new Date(task.doneAt).toLocaleString() }) }
              if (!task.done) {
                Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
                  this.action('30 分钟后提醒', () => { this.remind(task, Date.now() + 1800000); })
                  if (Math.max(task.remindAt, task.snoozeUntil) > 0) { this.action('取消提醒', () => { this.remind(task, 0); }) }
                  if (Math.max(task.remindAt, task.snoozeUntil) > Date.now()) {
                    this.action('添加到系统日历', () => { this.calendarForTask(task); })
                  }
                }
              }
            }
            if (task.notes.trim()) {
              DetailSection({ title: '备注', surface: $r('app.color.task_glass_card') }) {
                Text(task.notes).fontSize(16).lineHeight(25).fontColor($r('app.color.task_text')).copyOption(CopyOptions.InApp)
              }
            }
            if (task.steps.length) {
              DetailSection({ title: '步骤 · ' + task.stepsDone.filter((done: boolean) => done).length + '/' + task.steps.length,
                surface: $r('app.color.task_glass_card') }) {
                ForEach(task.steps, (step: string, i: number) => {
                  Row({ space: 10 }) {
                    Stack({ alignContent: Alignment.Center }) {
                      if (task.stepsDone[i]) {
                        SymbolGlyph(AppSymbols.CHECKMARK).fontSize(14).fontColor([Color.White])
                      }
                    }.width(22).height(22).borderRadius(Tokens.SPACE_6)
                      .backgroundColor(task.stepsDone[i] ? $r('app.color.task_primary_button') : Color.Transparent)
                      .border({ width: 1, color: task.stepsDone[i] ? $r('app.color.task_primary_button') : $r('app.color.task_muted') })
                    Column({ space: 3 }) {
                      Text(step).fontSize(16).lineHeight(24)
                        .fontColor(task.stepsDone[i] ? $r('app.color.task_muted') : $r('app.color.task_text'))
                      if (task.stepNotes[i]) {
                        Text(task.stepNotes[i]).fontSize(14).fontColor($r('app.color.task_muted'))
                      }
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  }.width('100%').constraintSize({ minHeight: 44 }).accessibilityText(
                    (task.stepsDone[i] ? '已完成，' : '未完成，') + step + (task.stepNotes[i] ? '，' + task.stepNotes[i] : ''))
                    .onClick(async () => { await TaskRepository.toggleStep(task.id, i); await this.afterEdit(); })
                }, (step: string, i: number) => i + step + task.stepNotes[i] + task.stepsDone[i])
              }
            }
            if (task.attachments.length) {
              DetailSection({ title: '附件 · ' + task.attachments.length, surface: $r('app.color.task_glass_card') }) {
                ForEach(task.attachments, (meta: HomeworkAttachmentMeta) => {
                  TaskAttachmentRow({ meta: meta, data: () => TaskRepository.attachmentData(task.id, meta.index),
                    onImage: (src: string) => { this.imagePreview = src; } })
                }, (meta: HomeworkAttachmentMeta) => meta.index + meta.name)
              }
            }
            if (task.sourceHwId || task.sourceNoticeId || task.sourceTitle) {
              DetailSection({ title: '任务来源', surface: $r('app.color.task_glass_card') }) {
                DetailField({ label: task.sourceHwId ? '班级作业' : task.sourceNoticeId ? '班级通知' : '来源',
                  value: task.sourceTitle || task.title })
                if (task.sourceHwId) { this.action('查看原作业', () => this.onHomework(task.sourceHwId, task.id)) }
                if (task.sourceNoticeId) { this.action('查看原通知', () => this.onNotice(task.sourceNoticeId, task.id)) }
              }
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(this.pageInset())
        }.width('100%').layoutWeight(1).align(Alignment.Top)
          .onDidScroll(() => {
            const progress = this.scrollProgress(this.detailScroller);
            if (Math.abs(progress - this.detailProgress) > 0.03 || progress === 0) this.detailProgress = progress;
          })
        GlassBar({ surface: $r('app.color.task_glass_bar'), edge: $r('app.color.task_glass_edge'), inset: this.pageInset() }) {
          Button('编辑任务').taskButton(false).layoutWeight(1)
            .onClick(() => { this.startEdit(task); })
          Button(task.done ? '撤销完成' : '标记完成').taskButton(!task.done).layoutWeight(1)
            .onClick(() => { this.toggle(task); })
        }
      }.width('100%').height('100%')
    }
  }

  @Builder
  quickEntry() {
    GlassBar({ surface: $r('app.color.task_glass_bar'), edge: $r('app.color.task_glass_edge'), inset: this.pageInset() }) {
      Column({ space: Tokens.GAP_SM }) {
        if (this.linkInput) {
          Row({ space: Tokens.SPACE_6 }) {
            TextInput({ placeholder: '粘贴任务分享链接', text: this.link }).taskInput().taskInputSurface().maxLength(8192).layoutWeight(1)
              .onChange((s: string) => { this.link = s; }).onSubmit(() => { this.preview(this.link); })
            Button('预览').taskButton(true).onClick(() => { this.preview(this.link); })
            this.action('取消', () => { this.linkInput = false; })
          }.width('100%')
        } else {
          Row({ space: Tokens.SPACE_6 }) {
            TextInput({ placeholder: '添加个人任务', text: this.title }).taskInput().taskInputSurface().maxLength(200).layoutWeight(1)
              .onChange((value: string) => { this.title = value; }).onSubmit(() => { this.addQuickTask(); })
            Button('添加').taskButton(true).onClick(() => { this.addQuickTask(); })
            this.action('AI 整理', () => { this.openAi(); })
          }.width('100%')
          if (this.title.trim().length) {
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Tokens.SPACE_6), cross: LengthMetrics.vp(Tokens.SPACE_4) } }) {
              this.action((this.quickDue === this.quickDate(0) ? '✓ ' : '') + '今天截止', () => {
                this.quickDue = this.quickDue === this.quickDate(0) ? '' : this.quickDate(0);
              }, this.quickDue === this.quickDate(0))
              this.action((this.quickDue === this.quickDate(1) ? '✓ ' : '') + '明天截止', () => {
                this.quickDue = this.quickDue === this.quickDate(1) ? '' : this.quickDate(1);
              }, this.quickDue === this.quickDate(1))
              this.action(this.quickStar ? '★ 重要' : '☆ 重要', () => { this.quickStar = !this.quickStar; }, this.quickStar)
            }
          }
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  aiIntake() {
    PageHeader({ taskColors: true, showAmbientBackground: true, title: 'AI 整理任务', onBack: () => { this.closeAi(); } }) {
      Scroll() {
        Column({ space: Tokens.GAP }) {
          Column({ space: Tokens.GAP }) {
            TextArea({ text: this.aiText, placeholder: '粘贴或输入要整理的任务文字' }).taskTextArea().taskInputSurface()
              .height(156).maxLength(TaskAi.MAX_TEXT).enabled(!this.aiBusy).width('100%')
              .onChange((value: string) => { this.aiText = value; this.aiError = ''; })
            Text('提交的文字和本地日期将发送给深度求索（DeepSeek）API，用于生成任务草稿。')
              .fontSize(Tokens.F_LABEL).fontColor($r('app.color.task_muted'))
            Button(this.aiBusy ? '正在整理…' : '发送给云端 AI').taskButton(true)
              .enabled(!this.aiBusy && !!this.aiText.trim()).onClick(() => { this.suggestTasks(); })
            if (this.aiError) {
              Text(this.aiError).fontSize(Tokens.F_BODY).fontColor($r('app.color.task_urgent'))
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(Tokens.CARD_PADDING).taskCardSurface()
          if (this.aiDrafts.length && !this.aiBusy) {
            Text('任务草稿').fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Bold).fontColor($r('app.color.task_text'))
            ForEach(this.aiDrafts, (draft: TaskCreateDraft, index: number) => {
              Row({ space: 10 }) {
                Text(draft.title.trim() || '未填写标题').fontSize(16).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.task_text')).layoutWeight(1)
                this.action('编辑草稿', () => { this.editAiDraft(index); })
              }.width('100%').padding(Tokens.CARD_PADDING).taskCardSurface()
            }, (draft: TaskCreateDraft, index: number) => index + ':' + draft.title)
          }
        }.alignItems(HorizontalAlign.Start).width('100%').constraintSize({ maxWidth: 720 }).padding(this.pageInset())
      }.width('100%').height('100%').align(Alignment.Top)
    }
  }

  @Builder
  taskEditor() {
    PageHeader({ taskColors: true, showAmbientBackground: true, title: this.aiDraftIndex >= 0 ? '新建任务' : '编辑任务',
      onBack: () => { this.closeEditor(); } }) {
      Column() {
        Scroll() {
          Column({ space: Tokens.GAP }) {
            Column({ space: Tokens.GAP_SM }) {
              Text('任务名称').fontSize(Tokens.F_LABEL).fontColor($r('app.color.task_muted'))
              TextInput({ text: this.editTitle, placeholder: '任务名称' }).taskInput().taskInputSurface().maxLength(200)
                .onChange((s: string) => { this.editTitle = s; })
              Text('备注').fontSize(Tokens.F_LABEL).fontColor($r('app.color.task_muted'))
              TextArea({ text: this.editNotes, placeholder: '添加备注' }).taskTextArea().taskInputSurface().height(100).maxLength(5000)
                .onChange((s: string) => { this.editNotes = s; })
              Text('截止日期与时间').fontSize(Tokens.F_LABEL).fontColor($r('app.color.task_muted'))
              Row({ space: Tokens.GAP_SM }) {
                TextInput({ text: this.editDue, placeholder: 'YYYY-MM-DD' }).taskInput().taskInputSurface().accessibilityText('截止日期')
                  .layoutWeight(3).maxLength(10).onChange((s: string) => { this.editDue = s; if (!s) this.editTime = ''; })
                TextInput({ text: this.editTime, placeholder: 'HH:MM' }).taskInput().taskInputSurface().accessibilityText('截止时间')
                  .layoutWeight(2).maxLength(5).onChange((s: string) => { this.editTime = s; })
              }
              this.action(this.editStar ? '★ 重要' : '☆ 标为重要', () => { this.editStar = !this.editStar; }, this.editStar)
            }.alignItems(HorizontalAlign.Start).width('100%').padding(Tokens.CARD_PADDING).taskCardSurface()

            if (this.aiDraftIndex >= 0) {
              DetailSection({ title: '步骤', surface: $r('app.color.task_glass_card') }) {
                ForEach(this.editSteps, (step: TaskDraftStep) => {
                  Column({ space: Tokens.SPACE_6 }) {
                    Row({ space: Tokens.SPACE_6 }) {
                      TextInput({ text: step.text, placeholder: '步骤名称' }).taskInput().taskInputSurface().maxLength(120).layoutWeight(1)
                        .onChange((value: string) => { step.text = value; })
                      this.action('删除步骤', () => {
                        this.editSteps = this.editSteps.filter((item: TaskDraftStep) => item.key !== step.key);
                      })
                    }.width('100%')
                    TextArea({ text: step.note, placeholder: '步骤备注' }).taskTextArea().taskInputSurface().height(76).maxLength(500)
                      .onChange((value: string) => { step.note = value; })
                  }.width('100%')
                }, (step: TaskDraftStep) => step.key.toString())
                if (this.editSteps.length < 50) {
                  this.action('添加步骤', () => { this.editSteps = this.editSteps.concat(new TaskDraftStep('', '', this.nextStep++)); })
                }
              }
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(this.pageInset())
        }.width('100%').layoutWeight(1).align(Alignment.Top)
        GlassBar({ surface: $r('app.color.task_glass_bar'), edge: $r('app.color.task_glass_edge'), inset: this.pageInset() }) {
          Button(this.aiSaving ? '正在保存…' : '保存任务').taskButton(true).layoutWeight(1).enabled(!this.aiSaving)
            .onClick(() => {
              if (this.aiDraftIndex >= 0) this.saveAiDraft();
              else this.saveEdit();
            })
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 })
    }
  }

  @Builder
  categoryPage(view: TaskView, tasks: PersonalTask[]) {
    Refresh({ refreshing: this.refreshing }) {
      List({ space: Tokens.GAP, scroller: this.scrollerForView(view.key) }) {
        if (!this.wideLayout() && view.key === 'all' && !this.searching) {
          ListItem() { this.homeworkCard() }
        }
        ListItem() {
          Row({ space: Tokens.GAP_SM }) {
            Column({ space: Tokens.TEXT_GAP }) {
              Text(view.label + ' · ' + tasks.length).fontSize(Tokens.F_HEADING).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.task_text'))
              if (this.syncLabel) {
                Text(this.syncLabel).fontSize(Tokens.F_CAPTION).fontColor($r('app.color.task_muted'))
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.wideLayout() || view.key !== 'all' || this.searching) {
              this.action('班级作业', () => this.onHomework(''))
            }
          }.width('100%').padding({ top: Tokens.SPACE_4 })
        }
        if (!tasks.length) {
          ListItem() {
            Column() {
              Text(this.query.trim() ? '没有符合搜索的任务' : '暂无' + view.label + '任务')
                .fontSize(Tokens.F_BODY).fontColor($r('app.color.task_muted')).textAlign(TextAlign.Center)
            }.width('100%').padding(Tokens.SPACE_24).taskCardSurface()
          }
        }
        ForEach(tasks, (task: PersonalTask) => { ListItem() { this.taskCard(task) } },
          (task: PersonalTask) => task.id + JSON.stringify(task))
      }.width('100%').height('100%').padding({ left: this.pageInset(), right: this.pageInset(),
        top: Tokens.SPACE_8, bottom: Tokens.GAP }).scrollBar(BarState.Auto)
        .onDidScroll(() => { this.updateListProgress(view.key); })
    }.onRefreshing(() => { this.refresh(true); })
  }

  @Builder
  taskList() {
    PageHeader({ taskColors: true, showAmbientBackground: true, progress: this.listProgress.get(this.activeView) || 0,
      title: '任务', actionText: '完整任务管理', onAction: this.onAdvanced,
      actionText2: '从链接添加任务', onAction2: () => { this.linkInput = true; },
      actionText3: this.searching ? '结束搜索' : '搜索任务', onAction3: () => {
        this.searching = !this.searching;
        if (!this.searching) this.query = '';
      }, onBack: this.onClose }) {
      Column() {
        if (this.searching) {
          Row() {
            Search({ placeholder: '搜索标题、备注、来源或标签', value: this.query })
              .taskInputSurface().fontColor($r('app.color.task_text')).placeholderColor($r('app.color.task_muted'))
              .width('100%').height(48).textFont({ size: Tokens.F_BODY }).onChange((s: string) => { this.query = s; })
          }.width('100%').padding({ left: this.pageInset(), right: this.pageInset() })
        }
        Tabs({ barPosition: BarPosition.Start, index: TaskView.index(this.views, this.activeView) }) {
          ForEach(this.views, (view: TaskView) => {
            TabContent() {
              this.categoryPage(view, TaskView.filter(this.personal, view.key, taskDay(new Date()), this.query))
            }.tabBar(SubTabBarStyle.of(view.label)
              .padding({ left: Tokens.SPACE_12, right: Tokens.SPACE_12, top: Tokens.SPACE_8, bottom: Tokens.SPACE_10 })
              .indicator({ color: $r('app.color.task_accent'), height: 3, borderRadius: 1.5 })
              .labelStyle({ font: { size: Tokens.F_BODY }, selectedColor: $r('app.color.task_accent'),
                unselectedColor: $r('app.color.task_muted') }))
          }, (view: TaskView) => view.key + ':' + view.label)
        }.width('100%').layoutWeight(1).barMode(BarMode.Scrollable).barHeight(52).scrollable(true).edgeEffect(EdgeEffect.None)
        .onChange((index: number) => {
          if (index >= 0 && index < this.views.length) this.activeView = this.views[index].key;
        })
        this.quickEntry()
      }.width('100%').height('100%')
    }
  }

  build() {
    Stack() {
      Row() {
        Column() { this.taskList() }.layoutWeight(1).height('100%')
        if (this.wideLayout()) {
          Divider().vertical(true).height('100%').color($r('app.color.task_glass_edge'))
          Column() {
            if (this.selected) {
              this.selectedDetail()
            } else {
              Scroll() {
                Column() { this.homeworkCard() }.width('100%').padding(this.pageInset())
              }.width('100%').height('100%').align(Alignment.Top)
            }
          }.layoutWeight(1.08).height('100%')
        }
      }.width('100%').height('100%')
        .visibility(this.imagePreview || this.shared || this.editing || this.aiOpen || (!this.wideLayout() && this.selected)
          ? Visibility.Hidden : Visibility.Visible)

      if (this.imagePreview) {
        PageHeader({ taskColors: true, showAmbientBackground: true, title: '图片附件', onBack: () => { this.imagePreview = ''; } }) {
          Image(this.imagePreview).objectFit(ImageFit.Contain).width('100%').height('100%')
        }
      } else if (this.shared) {
        PageHeader({ taskColors: true, showAmbientBackground: true, title: '分享的任务', onBack: () => { this.shared = undefined; } }) {
          Scroll() {
            Column() {
              Column({ space: Tokens.GAP }) {
                Text(this.shared.title).fontSize(Tokens.F_TITLE).fontWeight(FontWeight.Bold).fontColor($r('app.color.task_text'))
                if (this.shared.group || this.shared.due) {
                  Text([this.shared.group, this.shared.due].filter((s: string) => !!s).join(' · '))
                    .fontSize(Tokens.F_LABEL).fontColor($r('app.color.task_muted'))
                }
                if (this.shared.notes) { Text(this.shared.notes).fontColor($r('app.color.task_text')) }
                ForEach(this.shared.steps, (step: string) => { Text('• ' + step).fontColor($r('app.color.task_text')) },
                  (step: string, index: number) => index + step)
                Button('保存为我的任务').taskButton(true).onClick(() => { this.acceptShare(); })
              }.alignItems(HorizontalAlign.Start).width('100%').padding(Tokens.SPACE_16).taskCardSurface()
            }.width('100%').constraintSize({ maxWidth: 720 }).padding(this.pageInset())
          }.width('100%').height('100%').align(Alignment.Top)
        }
      } else if (this.editing || this.aiDraftIndex >= 0) {
        this.taskEditor()
      } else if (this.aiOpen) {
        this.aiIntake()
      } else if (!this.wideLayout() && this.selected) {
        this.selectedDetail()
      }
    }.width('100%').height('100%')
      .backgroundColor($r('app.color.task_ambient_scrim'))
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (Math.abs(width - this.layoutWidth) > 1) this.layoutWidth = width;
      })
  }
}
