import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { AppGlobal } from '../../app/AppGlobal';
import { MapLoadState, MapLogic } from '../../features/map/MapModels';
import { Tokens } from '../theme/Tokens';
import { Breakpoints } from '../theme/Breakpoints';
import { PageHeader } from '../components/PageHeader';
import { EMBEDDED_FEEDBACK_SCRIPT, showFeedback } from '../components/AppFeedback';

@Component
export struct MapScreen {
  @Prop room: string = '';
  onClose: () => void = () => {
  };

  @State private state: MapLoadState = MapLoadState.LOADING;
  @State private progress: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private online: boolean = false;
  private active: boolean = false;
  private loadId: number = 0;
  private timeout: number = -1;
  private backing: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    AppGlobal.toolBack = this.handleBack;
    this.beginLoad();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (AppGlobal.toolBack === this.handleBack) AppGlobal.toolBack = undefined;
    clearTimeout(this.timeout);
  }

  private handleBack = (): boolean => {
    if (!this.active) return false;
    if (this.backing) return true;
    if (this.state !== MapLoadState.READY) {
      this.onClose();
      return true;
    }
    this.dismissMap();
    return true;
  };

  private async dismissMap(): Promise<void> {
    this.backing = true;
    const id: number = this.loadId;
    let dismissed: boolean = false;
    try {
      const result: string = await this.controller.runJavaScript(
        "typeof window.zqMapDismiss === 'function' && window.zqMapDismiss()");
      dismissed = result === 'true';
    } catch (_) {
      // ArkWeb can exit between a back press and the script callback.
    } finally {
      this.backing = false;
    }
    if (this.active && id === this.loadId && !dismissed) this.onClose();
  }

  private beginLoad(): void {
    clearTimeout(this.timeout);
    this.state = MapLoadState.LOADING;
    this.progress = 0;
    this.loadId += 1;
    const id: number = this.loadId;
    this.timeout = setTimeout(() => {
      if (this.checking(id)) this.failLoad();
    }, 8500);
  }

  private checking(id: number): boolean {
    return this.active && id === this.loadId && this.state === MapLoadState.LOADING;
  }

  private reload(online: boolean): void {
    this.online = online;
    this.beginLoad();
    try {
      this.controller.loadUrl(MapLogic.pageUrl(this.room, true, !online));
    } catch (e) {
      this.failLoad();
    }
  }

  private failLoad(): void {
    clearTimeout(this.timeout);
    if (!this.active || this.state !== MapLoadState.LOADING) return;
    if (!this.online) {
      this.reload(true);
      return;
    }
    this.state = MapLoadState.FAILED;
  }

  private matchesCurrent(url: string): boolean {
    return this.online ? MapLogic.isAllowedNavigation(url) : MapLogic.isLocalPage(url);
  }

  private async checkRendered(id: number): Promise<void> {
    for (let i = 0; i < 24 && this.checking(id); i++) {
      try {
        const ready: string = await this.controller.runJavaScript('window.zqMapReady === true');
        if (!this.checking(id)) return;
        if (ready === 'true') {
          this.controller.runJavaScript(EMBEDDED_FEEDBACK_SCRIPT).catch(() => {});
          clearTimeout(this.timeout);
          this.state = MapLoadState.READY;
          this.progress = 100;
          return;
        }
      } catch (e) {
        // ArkWeb 首次布局或切换文档时可能尚未准备好。
      }
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 250); });
    }
  }

  private async openBrowser(uri: string): Promise<void> {
    const context = AppGlobal.context;
    if (context === undefined) return;
    try {
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: uri
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (this.active) showFeedback(this.getUIContext(), '无法打开浏览器（' + err.code + '）');
    }
  }

  build() {
    Column() {
      PageHeader({
        progress: 0.6,
        title: '校内地图',
        actionText: '重载',
        actionText2: '浏览器',
        onBack: () => { this.handleBack(); },
        onAction: () => { this.reload(false); },
        onAction2: () => { this.openBrowser(MapLogic.pageUrl(this.room, false)); }
      }) {
        Stack() {
          Web({ src: MapLogic.pageUrl(this.room, true, true), controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .zoomAccess(false)
            .darkMode(WebDarkMode.Auto)
            .fileAccess(false)
            .backgroundColor(Tokens.BG)
            .onProgressChange((event: OnProgressChangeEvent) => {
              if (this.state === MapLoadState.LOADING) this.progress = Math.min(event.newProgress, 95);
            })
            .onPageEnd((event: OnPageEndEvent) => {
              if (this.matchesCurrent(event.url) && this.checking(this.loadId)) this.checkRendered(this.loadId);
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event.request.isMainFrame() && this.matchesCurrent(event.request.getRequestUrl())) this.failLoad();
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
              if (event.request.isMainFrame() && this.matchesCurrent(event.request.getRequestUrl())) this.failLoad();
            })
            .onRenderExited(() => {
              clearTimeout(this.timeout);
              this.state = MapLoadState.FAILED;
            })
            .onLoadIntercept((event: OnLoadInterceptEvent) => {
              const url: string = event.data.getRequestUrl();
              if (MapLogic.isLocalPage(url) || MapLogic.isAllowedNavigation(url)) return false;
              if (event.data.isMainFrame() && (url.startsWith('https://') || url.startsWith('http://'))) {
                this.openBrowser(url);
              }
              return true;
            })

          if (this.state === MapLoadState.LOADING) {
            Column() {
              Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(2)
                .color(Tokens.MIST_TEAL)
                .backgroundColor(Tokens.DIVIDER)
              Blank()
            }
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Transparent)
          }

          if (MapLogic.showErrorBar(this.state)) {
            Column({ space: 12 }) {
              Text(MapLogic.stateText(this.state)).fontSize(Tokens.F_BODY).fontColor(Tokens.TEXT_SECONDARY)
              Button('重试').height(44).onClick(() => { this.reload(false); })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Tokens.BG)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .padding({ top: Breakpoints.BREATH_TOP })
  }
}
