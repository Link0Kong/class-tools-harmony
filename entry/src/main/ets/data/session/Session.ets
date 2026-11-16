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

  /** 与网页一致的 29 天本地判定：未过期且签发不满 29 天可直接进主界面。 */
  isLikelyValid(now: number): boolean {
    if (this.expiresAt > 0 && now > this.expiresAt) {
      return false;
    }
    if (this.issuedAt <= 0) {
      return true;
    }
    return now - this.issuedAt < 29 * 24 * 60 * 60 * 1000;
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
