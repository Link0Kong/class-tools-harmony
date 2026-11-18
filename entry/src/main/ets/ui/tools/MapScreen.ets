import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { AppGlobal } from '../../app/AppGlobal';
import { MapLoadState, MapLogic } from '../../features/map/MapModels';
import { Tokens } from '../theme/Tokens';
import { Immersive } from '../theme/Immersive';
import { Breakpoints } from '../theme/Breakpoints';
import { PageHeader } from '../components/PageHeader';

/**
 * 校内地图（ArkUI Web 加载 ECS H5，与网页/安卓同源方案）。
 *
 * - 数据源：`http://121.196.47.2/map/campus_final_25d.html?embed=1`（唯一数据源，不在原生侧重写 canvas）；
 * - 顶栏：返回 / 刷新 / 浏览器降级；
 * - 主文档加载失败：错误条提供「重试 / 浏览器打开」；
 * - Web 内部只允许 ECS 主机继续加载，其它链接交系统浏览器。
 */
@Component
export struct MapScreen {
  onClose: () => void = () => {
  };

  @State private state: MapLoadState = MapLoadState.LOADING;
  @State private progress: number = 0;
  @State private layoutWidth: number = 0;
  @State private wide: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.state = MapLoadState.LOADING;
  }

  private refresh(): void {
    try {
      this.state = MapLoadState.LOADING;
      this.progress = 0;
      this.controller.refresh();
    } catch (e) {
      this.state = MapLoadState.FAILED;
    }
  }

  private async openBrowser(): Promise<void> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return;
    }
    try {
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: MapLogic.pageUrl()
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
        this.getUIContext().getPromptAction().showToast({
          message: '无法打开浏览器（' + err.code + '）',
          systemMaterial: Immersive.dialogMaterial()
        });
    }
  }


  @Builder
  errorBar() {
    Row() {
      Text(MapLogic.stateText(MapLoadState.FAILED))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.WARM_SAND)
        .layoutWeight(1)
      Text('重试')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.MIST_TEAL)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.refresh();
        })
      Text('浏览器')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.SLATE_BLUE)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.openBrowser();
        })
    }
    .width('100%')
    .padding({ left: 14, right: 8, top: 6, bottom: 6 })
    .backgroundColor(Tokens.TINT_SAND)
  }

  @State private headerFade: number = 0;

  build() {
    Column() {
      PageHeader({
      progress: 0.6,
        title: '地图',
        actionText: '刷新',
        actionText2: '浏览器',
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.refresh();
        },
        onAction2: () => {
          this.openBrowser();
        }
      }) {
        Column() {
          if (this.state === MapLoadState.LOADING) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color(Tokens.MIST_TEAL)
              .backgroundColor(Tokens.DIVIDER)
          }

          if (MapLogic.showErrorBar(this.state)) {
            this.errorBar()
          }

          Web({ src: MapLogic.pageUrl(), controller: this.controller })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(true)
            .fileAccess(false)
            .imageAccess(true)
            .layoutWeight(1)
            .width('100%')
            .backgroundColor(Tokens.BG)
            .onPageBegin(() => {
              this.state = MapLoadState.LOADING;
            })
            .onProgressChange((event: OnProgressChangeEvent) => {
              this.progress = event.newProgress;
            })
            .onPageEnd(() => {
              this.state = MapLoadState.READY;
              this.progress = 100;
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event.request.isMainFrame()) {
                this.state = MapLoadState.FAILED;
              }
            })
            .onLoadIntercept((event: OnLoadInterceptEvent) => {
              const url: string = event.data.getRequestUrl();
              if (MapLogic.isAllowedNavigation(url)) {
                return false;
              }
              // 非 ECS 主机（如站外链接）交给系统浏览器，Web 内不加载。
              this.openBrowser();
              return true;
            })
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .padding({ top: Breakpoints.BREATH_TOP })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
        this.wide = Breakpoints.isWide(next);
      }
    })
  }
}
