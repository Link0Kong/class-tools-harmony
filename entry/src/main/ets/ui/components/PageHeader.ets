import { PageInsets } from '../theme/PageInsets';
import { Breakpoints } from '../theme/Breakpoints';
﻿import { Immersive } from '../theme/Immersive';
import { Tokens } from '../theme/Tokens';

/**
 * 工具页统一顶栏（沉浸光感）。
 *
 * - 静止时完全透明，页面顶部不出现独立颜色条；
 * - 页面滑动后，顶栏底色随滚动距离线性淡入一层柔和渐变，
 *   与底部悬浮操作条保持同一套层次语言；
 * - 返回 / 次级动作统一为圆形玻璃按钮 + 原生系统材质菜单，
 *   不再平铺一排文字按钮。
 */
@Component
export struct PageHeader {
  @Prop inset: number = PageInsets.HORIZONTAL;
  @Prop taskColors: boolean = false;
  @Prop showAmbientBackground: boolean = false;
  @Prop title: string = '';
  @Prop actionText: string = '';
  @Prop actionText2: string = '';
  @Prop actionText3: string = '';
  /** 0（顶部透明）→ 1（完全淡入）的滚动进度。 */
  @Prop progress: number = 0;
  /** 页面主滚动容器（保留给后续滚动联动，当前由 progress 驱动）。 */
  scroller: Scroller = new Scroller();
  @BuilderParam content: () => void = this.emptyContent;
  onBack: () => void = () => {
  };
  onAction: () => void = () => {
  };
  onAction2: () => void = () => {
  };
  onAction3: () => void = () => {
  };

  @Builder
  emptyContent() {
  }

  private hasMenu(): boolean {
    return this.actionText.length > 0 || this.actionText2.length > 0 || this.actionText3.length > 0;
  }

  private menuItems(): MenuElement[] {
    const items: MenuElement[] = [];
    if (this.actionText.length > 0) {
      items.push({
        value: this.actionText,
        action: () => {
          this.onAction();
        }
      });
    }
    if (this.actionText2.length > 0) {
      items.push({
        value: this.actionText2,
        action: () => {
          this.onAction2();
        }
      });
    }
    if (this.actionText3.length > 0) {
      items.push({
        value: this.actionText3,
        action: () => {
          this.onAction3();
        }
      });
    }
    return items;
  }

  @Builder
  headerBar() {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: Tokens.TEXT_GAP_H }) {
        Text('‹')
          .fontSize(30)
          .fontWeight(FontWeight.Lighter)
          .fontColor(this.taskColors ? $r('app.color.task_text') : Tokens.TEXT_PRIMARY)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBack();
          })

        Text(this.title)
          .fontSize(Tokens.F_HEADING)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.taskColors ? $r('app.color.task_text') : Tokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.hasMenu()) {
          Text('⋯')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.taskColors ? $r('app.color.task_text') : Tokens.TEXT_PRIMARY)
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .bindMenu(this.menuItems(), { systemMaterial: Immersive.dialogMaterial() })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: this.inset, right: this.inset })
    }
    .width('100%')
    .height(56)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.showAmbientBackground ? $r('app.color.task_glass_bar') :
            this.taskColors ? $r('app.color.task_card') : Tokens.GLASS)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: { bottom: 0.5 }, color: this.showAmbientBackground ? $r('app.color.task_glass_edge') : Tokens.GLASS_STROKE })
          .opacity(this.progress)
          .hitTestBehavior(HitTestMode.None)
        this.headerBar()
      }
      .width('100%')
      .height(56)
      Column() {
        this.content()
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: Tokens.GAP_SM, bottom: Breakpoints.PAGE_BOTTOM })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.taskColors && !this.showAmbientBackground ? $r('app.color.task_page') : Color.Transparent)
  }
}
