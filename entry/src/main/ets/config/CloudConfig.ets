/**
 * 云端配置（与网页/小程序/安卓共用同一套 CloudBase 契约）。
 *
 * - 后端只有一种形态：CloudBase PostgreSQL + PostgREST 风格 REST 网关。
 * - `PUBLISHABLE_KEY` 是 role=anon 的**公开** key（设计上可进客户端，与网页 `var CB` / 小程序 cloud-config 同值），
 *   不是服务端高权限 key；任何高权限 key 都不允许出现在客户端。
 * - 认证分两层：Bearer + 班级 token（`X-Class-Token`）。
 */
export class CloudConfig {
  /** REST 根（结尾必须带 `/`）。 */
  static readonly REST_BASE: string = 'https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/';

  /** 公开 Publishable Key（role=anon）。构建时由本机脚本从 android-class-tools/gradle.properties 注入。 */
  static readonly PUBLISHABLE_KEY: string = 'eyJhbGciOiJSUzI1NiIsImtpZCI6IjkwMTNkMzBkLWY3NTEtNGE4Yi05OGNlLTlmNTFiMzk3ZDdjNyJ9.eyJpc3MiOiJodHRwczovL3Rvb2wtZDRnb3N1ZG9rNDZlMGUwODEuYXAtc2hhbmdoYWkudGNiLWFwaS50ZW5jZW50Y2xvdWRhcGkuY29tIiwic3ViIjoiYW5vbiIsImF1ZCI6InRvb2wtZDRnb3N1ZG9rNDZlMGUwODEiLCJleHAiOjQwOTUyNzY4ODAsImlhdCI6MTc5MTU5MzY4MCwibm9uY2UiOiItdGJncVVhcVNZS25jNUx0VmZ2QWZRIiwiYXRfaGFzaCI6Ii10YmdxVWFxU1lLbmM1THRWZnZBZlEiLCJuYW1lIjoiQW5vbnltb3VzIiwic2NvcGUiOiJhbm9ueW1vdXMiLCJwcm9qZWN0X2lkIjoidG9vbC1kNGdvc3Vkb2s0NmUwZTA4MSIsIm1ldGEiOnsicGxhdGZvcm0iOiJQdWJsaXNoYWJsZUtleSJ9LCJyb2xlIjoiYW5vbiIsImlzX2Fub255bW91cyI6dHJ1ZSwiYXBwX21ldGFkYXRhIjp7InByb3ZpZGVyIjoiYW5vbnltb3VzIiwicHJvdmlkZXJzIjpbImFub255bW91cyJdfSwidXNlcl9tZXRhZGF0YSI6eyJuYW1lIjoiQW5vbnltb3VzIn0sInVzZXJfdHlwZSI6IiIsImNsaWVudF90eXBlIjoiY2xpZW50X3VzZXIiLCJpc19zeXN0ZW1fYWRtaW4iOmZhbHNlfQ.Iyf827jPzSxTtY6l9tjeRSWG0DVkU8a-sqOcg43b0sP-4CuykUQ_2DpIm3vQSd6t9gDjQRsODpuQzZt4X2iabRr7eahQnB5UFjNuHWBJYtg9O1IZSdx1qfiyQ9NHLHLMOGQKw95E5qhqEs-tQXu-FbASsAl4Y-O_ssL3_OrwFP6qUWfLRb53D0X5gqkumEaKvf-hHhSlyFCzOImKdTKnoI-Qr_N-xa3_WE1AWjGXC_5lo8BhsxZFrGXrkp90eB1kT4303lPA_bzuzP1RXHdrNRmJRbobZmOUUa3k8SoqoeSrizQxCSaL-1oyhZZBFn_zBMpN7wGw0H2uC8I-NTE5Vg';

  static readonly CONNECT_TIMEOUT_MS: number = 10000;
  static readonly READ_TIMEOUT_MS: number = 10000;
  static readonly GET_RETRY_DELAY_MS: number = 350;

  /** 与网页/小程序一致的应用版本号（HarmonyOS 端独立版本线，M0 = 1.0.0）。 */
  static readonly APP_VERSION: string = '1.0.7';

  static isConfigured(): boolean {
    // 只做长度/前缀校验：不要把 key 字面量和自身比较（占位符替换脚本会把比较里的占位符一起替换掉）
    const key: string = CloudConfig.PUBLISHABLE_KEY;
    return key.length > 100 && key.startsWith('eyJ');
  }

  /** 拼接 REST 地址；`path` 可自带 query。 */
  static url(path: string): string {
    const base: string = CloudConfig.REST_BASE.endsWith('/')
      ? CloudConfig.REST_BASE
      : CloudConfig.REST_BASE + '/';
    const p: string = path.startsWith('/') ? path.substring(1) : path;
    return base + p;
  }
}
