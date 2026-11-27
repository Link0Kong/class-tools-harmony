import { HomeAtmosphere } from '../../features/home/HomeContext';
import { Motion } from '../theme/Motion';
import { Tokens } from '../theme/Tokens';

export function homeAtmosphereFeedback(scene: HomeAtmosphere): string {
  switch (scene) {
    case HomeAtmosphere.Rain: return '小伞已就位，今天也替你挡一点雨。';
    case HomeAtmosphere.Sun: return '给今天加一点亮色。';
    case HomeAtmosphere.Night: return '给今晚留一盏小灯。';
    default: return '';
  }
}

@Component
export struct HomeAtmosphereIcon {
  @Prop @Watch('onSceneChange') scene: HomeAtmosphere = HomeAtmosphere.None;
  @Prop @Watch('reset') active: boolean = true;
  @Prop @Watch('reset') motion: boolean = true;
  onTap: (scene: HomeAtmosphere) => void = () => {};

  @State private tilt: number = 0;
  @State private glow: number = 0;
  @State private glowScale: number = 1;
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private playing: boolean = false;
  private animationGeneration: number = 0;

  aboutToDisappear(): void {
    this.ready = false;
    this.animationGeneration += 1;
    this.playing = false;
  }

  private reset(): void {
    this.animationGeneration += 1;
    this.playing = false;
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.tilt = 0;
      this.glow = 0;
      this.glowScale = 1;
    });
  }

  private onSceneChange(): void {
    this.reset();
    this.draw();
  }

  private label(): string {
    if (this.scene === HomeAtmosphere.Rain) return '轻点小伞';
    if (this.scene === HomeAtmosphere.Sun) return '轻点太阳';
    return '点亮小灯';
  }

  private tap(): void {
    if (!this.active) return;
    this.onTap(this.scene);
    if (!this.motion || this.playing) return;
    this.playing = true;
    const generation = ++this.animationGeneration;
    const done = () => {
      if (generation === this.animationGeneration) this.playing = false;
    };
    if (this.scene === HomeAtmosphere.Rain) {
      this.getUIContext().keyframeAnimateTo({ onFinish: done }, [
        { duration: 110, curve: Motion.ease(), event: () => { this.tilt = -8; } },
        { duration: 190, curve: Motion.ease(), event: () => { this.tilt = 5; } },
        { duration: 130, curve: Motion.ease(), event: () => { this.tilt = 0; } }
      ]);
    } else {
      this.getUIContext().keyframeAnimateTo({ onFinish: done }, [
        { duration: 160, curve: Motion.ease(), event: () => {
          this.glow = 0.24;
          this.glowScale = 1.26;
        } },
        { duration: 280, curve: Motion.ease(), event: () => {
          this.glow = 0;
          this.glowScale = 1;
        } }
      ]);
    }
  }

  private line(x: number, y: number, endX: number, endY: number): void {
    this.canvas.beginPath();
    this.canvas.moveTo(x, y);
    this.canvas.lineTo(endX, endY);
    this.canvas.stroke();
  }

  private draw(): void {
    if (!this.ready) return;
    const ctx = this.canvas;
    ctx.clearRect(0, 0, 36, 36);
    ctx.strokeStyle = this.scene === HomeAtmosphere.Rain ? Tokens.MIST_TEAL : '#8C5B19';
    ctx.fillStyle = this.scene === HomeAtmosphere.Rain ? 'rgba(78,144,130,0.14)' : 'rgba(185,137,67,0.18)';
    ctx.lineWidth = 1.7;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    if (this.scene === HomeAtmosphere.Rain) {
      ctx.beginPath();
      ctx.moveTo(5, 20);
      ctx.bezierCurveTo(7, 8, 27, 8, 29, 20);
      ctx.quadraticCurveTo(26, 17, 23, 20);
      ctx.quadraticCurveTo(20, 17, 17, 20);
      ctx.quadraticCurveTo(14, 17, 11, 20);
      ctx.quadraticCurveTo(8, 17, 5, 20);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(17, 20);
      ctx.lineTo(17, 28);
      ctx.bezierCurveTo(17, 33, 24, 33, 24, 28);
      ctx.stroke();
      this.line(25, 4, 23, 7);
      this.line(32, 8, 30, 11);
    } else if (this.scene === HomeAtmosphere.Sun) {
      ctx.beginPath();
      ctx.arc(18, 18, 6.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      for (let ray = 0; ray < 8; ray++) {
        const angle = Math.PI * ray / 4;
        const x = Math.cos(angle);
        const y = Math.sin(angle);
        this.line(18 + x * 10, 18 + y * 10, 18 + x * 13.6, 18 + y * 13.6);
      }
    } else if (this.scene === HomeAtmosphere.Night) {
      ctx.beginPath();
      ctx.moveTo(13.6, 8.5);
      ctx.lineTo(22.4, 8.5);
      ctx.lineTo(27, 19);
      ctx.lineTo(9, 19);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      this.line(18, 19.8, 18, 28);
      this.line(12.7, 28, 23.3, 28);
    }
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.scene !== HomeAtmosphere.Rain) {
          Circle()
            .width(this.scene === HomeAtmosphere.Sun ? 28 : 21)
            .height(this.scene === HomeAtmosphere.Sun ? 28 : 21)
            .fill(Tokens.WARM_SAND)
            .opacity(0.08 + this.glow)
            .scale({ x: this.glowScale, y: this.glowScale })
        }
        Canvas(this.canvas)
          .width(36).height(36)
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
          .rotate({ angle: this.tilt })
          .hitTestBehavior(HitTestMode.None)
      }.width(36).height(36)
    }
    .width(52).height(52).padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label())
    .id('home_context_atmosphere')
    .onClick(() => { this.tap(); })
  }
}
