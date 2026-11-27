/**
 * 响应式断点（手机 / 折叠屏 / 平板 / 2in1）纯逻辑，可单测。
 *
 * 口径（2026-11-18 平板适配）：
 * - 导航：宽 < 900vp 用底部胶囊页签；≥ 900vp 用左侧导航栏（平板横屏/2in1）；
 * - 「全部工具」网格：宽 < 600vp → 2 列；600–899vp → 3 列；≥ 900vp → 4 列；
 * - 主内容最大宽度：手机/平板 ≤ 1080vp（平板首页二分栏），桌面再宽也居中留白；
 * - 工具页表单最大宽度：宽屏 ≤ 960vp，避免输入框/按钮横向拉满；
 * - 底部留白：悬浮页签预留页签高度和外边距；侧边导航保留屏幕边距。
 *
 * 本文件不 import ArkUI，纯函数，hypium 可直接跑。
 */
export class Breakpoints {
  /** 手机竖屏上限（含普通折叠屏外屏）。 */
  static readonly PHONE_MAX: number = 600;
  /** 平板断点：≥ 该宽度用 3 列。 */
  static readonly TABLET_MIN: number = 600;
  /** 大屏断点（折叠屏展开 / 平板横屏 / 2in1）：≥ 该宽度用 4 列并切换侧边导航。 */
  static readonly WIDE_MIN: number = 900;

  /** 手机内容最大宽度。 */
  static readonly CONTENT_MAX_PHONE: number = 880;
  /** 大屏内容最大宽度（二分栏首页 / 四列网格）。 */
  static readonly CONTENT_MAX_WIDE: number = 1080;
  /** 大屏工具页内容最大宽度（表单/列表居中，不横向拉满）。 */
  static readonly TOOL_MAX_WIDE: number = 960;

  /** 屏幕边缘间隔与底部页签占位，单位 vp。 */
  static readonly PAGE_TOP: number = 36;
  static readonly PAGE_BOTTOM: number = 28;
  static readonly WATCH_HORIZONTAL: number = 26;
  static readonly WATCH_VERTICAL: number = 20;
  static readonly FLOAT_BAR_SPACE: number = 80 + Breakpoints.PAGE_BOTTOM;

  /** 侧边导航宽度（vp）。 */
  static readonly SIDE_NAV_WIDTH: number = 104;

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

  /** 主内容最大宽度（vp）：手机 880，大屏 1080。 */
  static contentMaxWidth(width: number): number {
    return Breakpoints.isWide(width) ? Breakpoints.CONTENT_MAX_WIDE : Breakpoints.CONTENT_MAX_PHONE;
  }

  /** 华为间隔参数按设备形态定义边距。窗口宽度仍用于列数和导航断点。 */
  static pagePadding(deviceType: string, foldable: boolean = false): number {
    if (deviceType === '2in1' || deviceType === 'pc') {
      return 40;
    }
    if (deviceType === 'tablet') {
      return 32;
    }
    if (deviceType === 'wearable') {
      return Breakpoints.WATCH_HORIZONTAL;
    }
    return foldable ? 24 : 16;
  }

  /** 底部内容避让高度（vp）：宽屏只留屏幕底边距。 */
  static contentBottomSpace(width: number): number {
    return Breakpoints.isWide(width) ? Breakpoints.PAGE_BOTTOM : Breakpoints.FLOAT_BAR_SPACE;
  }

  /** 任务与课表的双栏各需约 400vp，以内容区实测宽度判定。 */
  static supportsToolPanes(width: number): boolean {
    return Breakpoints.normalize(width) >= 840;
  }

  static toolContentMaxWidth(width: number, paired: boolean = false): number {
    if (paired && Breakpoints.supportsToolPanes(width)) return 1200;
    return Breakpoints.isWide(width) ? Breakpoints.TOOL_MAX_WIDE : 100000;
  }

  /** 是否使用左侧导航（平板横屏 / 折叠屏展开 / 2in1）。 */
  static useSideNav(width: number): boolean {
    return Breakpoints.isWide(width);
  }

  /** 是否宽屏布局（平板横屏/折叠屏展开/2in1）：首页二分栏。 */
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
