/**
 * 已通过班级身份核验的会话（字段对齐网页/小程序/安卓本机身份）。
 *
 * 隐私：`sid`/`name`/`token` 只在本机使用，**不写日志、不导出、不上报**。
 */
interface SessionJson {
  sid?: string;
  name?: string;
  token?: string;
  role?: string;
  badge?: string;
  isAdmin?: boolean;
  issuedAt?: number;
  expiresAt?: number;
}

export class Session {
  sid: string = '';
  name: string = '';
  token: string = '';
  role: string = '';
  badge: string = '';
  isAdmin: boolean = false;
  /** token 签发时间（毫秒）。 */
  issuedAt: number = 0;
  /** token 过期时间（毫秒，0 = 未知）。 */
  expiresAt: number = 0;

  constructor(sid: string = '', name: string = '', token: string = '') {
    this.sid = sid;
    this.name = name;
    this.token = token;
  }

  /** UI 展示用的脱敏学号。 */
  maskedSid(): string {
    if (this.sid.length <= 4) {
      return '***';
    }
    return this.sid.substring(0, 2) + '***' + this.sid.substring(this.sid.length - 2);
  }

  /** 登录状态长期保持：只要本机有 token 就直接进入，不再做本地期限判定。 */
  isLikelyValid(now: number): boolean {
    return this.token.trim().length > 0;
  }

  toJson(): string {
    const d: SessionJson = {
      sid: this.sid,
      name: this.name,
      token: this.token,
      role: this.role,
      badge: this.badge,
      isAdmin: this.isAdmin,
      issuedAt: this.issuedAt,
      expiresAt: this.expiresAt
    };
    return JSON.stringify(d);
  }

  static fromJson(raw: string): Session | undefined {
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const d: SessionJson = JSON.parse(raw) as SessionJson;
      const s: Session = new Session(
        d.sid !== undefined ? d.sid : '',
        d.name !== undefined ? d.name : '',
        d.token !== undefined ? d.token : ''
      );
      s.role = d.role !== undefined ? d.role : '';
      s.badge = d.badge !== undefined ? d.badge : '';
      s.isAdmin = d.isAdmin === true;
      s.issuedAt = d.issuedAt !== undefined ? d.issuedAt : 0;
      s.expiresAt = d.expiresAt !== undefined ? d.expiresAt : 0;
      if (s.token.length === 0) {
        return undefined;
      }
      return s;
    } catch (e) {
      return undefined;
    }
  }
}
