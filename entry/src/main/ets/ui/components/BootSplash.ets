import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import display from '@ohos.display';

@Component
export struct BootSplash {
  @Prop @Watch('startLeave') leaving: boolean = false;
  @Prop barHandoff: boolean = true;
  onDone: () => void = () => {
  };

  @State private spin: number = 0;
  @State private bgAlpha: number = 1;
  @State private wordAlpha: number = 0;
  @State private travelY: number = 0;
  @State private gap: number = 38;
  @State private drop: number = 1;
  @State private dotW: number = 22;
  @State private dotH: number = 22;
  @State private dotAlpha: number = 1;
  @State private rootW: number = 360;
  @State private rootH: number = 760;
  private doneFired: boolean = false;

  aboutToAppear(): void {
    const ui = this.getUIContext();
    try {
      const info = display.getDefaultDisplaySync();
      this.rootW = px2vp(info.width);
      this.rootH = px2vp(info.height);
    } catch (e) {
      this.rootW = 360;
      this.rootH = 760;
    }
    ui.animateTo({ duration: 420, curve: Motion.ease() }, () => {
      this.wordAlpha = 1;
    });
    setTimeout(() => {
      ui.animateTo({ duration: 2800, curve: Curve.Linear, iterations: -1 }, () => {
        this.spin = 360;
      });
    }, 40);
  }

  private finish(): void {
    if (!this.doneFired) {
      this.doneFired = true;
      this.onDone();
    }
  }

  private startLeave(): void {
    if (!this.leaving) {
      return;
    }
    const ui = this.getUIContext();
    if (!this.barHandoff) {
      ui.animateTo({ duration: 240, curve: Motion.ease() }, () => {
        this.bgAlpha = 0;
        this.dotAlpha = 0;
        this.wordAlpha = 0;
      });
      setTimeout(() => {
        this.finish();
      }, 260);
      return;
    }

    const barW: number = this.rootW * 0.2625;
    const targetY: number = -this.rootH * 0.411;
    const settleSpin: number = this.spin + (360 - this.spin % 360);

    ui.animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.wordAlpha = 0;
    });
    ui.animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.spin = settleSpin;
    });
    ui.animateTo({ duration: 380, delay: 120, curve: Curve.FastOutSlowIn }, () => {
      this.travelY = targetY;
      this.gap = barW;
      this.drop = 0;
      this.dotW = barW;
      this.dotH = 3;
    });
    ui.animateTo({ duration: 300, delay: 40, curve: Curve.EaseInOut }, () => {
      this.bgAlpha = 0;
    });
    ui.animateTo({ duration: 80, delay: 380, curve: Curve.EaseIn }, () => {
      this.dotAlpha = 0;
    });
    setTimeout(() => {
      this.finish();
    }, 470);
  }

  @Builder
  orbitDots() {
    Row()
      .width(this.dotW)
      .height(this.dotH)
      .borderRadius(this.dotH / 2)
      .backgroundColor(Tokens.MIST_TEAL)
      .translate({ x: -this.gap, y: this.drop * 22 })
      .opacity(this.dotAlpha)
    Row()
      .width(this.dotW)
      .height(this.dotH)
      .borderRadius(this.dotH / 2)
      .backgroundColor(Tokens.SLATE_BLUE)
      .translate({ x: 0, y: -this.drop * 44 })
      .opacity(this.dotAlpha)
    Row()
      .width(this.dotW)
      .height(this.dotH)
      .borderRadius(this.dotH / 2)
      .backgroundColor(Tokens.WARM_SAND)
      .translate({ x: this.gap, y: this.drop * 22 })
      .opacity(this.dotAlpha)
  }

  build() {
    Stack() {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#F7F8F8')
        .opacity(this.bgAlpha)

      Stack() {
        Stack() {
          this.orbitDots()
        }
        .width('100%')
        .height('100%')
        .rotate({ angle: this.spin })
      }
      .width('100%')
      .height('100%')
      .translate({ y: this.travelY })

      Column({ space: 4 }) {
        Text('枫丹工具箱')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#303A35')
          .letterSpacing(1)
        Text('MONET TOOLBOX')
          .fontSize(9)
          .fontColor('#7A8A83')
          .letterSpacing(2.4)
      }
      .translate({ y: 88 })
      .opacity(this.wordAlpha)
    }
    .width('100%')
    .height('100%')
  }
}
