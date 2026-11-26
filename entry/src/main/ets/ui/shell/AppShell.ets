import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Immersive } from '../theme/Immersive';
import { Breakpoints } from '../theme/Breakpoints';
import { AppSymbols } from '../theme/AppSymbols';
import { HomeTools, HomeToolsToggleResult } from '../../data/home/HomeTools';
import { HomeScreen } from '../screens/HomeScreen';
import { AllScreen } from '../screens/AllScreen';
import { MeScreen } from '../screens/MeScreen';
import { showFeedback } from '../components/AppFeedback';
import {
  BlurStrategy,
  hdsMaterial,
  HdsNavigation,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  ScrollEffectType,
  TitleSize
} from '@kit.UIDesignKit';

/**
 * 应用外壳：工作台 / 全部 / 我的。
 *
 * 响应式导航（对齐平板设计规范）：
 * - 手机 / 折叠屏折叠态：底部悬浮胶囊页签（HdsTabs horizontal）；
 * - 平板横屏 / 折叠屏展开 / 2in1：左侧竖向导航栏（HdsTabs vertical），
 *   内容区获得更宽的横向空间，避免底部导航在大屏上被简单拉伸。
 */
@Component
export struct AppShell {
  @Prop @Watch('goToNotifications') notifyRequest: boolean = false;
  onNotifyHandled: () => void = () => {};
  @Prop @Watch('goHome') homeRequest: number = 0;
  @Prop contentEpoch: number = 0;
  @Prop userName: string = '';
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop isAdmin: boolean = false;
  @Prop quickIds: string[] = [];
  @Prop syncState: string = '';
  onOpenTool: (id: string) => void = () => {
  };
  onHomeReady: () => void = () => {
  };
  onSetHomeTools: (ids: string[]) => void = () => {
  };
  onSyncNow: () => void = () => {
  };
  onLogout: () => void = () => {
  };

  @State private activeTab: number = 0;
  @State private editHome: boolean = false;
  @State private homeEpoch: number = 0;
  @State private homeAddEpoch: number = 0;
  @State private layoutWidth: number = 0;
  private homeScroller: Scroller = new Scroller();
  @State private tabPulse: number[] = [-1, -1, -1];
  private controller: HdsTabsController = new HdsTabsController();
  private materialLevel: hdsMaterial.MaterialLevel = Immersive.hdsLevel();

  private goToNotifications(): void {
    if (this.notifyRequest) this.switchTab(2);
  }

  private goHome(): void {
    this.switchTab(0);
  }

  private sideNav(): boolean {
    return Breakpoints.useSideNav(this.layoutWidth);
  }

  private title(): string {
    if (this.activeTab === 1) {
      return '全部工具';
    }
    if (this.activeTab === 2) {
      return '我的';
    }
    return '工作台';
  }

  private tabSymbol(index: number): Resource {
    return AppSymbols.tab(index);
  }

  private toggleEditHome(): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.softSpring() }, () => {
      this.editHome = !this.editHome;
    });
  }

  /**
   * 标题栏右侧按钮：
   * - 工作台：[加号]（添加卡片）+ [设置]（切换编辑态）；
   * - 全部：[设置]（切换常用工具编辑态）。
   */
  private titleMenus(): HdsNavigationMenuItemOptions[] {
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.activeTab === 2) {
      return items;
    }
    if (this.activeTab === 0) {
      const addIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.plus'),
        action: () => {
          this.homeAddEpoch += 1;
        }
      };
      items.push({ content: addIcon });
    }
    const icon: HdsNavigationIconOptions = {
      icon: this.editHome ? $r('sys.symbol.gearshape_fill') : $r('sys.symbol.gearshape'),
      action: () => {
        this.toggleEditHome();
      }
    };
    items.push({ content: icon });
    return items;
  }

  private bumpTab(index: number): void {
    this.tabPulse[index] = this.tabPulse[index] + 1;
  }

  private switchTab(index: number): void {
    if (index === this.activeTab) {
      return;
    }
    this.activeTab = index;
    this.bumpTab(index);
    this.controller.changeIndex(index);
    if (index === 0) {
      this.homeEpoch += 1;
    }
  }

  private toggleQuick(id: string): void {
    const result: HomeToolsToggleResult = HomeTools.toggle(this.quickIds, id);
    if (result.rejected === 'full') {
      showFeedback(this.getUIContext(), '首页最多 4 个');
      return;
    }
    if (result.changed) {
      this.onSetHomeTools(result.ids);
    }
  }

  @Builder
  tabItem(index: number, label: string) {
    if (this.sideNav()) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.tabSymbol(index))
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.activeTab === index ? Tokens.MIST_TEAL : Tokens.TEXT_SECONDARY])
            .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), this.tabPulse[index])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.activeTab === index ? Tokens.TINT_TEAL : Color.Transparent)
        .borderRadius(12)
        .animation({ duration: Motion.FAST, curve: Motion.ease() })
        Text(label)
          .fontSize(11)
          .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.activeTab === index ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
          .margin({ top: 4 })
          .animation({ duration: Motion.FAST, curve: Motion.ease() })
      }
      .width('100%')
      .height(74)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.tabSymbol(index))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.activeTab === index ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY])
            .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), this.tabPulse[index])
        }
        .width(26)
        .height(24)
        .animation({ duration: Motion.FAST, curve: Motion.ease() })
        Text(label)
          .fontSize(10)
          .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.activeTab === index ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
          .animation({ duration: Motion.FAST, curve: Motion.ease() })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  bottomScrim() {
    Column()
      .width('100%')
      .height(150)
      .linearGradient({
        angle: 180,
        colors: [
          ['#00F6F7F8', 0.0],
          ['#B8F6F7F8', 0.5],
          ['#FFF6F7F8', 1.0]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    HdsNavigation() {
      HdsTabs({ controller: this.controller }) {
        TabContent() {
          Stack({ alignContent: Alignment.Bottom }) {
            HomeScreen({
              scroller: this.homeScroller,
              userName: this.userName,
              maskedSid: this.maskedSid,
              roleLabel: this.roleLabel,
              quickIds: this.quickIds,
              epoch: this.homeEpoch + this.contentEpoch,
              onReorderQuick: (ids: string[]) => {
                this.onSetHomeTools(HomeTools.normalize(ids));
              },
              editing: this.editHome,
              addEpoch: this.homeAddEpoch,
              onOpenTool: (id: string) => {
                this.onOpenTool(id);
              },
              onHomeReady: () => {
                this.onHomeReady();
              },
              onOpenAll: () => {
                this.switchTab(1);
              }
            })
            if (!this.sideNav()) {
              this.bottomScrim()
            }
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(this.tabItem(0, '工作台'))

        TabContent() {
          Stack({ alignContent: Alignment.Bottom }) {
            AllScreen({
              editing: this.editHome,
              quickIds: this.quickIds,
              onToggleQuick: (id: string) => {
                this.toggleQuick(id);
              },
              onToggleEdit: () => {
                this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.softSpring() }, () => {
                  this.editHome = !this.editHome;
                });
              },
              onReorderQuick: (ids: string[]) => {
                this.onSetHomeTools(HomeTools.normalize(ids));
              },
              onOpenTool: (id: string) => {
                this.onOpenTool(id);
              }
            })
            if (!this.sideNav()) {
              this.bottomScrim()
            }
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(this.tabItem(1, '全部'))

        TabContent() {
          Stack({ alignContent: Alignment.Bottom }) {
            MeScreen({
              notifyRequest: this.notifyRequest,
              onNotifyHandled: this.onNotifyHandled,
              userName: this.userName,
              maskedSid: this.maskedSid,
              roleLabel: this.roleLabel,
              isAdmin: this.isAdmin,
              syncState: this.syncState,
              onSyncNow: () => {
                this.onSyncNow();
              },
              onOpenTool: (id: string) => {
                this.onOpenTool(id);
              },
              onLogout: () => {
                this.onLogout();
              }
            })
            if (!this.sideNav()) {
              this.bottomScrim()
            }
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(this.tabItem(2, '我的'))
      }
      .vertical(this.sideNav())
      .barPosition(this.sideNav() ? BarPosition.Start : BarPosition.End)
      .barMode(BarMode.Fixed)
      .barOverlap(!this.sideNav())
      .barBackgroundColor(this.sideNav() ? Tokens.GLASS : Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .scrollable(!this.sideNav())
      .animationDuration(Motion.NORMAL)
      .barFloatingStyle(this.sideNav() ? undefined : {
        barBottomMargin: 16,
        adaptToHandedness: true,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        }
      })
      .backgroundColor(Color.Transparent)
      .onChange((index: number) => {
        if (index !== this.activeTab) {
          this.activeTab = index;
          this.bumpTab(index);
        }
      })
    }
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .hideToolBar(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar({
      content: {
        title: {
          mainTitle: this.title(),
          mainTitleSize: TitleSize.TITLE_S
        },
        menu: {
          value: this.titleMenus(),
          maxCount: 2
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
            maskExtraHeight: 0
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: Tokens.TEXT_PRIMARY
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
            maskExtraHeight: 0
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: Tokens.TEXT_PRIMARY
            }
          }
        },
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        },
        blurStrategy: BlurStrategy.ENABLE
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
