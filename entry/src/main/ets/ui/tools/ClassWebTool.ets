import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { Services } from '../../app/Services';
import { AppGlobal } from '../../app/AppGlobal';
import { Session } from '../../data/session/Session';
import { PageHeader } from '../components/PageHeader';
import { Tokens } from '../theme/Tokens';
import { TaskScreen } from './TaskScreen';
import { TaskRepository } from '../../data/tasks/TaskRepository';
import { HomeworkScreen } from './HomeworkScreen';
import { NoticeScreen } from './NoticeScreen';

const SITE = 'https://tool.furina.fun';

@Component
export struct ClassWebTool {
  @Prop toolId: string = 'hw';
  @Prop homeworkId: string = '';
  @Prop taskId: string = '';
  @Prop taskShareUrl: string = '';
  @Prop noticeId: string = '';
  onClose: () => void = () => {};
  onReminderSettings: () => void = () => {};
  @State private advanced: boolean = false;
  @State private currentHomework: string = '';
  @State private currentTask: string = '';
  @State private sourceNotice: string = '';
  @State private incomingShare: string = '';
  private watchTimer: number = -1;
  private observedTaskStamp: string = '';
  private polling: boolean = false;
  @State private nativeView: boolean = false;
  @State private scripts: ScriptItem[] = [];
  @State private error: string = '';
  @State private progress: number = 0;
  private controller = new webview.WebviewController();
  private downloads = new webview.WebDownloadDelegate();
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.currentHomework = this.homeworkId;
    this.currentTask = this.taskId;
    this.incomingShare = this.taskShareUrl;
    this.nativeView = !!this.homeworkId || !!this.noticeId;
    this.prepareSession();
  }

  aboutToDisappear(): void {
    if (AppGlobal.toolBack === this.handleEditorBack) AppGlobal.toolBack = undefined;
    this.active = false;
    clearInterval(this.watchTimer);
  }

  // The full editor syncs via the website. Keep native reminders and Forms current after a confirmed web write.
  private async pollEditor(): Promise<void> {
    if (this.polling || !this.active || !this.advanced) return;
    this.polling = true;
    try {
      const state: string = await this.controller.runJavaScript(
        '(()=>{if(location.origin!==' + JSON.stringify(SITE) + ' || !window.TASKSYNC)return "";' +
        'const s=window.TASKSYNC.state();if(!s.sid || s.status!=="已同步")return "";' +
        'const base=JSON.parse(localStorage.getItem("zq_task_cloud_"+s.sid)||"null");return String(base?.ts||0);})()');
      if (this.active && this.advanced && state && state !== '""' && state !== this.observedTaskStamp) {
        this.observedTaskStamp = state;
        await TaskRepository.load(true);
      }
    } catch (_) {} finally { this.polling = false; }
  }

  private handleEditorBack = (): boolean => {
    if (!this.advanced) return false;
    this.editorBack();
    return true;
  };

  private openEditor(): void {
    AppGlobal.toolBack = this.handleEditorBack;
    this.nativeView = false;
    this.advanced = true;
    this.error = '';
    this.progress = 0;
    this.observedTaskStamp = '';
    clearInterval(this.watchTimer);
    this.watchTimer = setInterval(() => { this.pollEditor(); }, 2500);
  }

  private editorBack(): void {
    if (this.toolId === 'nt') { this.onClose(); return; }
    clearInterval(this.watchTimer);
    this.advanced = false;
    this.incomingShare = '';
    this.currentTask = '';
  }

  private pageUrl(): string {
    return SITE + '/?mobileTool=' + (this.toolId === 'nt' ? 'nt' : 'hw');
  }

  private async prepareSession(): Promise<void> {
    const session: Session | undefined = await Services.sessionStore.load();
    if (!this.active) return;
    if (!session || !session.token || session.sid !== Services.currentSid) {
      this.error = '请重新验证班级身份后打开此工具';
      return;
    }
    const script: string = 'if(window===window.top && location.origin===' + JSON.stringify(SITE) +
      ' && location.pathname==="/" && location.search===' + JSON.stringify(this.pageUrl().substring(SITE.length + 1)) +
      '){let s=' + session.toJson() + ';s.is_admin=s.isAdmin;s.ts=Date.now();window.__ctMobileSession=s;}';
    this.scripts = [{ script: script, scriptRules: [SITE] }];
  }

  private async chooseFiles(event: OnShowFileSelectorEvent): Promise<void> {
    const context = AppGlobal.context;
    let uris: string[] = [];
    if (context) {
      try {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode ? 50 : 1;
        uris = await new picker.DocumentViewPicker(context).select(options);
      } catch (_) {}
    }
    event.result.handleFileList(uris);
  }

  private toast(message: string): void {
    if (this.active) this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private bindDownloads(): void {
    this.downloads.onBeforeDownload((item: webview.WebDownloadItem) => {
      const context = AppGlobal.context;
      if (!context) { item.cancel(); return; }
      item.start(context.cacheDir + '/tool-download-' + item.getGuid());
    });
    this.downloads.onDownloadFinish((item: webview.WebDownloadItem) => { this.saveFile(item); });
    this.downloads.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.toast('下载失败，请重新打开该文件');
    });
    this.controller.setDownloadDelegate(this.downloads);
  }

  private async saveFile(item: webview.WebDownloadItem): Promise<void> {
    const context = AppGlobal.context;
    const path: string = item.getFullPath();
    try {
      if (!this.active || !context) return;
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [(item.getSuggestedFileName() || '附件').replace(/[\\/]/g, '_')];
      const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) return;
      const dest = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await fs.copyFile(path, dest.fd);
      } finally { fs.closeSync(dest); }
      this.toast('文件已保存');
    } catch (_) { this.toast('保存失败，请重试'); }
    finally { if (path) { try { fs.unlinkSync(path); } catch (_) {} } }
  }

  private allowNavigation(event: OnLoadInterceptEvent): boolean {
    if (!event.data.isMainFrame()) return false;
    const url: string = event.data.getRequestUrl();
    if (url.split('#')[0] === this.pageUrl() || url === 'about:blank') return false;
    if (/^https?:\/\//i.test(url)) {
      AppGlobal.context?.startAbility({ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'],
        uri: url }).catch(() => { this.toast('无法打开链接'); });
    }
    return true;
  }

  private retry(): void {
    this.error = '';
    this.progress = 0;
    if (this.scripts.length === 0) this.prepareSession();
    else this.controller.loadUrl(this.pageUrl());
  }

  build() {
    if (this.sourceNotice) {
      NoticeScreen({ noticeId: this.sourceNotice, onClose: () => { this.sourceNotice = ''; } })
    } else if (this.nativeView) {
      if (this.toolId === 'nt') {
        NoticeScreen({ noticeId: this.noticeId, onClose: () => { if (this.noticeId) this.onClose(); else this.nativeView = false; } })
      } else {
        HomeworkScreen({ homeworkId: this.currentHomework, onClose: () => {
          this.nativeView = false; this.currentHomework = ''; this.incomingShare = '';
        } })
      }
    } else if (this.toolId === 'hw' && !this.advanced) {
      TaskScreen({ taskId: this.currentTask, taskShareUrl: this.incomingShare, onClose: this.onClose,
        onAdvanced: () => { this.openEditor(); }, onReminderSettings: this.onReminderSettings,
        onNotice: (id: string, fromTask: string) => { this.currentTask = fromTask; this.sourceNotice = id; },
        onHomework: (id: string, fromTask?: string) => { this.currentTask = fromTask || ''; this.currentHomework = id; this.nativeView = true; } })
    } else {
      PageHeader({
        title: this.toolId === 'nt' ? '通知' : '任务',
        actionText: this.toolId === 'nt' ? '本机通知' : '任务概览',
        onAction: () => { if (this.toolId === 'hw') this.editorBack(); else this.nativeView = true; this.error = ''; },
        onBack: () => { this.editorBack(); }
      }) {
        Stack() {
          if (this.scripts.length > 0) {
            Web({ src: this.pageUrl(), controller: this.controller })
              .javaScriptAccess(true)
              .javaScriptOnDocumentStart(this.scripts)
              .domStorageAccess(true)
              .fileAccess(false)
              .onControllerAttached(() => { this.bindDownloads(); })
              .onShowFileSelector((event: OnShowFileSelectorEvent) => { this.chooseFiles(event); return true; })
              .onLoadIntercept((event: OnLoadInterceptEvent) => this.allowNavigation(event))
              .onProgressChange((event: OnProgressChangeEvent) => { this.progress = event.newProgress; })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                if (event.request.isMainFrame()) this.error = '工具暂时不可用';
              })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                if (event.request.isMainFrame()) this.error = '连接失败，可查看本机缓存';
              })
              .width('100%').height('100%')
          }
          if (this.error.length > 0) {
            Column({ space: 12 }) {
              Text(this.error).fontColor(Tokens.TEXT_SECONDARY)
              Button('重试').onClick(() => { this.retry(); })
              Button(this.toolId === 'nt' ? '查看本机通知' : '查看本机班级作业')
                .onClick(() => { this.nativeView = true; this.error = ''; })
            }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(Tokens.BG)
          } else if (this.progress < 100) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%').height(2).align(Alignment.Top).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').height('100%')
      }
    }
  }
}
