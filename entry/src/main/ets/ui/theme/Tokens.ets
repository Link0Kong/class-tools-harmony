/** 设计令牌（与网页/安卓共用品牌色，HarmonyOS 端按原生排版落地）。 */
export class Tokens {
  // 品牌色
  static readonly MIST_TEAL: string = '#4E9082';
  static readonly SLATE_BLUE: string = '#6E8CA8';
  static readonly WARM_SAND: string = '#B98F63';

  // 中性色
  static readonly BG: string = '#F7F8F8';
  static readonly CARD: string = '#FFFFFF';
  /** 底部工具栏浅色底（无黑影：纯浅色 + 发丝线，不叠阴影）。 */
  static readonly BAR_LIGHT: string = '#FBFCFC';
  static readonly TEXT_PRIMARY: string = '#1C2629';
  static readonly TEXT_SECONDARY: string = '#66777D';
  static readonly TEXT_TERTIARY: string = '#93A2A7';
  static readonly DIVIDER: string = '#E8EDEE';
  static readonly TINT_TEAL: string = '#E7F0ED';
  static readonly TINT_BLUE: string = '#E9EFF4';
  static readonly TINT_SAND: string = '#F5EFE7';
  static readonly DANGER: string = '#B4553F';

  // 深色 hero（中性色：深板岩，不铺大面积品牌绿；品牌绿只做小面积点缀）
  static readonly HERO_DARK: string = '#26333A';
  static readonly HERO_DARK_SOFT: string = '#33424A';
  static readonly HERO_TEXT: string = '#F3F6F6';
  static readonly HERO_SUB: string = '#B9C7CB';

  // 顶部呼吸区（所有页面内容与状态栏之间的最小留白）
  static readonly BREATH_TOP: number = 8;

  // 形状 / 间距
  static readonly RADIUS_CARD: number = 18;
  static readonly RADIUS_INPUT: number = 14;
  static readonly RADIUS_PILL: number = 999;
  static readonly GAP: number = 12;
  static readonly PAGE_PADDING: number = 20;

  // 字号
  static readonly F_TITLE: number = 26;
  static readonly F_HEADING: number = 19;
  static readonly F_BODY: number = 15;
  static readonly F_LABEL: number = 13;
  static readonly F_CAPTION: number = 12;

  // 动效
  static readonly DUR_FAST: number = 160;
  static readonly DUR_NORMAL: number = 260;

  /** `#RRGGBB` + 透明度 → ArkUI 支持的 `#AARRGGBB`。 */
  static tint(hex: string, alpha: number): string {
    const a: number = Math.round(alpha * 255);
    const aa: string = (a < 16 ? '0' : '') + a.toString(16).toUpperCase();
    if (hex.length === 7) {
      return '#' + aa + hex.substring(1);
    }
    return hex;
  }
}
