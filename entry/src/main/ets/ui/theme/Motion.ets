import curves from '@ohos.curves';

/**
 * 全局动效令牌（与网页/安卓同一套节奏）：
 * - 快 160ms（按压/勾选）、常规 260ms（弹层/切换）、慢 380ms（页面转场）；
 * - 使用 `getUIContext().animateTo` 驱动状态变化，配合 TransitionEffect 做进出场。
 */
export class Motion {
  static readonly FAST: number = 160;
  static readonly NORMAL: number = 260;
  static readonly SLOW: number = 380;

  /** 标准缓动（对应网页 cubic-bezier(.4,0,.2,1) 近似）。 */
  static ease(): ICurve {
    return curves.cubicBezierCurve(0.4, 0, 0.2, 1);
  }

  /** 弹性缓动（tab 指示条、卡片回弹）。 */
  static spring(): ICurve {
    return curves.springCurve(0.72, 1, 220, 26);
  }

  /** 轻回弹（弹层）。 */
  static softSpring(): ICurve {
    return curves.springCurve(0.5, 1, 200, 28);
  }

  /** 页面进入：从右侧轻微滑入 + 淡入。 */
  static pageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: 28 }))
      .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }));
  }

  /** 页面退出：向右滑出 + 淡出。 */
  static pageExit(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: 24 }))
      .combine(TransitionEffect.scale({ x: 0.99, y: 0.99 }));
  }

  /** 底部弹层进入：自下而上滑入 + 淡入。 */
  static sheetEnter(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 72 }));
  }

  /** 底部弹层退出。 */
  static sheetExit(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 48 }));
  }

  /** 遮罩淡入淡出。 */
  static scrim(): TransitionEffect {
    return TransitionEffect.OPACITY;
  }

  /** 列表项进入：淡入 + 上移 10vp。 */
  static listItem(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 10 }));
  }

  /** 横向卡片/徽标出现。 */
  static popIn(): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }));
  }
}
