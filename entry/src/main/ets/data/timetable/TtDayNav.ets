/**
 * 课表左右滑动的松手判定（可单测）。
 *
 * 周视图切周与日视图切天共用同一阈值 `min(64, 宽度 × 0.18)`，
 * 保证两处手感一致；容器宽度未测量时按 300vp 兜底（与周表原实现一致）。
 */
export class TtSwipe {
  /** 松手翻页的最小位移上限（vp）。 */
  static readonly MIN_THRESHOLD: number = 64;
  /** 阈值随容器宽度缩放的比例。 */
  static readonly RATIO: number = 0.18;
  /** 尚未测量宽度时的兜底值。 */
  static readonly FALLBACK_WIDTH: number = 300;

  /** 容器宽度；未测量（<= 0）时按 300vp 兜底。 */
  static widthOf(width: number): number {
    return width > 0 ? width : TtSwipe.FALLBACK_WIDTH;
  }

  /** 松手翻页阈值：min(64, 宽 × 0.18)。 */
  static threshold(width: number): number {
    return Math.min(TtSwipe.MIN_THRESHOLD, TtSwipe.widthOf(width) * TtSwipe.RATIO);
  }

  /** 松手位移 → 翻页方向：左滑 1（下一周/下一天）、右滑 -1、未过阈值 0（只回弹）。 */
  static delta(offsetX: number, width: number): number {
    const threshold: number = TtSwipe.threshold(width);
    if (offsetX < -threshold) {
      return 1;
    }
    if (offsetX > threshold) {
      return -1;
    }
    return 0;
  }
}

/**
 * 日视图（本周 0..6）相邻天导航纯逻辑。
 *
 * 只在本周内左右移动一天，越界返回 undefined：调用方只做回弹，
 * 不改天、也不顺带换周（跨周仍由周导航按钮完成）。
 */
export class TtDayNav {
  /** 一周 7 天（0 = 周一）。 */
  static readonly COUNT: number = 7;

  /** 目标天：current 与 current + delta 都落在 0..6 内才返回，否则 undefined。 */
  static next(current: number, delta: number): number | undefined {
    if (!Number.isInteger(current) || current < 0 || current >= TtDayNav.COUNT) {
      return undefined;
    }
    if (!Number.isInteger(delta)) {
      return undefined;
    }
    const target: number = current + delta;
    if (target < 0 || target >= TtDayNav.COUNT) {
      return undefined;
    }
    return target;
  }

  /** 松手位移 → 相邻天：未过阈值或越界都返回 undefined。 */
  static target(current: number, offsetX: number, width: number): number | undefined {
    const delta: number = TtSwipe.delta(offsetX, width);
    return delta === 0 ? undefined : TtDayNav.next(current, delta);
  }
}
