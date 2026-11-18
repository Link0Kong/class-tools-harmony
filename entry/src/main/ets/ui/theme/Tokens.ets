/** 设计令牌（与网页/安卓共用品牌色，HarmonyOS 端按原生排版落地）。 */
export class Tokens {
  // 品牌色
  static readonly MIST_TEAL: string = '#4E9082';
  static readonly SLATE_BLUE: string = '#6E8CA8';
  static readonly WARM_SAND: string = '#B98F63';

  // 中性色
  static readonly BG: string = '#F7F8F8';
  /** 内容卡片：半透明白，让页面环境光透入（沉浸光感玻璃面）。 */
  static readonly CARD: string = '#CCFFFFFF';
  static readonly CARD_STRONG: string = '#E6FFFFFF';
  static readonly CARD_SOFT: string = '#B8FFFFFF';
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

  // 沉浸光感：环境光底色与玻璃表面
  static readonly BG_TOP: string = '#EAF4F1';
  static readonly BG_MID: string = '#F1F3F7';
  static readonly BG_BOTTOM: string = '#F7EFE6';
  static readonly GLOW_TEAL: string = '#5E9E90';
  static readonly GLOW_BLUE: string = '#7C9CC4';
  static readonly GLOW_SAND: string = '#D9B489';
  /** 悬浮玻璃表面（半透明白，需配合 backgroundBlurStyle 使用）。 */
  static readonly GLASS: string = '#B8FFFFFF';
  static readonly GLASS_STRONG: string = '#D9FFFFFF';
  static readonly GLASS_STROKE: string = '#4DFFFFFF';
  static readonly GLASS_STROKE_DARK: string = '#14000000';
  /** 内容区控件底：半透明，让环境光透入（按钮 / 输入框 / 选项）。 */
  static readonly CONTROL: string = '#A6FFFFFF';
  static readonly CONTROL_SOFT: string = '#80FFFFFF';
  /** 底部悬浮操作条：比卡片更亮、更薄，配合模糊形成 Z 轴分层。 */
  static readonly ACTION_BAR: string = '#D9FFFFFF';
  /** 弹层（自定义面板）玻璃底：厚材质，保证文字可读。 */
  static readonly SHEET: string = '#F2FAFBFC';
  static readonly SCRIM: string = '#5C0B1418';
  /** 卡片发丝高光边：上亮下暗，模拟材质边缘反光。 */
  static readonly CARD_EDGE: string = '#59FFFFFF';
  static readonly CARD_SHADOW: string = '#141C2629';

  // 顶部呼吸区（所有页面内容与状态栏之间的最小留白）
  static readonly BREATH_TOP: number = 8;
  /** 悬浮导航栏占位高度（内容底部需避让）。 */
  static readonly FLOAT_BAR_SPACE: number = 160;

  // 形状
  static readonly RADIUS_CARD: number = 18;
  static readonly RADIUS_FLOAT: number = 24;
  static readonly RADIUS_INPUT: number = 14;
  static readonly RADIUS_PILL: number = 999;

  // 间隔：遵循 HarmonyOS「间隔参数」规范的 4vp/8vp 栅格体系
  // （对应系统 Padding_level0–level36，只使用规范内数值，避免随意间距）。
  static readonly SPACE_0: number = 0;
  static readonly SPACE_2: number = 2;
  static readonly SPACE_4: number = 4;
  static readonly SPACE_6: number = 6;
  static readonly SPACE_8: number = 8;
  static readonly SPACE_10: number = 10;
  static readonly SPACE_12: number = 12;
  static readonly SPACE_14: number = 14;
  static readonly SPACE_16: number = 16;
  static readonly SPACE_18: number = 18;
  static readonly SPACE_20: number = 20;
  static readonly SPACE_24: number = 24;
  static readonly SPACE_26: number = 26;
  static readonly SPACE_32: number = 32;
  static readonly SPACE_40: number = 40;
  static readonly SPACE_48: number = 48;

  /** 屏幕边缘间隔（手机 16vp；折叠屏 24vp；平板/2in1 32vp，见 Breakpoints.pagePadding）。 */
  static readonly PAGE_PADDING: number = 16;
  /** 卡片之间的间隔：12vp。 */
  static readonly GAP: number = 12;
  /** 卡片/容器内边距：14vp。 */
  static readonly CARD_PADDING: number = 14;
  /** 无明显边界控件之间的普通间隔：8vp（上下 / 左右通用）。 */
  static readonly GAP_SM: number = 8;
  /** 有明显边界控件之间的较大间隔：16vp。 */
  static readonly GAP_LG: number = 16;
  /** 模块 / 分组之间的间隔：24vp。 */
  static readonly GAP_XL: number = 24;
  /** 主次文本上下间隔：2vp。 */
  static readonly TEXT_GAP: number = 2;
  /** 主次文本左右间隔：8vp。 */
  static readonly TEXT_GAP_H: number = 8;

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
