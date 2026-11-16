/**
 * 响应式断点（手机 / 折叠屏 / 平板 / 2in1）纯逻辑，可单测。
 *
 * 口径（2026-11-15 视觉与平板适配要求）：
 * - 「全部工具」网格：宽 < 600vp → 2 列；600–899vp → 3 列；≥ 900vp → 4 列；
 * - 主内容最大宽度：手机/平板 ≤ 880vp，桌面/折叠屏展开 ≤ 960vp（居中留白，不横向拉满）；
 * - 顶部呼吸区：所有形态至少 [BREATH_TOP]，大屏再多一点，避免内容贴状态栏。
 *
 * 本文件不 import ArkUI，纯函数，hypium 可直接跑。
 */
export class Breakpoints {
  /** 手机竖屏上限（含普通折叠屏外屏）。 */
  static readonly PHONE_MAX: number = 600;
  /** 平板断点：≥ 该宽度用 3 列。 */
  static readonly TABLET_MIN: number = 600;
  /** 大屏断点（折叠屏展开 / 平板横屏 / 2in1）：≥ 该宽度用 4 列。 */
  static readonly WIDE_MIN: number = 900;

  /** 手机内容最大宽度。 */
  static readonly CONTENT_MAX_PHONE: number = 880;
  /** 大屏内容最大宽度。 */
  static readonly CONTENT_MAX_WIDE: number = 960;

  /** 顶部呼吸区（vp）：手机 8，宽屏 12。 */
  static readonly BREATH_TOP: number = 8;
  static readonly BREATH_TOP_WIDE: number = 12;

  /** 一列/两列/三列/四列断点判定。 */
  static isWide(width: number): boolean {
    return Breakpoints.normalize(width) >= Breakpoints.WIDE_MIN;
  }

  static isTablet(width: number): boolean {
    const w: number = Breakpoints.normalize(width);
    return w >= Breakpoints.TABLET_MIN && w < Breakpoints.WIDE_MIN;
  }

  /**
   * 「全部工具」网格列数：2 → 3 → 4。
   *
   * 非法/未知宽度（≤0）按手机 2 列处理，避免首帧 onAreaChange 前布局跳变。
   */
  static gridColumns(width: number): number {
    const w: number = Breakpoints.normalize(width);
    if (w >= Breakpoints.WIDE_MIN) {
      return 4;
    }
    if (w >= Breakpoints.TABLET_MIN) {
      return 3;
    }
    return 2;
  }

  /**
   * 网格项宽度百分比（给 `Flex` 的百分比宽度用）：
   * 2 列 → 48.5%（留 3% 间距），3 列 → 31.5%，4 列 → 23.5%。
   */
  static gridItemWidthPercent(width: number): string {
    const columns: number = Breakpoints.gridColumns(width);
    if (columns === 4) {
      return '23.5%';
    }
    if (columns === 3) {
      return '31.5%';
    }
    return '48.5%';
  }

  /** 主内容最大宽度（vp）：手机/平板 880，大屏 960。 */
  static contentMaxWidth(width: number): number {
    return Breakpoints.isWide(width) ? Breakpoints.CONTENT_MAX_WIDE : Breakpoints.CONTENT_MAX_PHONE;
  }

  /** 顶部呼吸区高度（vp）。 */
  static breathTop(width: number): number {
    return Breakpoints.isWide(width) ? Breakpoints.BREATH_TOP_WIDE : Breakpoints.BREATH_TOP;
  }

  /** 是否宽屏布局（平板横屏/折叠屏展开/2in1）：工具页可左右分栏。 */
  static useTwoPane(width: number): boolean {
    return Breakpoints.normalize(width) >= Breakpoints.WIDE_MIN;
  }

  private static normalize(width: number): number {
    if (typeof width !== 'number' || isNaN(width) || width <= 0) {
      return 0;
    }
    return width;
  }
}
