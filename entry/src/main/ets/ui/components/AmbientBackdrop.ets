import { Tokens } from '../theme/Tokens';

/**
 * 全局环境光背景：柔和的空气感极光。
 * 光晕位置与半径按实际可用宽高计算，手机 / 折叠屏 / 平板都能均匀铺满，
 * 避免大屏上光晕挤在左上角、整块背景发白。
 */
@Component
export struct AmbientBackdrop {
  @State private w: number = 0;
  @State private h: number = 0;

  private spread(): number {
    const maxSide: number = Math.max(this.w, this.h);
    return Math.max(520, maxSide * 0.62);
  }

  private cx(ratio: number): number {
    return this.w > 0 ? this.w * ratio : ratio * 400;
  }

  private cy(ratio: number): number {
    return this.h > 0 ? this.h * ratio : ratio * 800;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 165,
          colors: [
            [Tokens.BG_TOP, 0.0],
            [Tokens.BG_MID, 0.48],
            [Tokens.BG_BOTTOM, 1.0]
          ]
        })

      // 左上：睡莲青
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [this.cx(0.02), this.cy(0.0)],
          radius: this.spread(),
          colors: [['#595E9E90', 0.0], ['#005E9E90', 1.0]]
        })

      // 右上：雾蓝
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [this.cx(1.0), this.cy(0.18)],
          radius: this.spread() * 0.9,
          colors: [['#477C9CC4', 0.0], ['#007C9CC4', 1.0]]
        })

      // 中部偏左：淡紫
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [this.cx(0.12), this.cy(0.55)],
          radius: this.spread() * 0.95,
          colors: [['#2EA98BC9', 0.0], ['#00A98BC9', 1.0]]
        })

      // 右下：暖沙
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [this.cx(0.85), this.cy(0.95)],
          radius: this.spread(),
          colors: [['#40D9B489', 0.0], ['#00D9B489', 1.0]]
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const nw: number = Number(newArea.width);
      const nh: number = Number(newArea.height);
      if (nw > 0 && Math.abs(nw - this.w) > 1) {
        this.w = nw;
      }
      if (nh > 0 && Math.abs(nh - this.h) > 1) {
        this.h = nh;
      }
    })
  }
}
