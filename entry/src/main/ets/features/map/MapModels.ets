/**
 * 校园 2.5D 地图：H5 地址与降级逻辑（纯逻辑，可单测）。
 *
 * 数据源与安卓/网页同源：正式域名 H5 `map/campus_final_25d.html`（唯一数据源，不在原生侧重写 canvas）。
 * 顶栏要求：返回 / 刷新 / 浏览器降级；主文档加载失败时给出「重试 + 浏览器打开」。
 *
 * 2026-11-23 备案通过：统一走正式 HTTPS 域名 `https://tool.furina.fun`（原 ECS 明文 IP 仅本机调试）。
 */
export class MapConfig {
  /** 正式域名（2026-11-23 备案通过，全站 HTTPS；原 ECS 明文 IP 仅本机调试）。 */
  static readonly ECS_BASE: string = 'https://tool.furina.fun';

  /** H5 相对路径。 */
  static readonly PAGE_PATH: string = '/map/campus_final_25d.html';

  /** 嵌入参数（H5 据此隐藏站内导航，交给 App 顶栏）。 */
  static readonly EMBED_QUERY: string = 'embed=1';
}

/** 地图页加载状态。 */
export enum MapLoadState {
  LOADING = 'loading',
  READY = 'ready',
  FAILED = 'failed'
}

/** 地图页纯逻辑（URL / allowlist / 状态文案），不 import ArkUI。 */
export class MapLogic {
  /** 主页面 URL：`.../campus_final_25d.html?embed=1`。 */
  static pageUrl(): string {
    return MapConfig.ECS_BASE + MapConfig.PAGE_PATH + '?' + MapConfig.EMBED_QUERY;
  }

  /** 主文档 host（用于 Web 内部导航 allowlist）；由 [ECS_BASE] 推导，避免基址与 host 两处漂移。 */
  static host(): string {
    return MapLogic.hostOf(MapConfig.ECS_BASE);
  }

  /** 仅允许正式域名主机下的页面继续在 Web 内加载；其它交给系统浏览器。 */
  static isAllowedNavigation(url: string): boolean {
    const trimmed: string = url.trim();
    if (!trimmed.toLowerCase().startsWith('http://') && !trimmed.toLowerCase().startsWith('https://')) {
      return false;
    }
    const host: string = MapLogic.hostOf(trimmed);
    return host === MapLogic.host();
  }

  /** 解析 host（小写）；非法/缺失返回空串。 */
  static hostOf(url: string): string {
    const text: string = url.trim();
    const schemeIndex: number = text.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    let rest: string = text.substring(schemeIndex + 3);
    const stop: number = MapLogic.firstIndexAny(rest, ['/', '?', '#']);
    if (stop >= 0) {
      rest = rest.substring(0, stop);
    }
    // 去 userinfo（防御：https://user:pass@host/ 不当作合法源）
    const at: number = rest.lastIndexOf('@');
    if (at >= 0) {
      rest = rest.substring(at + 1);
    }
    const colon: number = rest.indexOf(':');
    if (colon >= 0) {
      rest = rest.substring(0, colon);
    }
    return rest.toLowerCase();
  }

  /** 状态文案：加载中/已就绪/失败。 */
  static stateText(state: MapLoadState): string {
    if (state === MapLoadState.LOADING) {
      return '正在加载校园地图…';
    }
    if (state === MapLoadState.FAILED) {
      return '地图加载失败，请检查网络后重试';
    }
    return '';
  }

  /** 主文档失败时是否展示错误条（含重试 + 浏览器打开）。 */
  static showErrorBar(state: MapLoadState): boolean {
    return state === MapLoadState.FAILED;
  }

  /** 顶栏「浏览器」按钮始终可用（任意设备都可降级到系统浏览器）。 */
  static canOpenInBrowser(): boolean {
    return true;
  }

  private static firstIndexAny(text: string, chars: string[]): number {
    let best: number = -1;
    for (let i = 0; i < chars.length; i++) {
      const index: number = text.indexOf(chars[i]);
      if (index >= 0 && (best < 0 || index < best)) {
        best = index;
      }
    }
    return best;
  }
}
