import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';

/** Workbench card shell: glass surface, press feedback, bottom-right resize grip border. */
@Component
export struct HomeCardShell {
  @Prop cardHeightVp: number = 150;
  @Prop accentColor: string = Tokens.MIST_TEAL;
  @Prop resizing: boolean = false;
  onCardTap: () => void = () => {
  };
  onResize: (phase: string, dx: number) => void = () => {
  };
  @BuilderParam content: () => void = this.emptyContent;

  @State private gripActive: boolean = false;

  /** 缩放提示只用右下角边框线：常态略粗，按住时再加粗。 */
  private gripEdgeWidth(): number {
    return this.gripActive || this.resizing ? 3 : 2;
  }

  private edgeColor(): string {
    return this.gripActive || this.resizing ? Tokens.tint(this.accentColor, 0.62) : Tokens.CARD_EDGE;
  }

  private gripColor(): string {
    return this.gripActive || this.resizing ? this.accentColor : Tokens.tint(this.accentColor, 0.55);
  }

  private liftRadius(): number {
    return this.gripActive || this.resizing ? 22 : 14;
  }

  private liftColor(): string {
    return this.gripActive || this.resizing ? Tokens.tint(this.accentColor, 0.22) : '#0B1C2629';
  }

  private liftOffsetY(): number {
    return this.gripActive || this.resizing ? 8 : 4;
  }

  @Builder
  emptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row()
          .width('100%')
          .height(3)
          .backgroundColor(Tokens.tint(this.accentColor, 0.55))
          .borderRadius(2)
          .margin({ bottom: 9 })
        Column() {
          this.content()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .padding(Tokens.CARD_PADDING)
      .alignItems(HorizontalAlign.Start)

      Stack() {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('#01000000')
      }
      .width(56)
      .height(56)
      .hitTestBehavior(HitTestMode.Block)
      .accessibilityText('拖动缩放卡片')
      .priorityGesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
            .onActionStart(() => {
              this.gripActive = true;
              this.onResize('start', 0);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onResize('update', event.offsetX);
            })
            .onActionEnd(() => {
              this.gripActive = false;
              this.onResize('end', 0);
            })
            .onActionCancel(() => {
              this.gripActive = false;
              this.onResize('end', 0);
            })
        )
    }
    .width('100%')
    .height(this.cardHeightVp)
    .backgroundColor(Tokens.CARD)
    .border({
      width: {
        left: 0.5,
        top: 0.5,
        right: this.gripEdgeWidth(),
        bottom: this.gripEdgeWidth()
      },
      color: {
        left: this.edgeColor(),
        top: this.edgeColor(),
        right: this.gripColor(),
        bottom: this.gripColor()
      }
    })
    .borderRadius(Tokens.RADIUS_CARD)
    .shadow({
      radius: this.liftRadius(),
      color: this.liftColor(),
      offsetX: 0,
      offsetY: this.liftOffsetY()
    })
    .clip(true)
    .stateStyles({
      pressed: {
        .scale({ x: 0.985, y: 0.985 })
      }
    })
    .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
    .transition(Motion.popIn())
    .onClick(() => {
      this.onCardTap();
    })
  }
}
