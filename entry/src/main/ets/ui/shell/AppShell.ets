import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { HomeTools, HomeToolsToggleResult } from '../../data/home/HomeTools';
import { HomeScreen } from '../screens/HomeScreen';
import { AllScreen } from '../screens/AllScreen';
import { MeScreen } from '../screens/MeScreen';

/** 应用外壳：工作台 / 全部 / 我的（底部自定义 tab + 液体指示条 + 页面滑动切换）。 */
@Component
export struct AppShell {
  @Prop userName: string = '';
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop isAdmin: boolean = false;
  @Prop quickIds: string[] = [];
  @Prop syncState: string = '';
  onOpenTool: (id: string) => void = () => {
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
  @State private barWidth: number = 0;
  @State private stretch: number = 0;
  private controller: TabsController = new TabsController();
  private stretchTimer: number = -1;

  private switchTab(index: number): void {
    if (index === this.activeTab) {
      return;
    }
    // 液体动效：先拉长指示条，再弹性吸附到目标 tab
    this.getUIContext().animateTo({ duration: 110, curve: Motion.ease() }, () => {
      this.stretch = 1;
    });
    if (this.stretchTimer >= 0) {
      clearTimeout(this.stretchTimer);
    }
    this.stretchTimer = setTimeout(() => {
      this.stretchTimer = -1;
      this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.spring() }, () => {
        this.activeTab = index;
        this.stretch = 0;
      });
      if (index === 0) {
        this.homeEpoch += 1;
      }
    }, 90);
    this.controller.changeIndex(index);
  }

  private toggleQuick(id: string): void {
    const result: HomeToolsToggleResult = HomeTools.toggle(this.quickIds, id);
    if (result.rejected === 'full') {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '首页最多 4 个' });
      } catch (e) {
        // toast 失败不影响主流程
      }
      return;
    }
    if (result.changed) {
      this.onSetHomeTools(result.ids);
    }
  }

  private itemWidth(): number {
    return this.barWidth > 0 ? this.barWidth / 3 : 0;
  }

  private indicatorX(): number {
    const itemW: number = this.itemWidth();
    if (itemW <= 0) {
      return 0;
    }
    return itemW * this.activeTab + itemW / 2 - (24 + 16 * this.stretch) / 2;
  }

  @Builder
  tabItem(index: number, label: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.activeTab === index ? Tokens.MIST_TEAL : Tokens.TEXT_TERTIARY)
        .animation({ duration: Motion.FAST, curve: Motion.ease() })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchTab(index);
    })
  }

  @Builder
  bottomBar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        this.tabItem(0, '工作台')
        this.tabItem(1, '全部')
        this.tabItem(2, '我的')
      }
      .width('100%')
      .height('100%')

      Column()
        .width(24 + 16 * this.stretch)
        .height(3)
        .borderRadius(2)
        .backgroundColor(Tokens.MIST_TEAL)
        .offset({ x: this.indicatorX(), y: -10 })
        .opacity(this.barWidth > 0 ? 1 : 0)
        .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
    }
    .width('100%')
    .height(58)
    .constraintSize({ maxWidth: 960 })
    // 浅色底栏无黑影：纯浅色 + 顶部发丝线，显式零阴影（不叠系统对比度蒙层/投影）。
    .backgroundColor(Tokens.BAR_LIGHT)
    .border({ width: { top: 0.5 }, color: Tokens.DIVIDER })
    .shadow({ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);
      if (width > 0 && Math.abs(width - this.barWidth) > 1) {
        this.barWidth = width;
      }
    })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.activeTab, controller: this.controller }) {
        TabContent() {
          HomeScreen({
            userName: this.userName,
            maskedSid: this.maskedSid,
            roleLabel: this.roleLabel,
            quickIds: this.quickIds,
            epoch: this.homeEpoch,
            editing: this.editHome,
            onToggleEdit: () => {
              this.editHome = !this.editHome;
            },
            onRemoveQuick: (id: string) => {
              this.onSetHomeTools(HomeTools.remove(this.quickIds, id));
            },
            onAddQuick: () => {
              this.editHome = true;
              this.switchTab(1);
            },
            onEditQuick: () => {
              this.editHome = true;
              this.switchTab(1);
            },
            onOpenTool: (id: string) => {
              this.onOpenTool(id);
            },
            onOpenAll: () => {
              this.switchTab(1);
            }
          })
        }

        TabContent() {
          AllScreen({
            editing: this.editHome,
            quickIds: this.quickIds,
            onToggleQuick: (id: string) => {
              this.toggleQuick(id);
            },
            onToggleEdit: () => {
              this.editHome = !this.editHome;
            },
            onOpenTool: (id: string) => {
              this.onOpenTool(id);
            }
          })
        }

        TabContent() {
          MeScreen({
            userName: this.userName,
            maskedSid: this.maskedSid,
            roleLabel: this.roleLabel,
            isAdmin: this.isAdmin,
            syncState: this.syncState,
            onSyncNow: () => {
              this.onSyncNow();
            },
            onLogout: () => {
              this.onLogout();
            }
          })
        }
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 960 })
      .barHeight(0)
      .barBackgroundColor(Color.Transparent)
      .divider({ strokeWidth: 0 })
      .scrollable(false)
      .animationDuration(Motion.NORMAL)
      .animationMode(AnimationMode.CONTENT_FIRST)
      .backgroundColor(Tokens.BG)
      .onChange((index: number) => {
        if (index !== this.activeTab) {
          this.activeTab = index;
        }
      })

      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    .padding({ top: Tokens.BREATH_TOP })
    .backgroundColor(Tokens.BG)
  }
}
