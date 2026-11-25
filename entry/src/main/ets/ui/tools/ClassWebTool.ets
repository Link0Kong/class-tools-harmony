import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { Services } from '../../app/Services';
import { AppGlobal } from '../../app/AppGlobal';
import { Session } from '../../data/session/Session';
import { PageHeader } from '../components/PageHeader';
import { Tokens } from '../theme/Tokens';
import { HomeworkScreen } from './HomeworkScreen';
import { NoticeScreen } from './NoticeScreen';

const SITE = 'https://tool.furina.fun';

@Component
export struct ClassWebTool {
  @Prop toolId: string = 'hw';
  onClose: () => void = () => {};
  @State private nativeView: boolean = false;
  @State private scripts: ScriptItem[] = [];
  @State private error: string = '';
  @State private progress: number = 0;
  private controller = new webview.WebviewController();
  private downloads = new webview.WebDownloadDelegate();
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.prepareSession();
  }

  aboutToDisappear(): void {
    this.active = false;
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
    if (this.nativeView) {
      if (this.toolId === 'nt') {
        NoticeScreen({ onClose: () => { this.nativeView = false; } })
      } else {
        HomeworkScreen({ onClose: () => { this.nativeView = false; } })
      }
    } else {
      PageHeader({
        title: this.toolId === 'nt' ? '通知' : '任务',
        actionText: this.toolId === 'nt' ? '本机通知' : '本机班级作业',
        onAction: () => { this.nativeView = true; this.error = ''; },
        onBack: this.onClose
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
