import { HttpClient } from '../net/HttpClient';
import { ApiError, ApiErrorKind, ApiResult } from '../net/ApiResult';
import { Session } from '../session/Session';

const VERIFY_PATH: string = 'rpc/class_verify';
const SESSION_TTL_MS: number = 30 * 24 * 60 * 60 * 1000;
const STUDENT_ID_REGEX: RegExp = new RegExp('^\\d{10}$');

interface VerifyJson {
  ok?: boolean;
  token?: string;
  sid?: string;
  name?: string;
  role?: string;
  badge?: string;
  is_admin?: boolean;
  reason?: string;
}

interface VerifyRequest {
  p_sid: string;
  p_name: string;
}

/** 身份核验结果。 */
export class VerifyResult {
  ok: boolean;
  session: Session | undefined;
  code: string;
  message: string;

  constructor(ok: boolean, session: Session | undefined, code: string, message: string) {
    this.ok = ok;
    this.session = session;
    this.code = code;
    this.message = message;
  }

  static success(session: Session): VerifyResult {
    return new VerifyResult(true, session, 'ok', '');
  }

  static failure(code: string, message: string): VerifyResult {
    return new VerifyResult(false, undefined, code, message);
  }
}

/**
 * 真实身份仓库：`POST rpc/class_verify`（唯一免班级 token 的接口）。
 *
 * 契约：请求 `{p_sid, p_name}`；响应兼容「对象」与「单元素数组」，成功必须带 `token`。
 * 成功后本地会话 `issuedAt=now`、`expiresAt=now+30d`（服务端 token 30 天）。
 */
export class AuthRepository {
  private api: HttpClient;
  private now: () => number;

  constructor(api: HttpClient, now: () => number = () => Date.now()) {
    this.api = api;
    this.now = now;
  }

  async verify(studentId: string, name: string): Promise<VerifyResult> {
    const sid: string = studentId.trim();
    const nm: string = name.trim();
    if (!STUDENT_ID_REGEX.test(sid)) {
      return VerifyResult.failure('invalid_input', '请输入 10 位学号');
    }
    if (nm.length === 0) {
      return VerifyResult.failure('invalid_input', '请输入姓名');
    }
    const body: VerifyRequest = { p_sid: sid, p_name: nm };
    let result: ApiResult = await this.api.post(VERIFY_PATH, JSON.stringify(body), '', false);
    // 云端 PostgREST schema cache 偶发未刷新时重试一次（线上曾出现 "Could not find the function ... in the schema cache"）。
    if (!result.ok && result.error !== undefined && this.isSchemaCacheError(result.error.message)) {
      await AuthRepository.delay(800);
      result = await this.api.post(VERIFY_PATH, JSON.stringify(body), '', false);
    }
    if (!result.ok) {
      return this.mapError(result.error, result.error !== undefined ? result.error.displayMessage() : '请求失败');
    }
    return this.parse(result.value, sid, nm);
  }

  private isSchemaCacheError(message: string): boolean {
    const text: string = message.toLowerCase();
    return text.indexOf('schema cache') >= 0 || text.indexOf('could not find the function') >= 0
      || text.indexOf('pgrst202') >= 0;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private parse(raw: string, fallbackSid: string, fallbackName: string): VerifyResult {
    let body: VerifyJson | undefined = undefined;
    try {
      const parsed: Object = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[];
        if (arr.length > 0) {
          body = arr[0] as VerifyJson;
        }
      } else {
        body = parsed as VerifyJson;
      }
    } catch (e) {
      return VerifyResult.failure('parse_error', '身份服务返回了无法解析的内容');
    }
    if (body === undefined) {
      return VerifyResult.failure('parse_error', '身份服务返回结构异常');
    }
    const token: string = body.token !== undefined ? body.token : '';
    const reason: string = body.reason !== undefined ? body.reason : '';
    if (body.ok === false) {
      return VerifyResult.failure('invalid_credentials', reason.length > 0 ? reason : '姓名或学号不在班级名单中');
    }
    if (token.length === 0) {
      return VerifyResult.failure('token_missing', reason.length > 0 ? reason : '云端未返回身份凭证，请稍后重试');
    }
    const nowMs: number = this.now();
    const s: Session = new Session(
      body.sid !== undefined && body.sid.trim().length > 0 ? body.sid.trim() : fallbackSid,
      body.name !== undefined && body.name.trim().length > 0 ? body.name.trim() : fallbackName,
      token
    );
    s.role = body.role !== undefined ? body.role : '';
    s.badge = body.badge !== undefined ? body.badge : '';
    s.isAdmin = body.is_admin === true;
    s.issuedAt = nowMs;
    s.expiresAt = nowMs + SESSION_TTL_MS;
    return VerifyResult.success(s);
  }

  private mapError(error: ApiError | undefined, fallback: string): VerifyResult {
    if (error === undefined) {
      return VerifyResult.failure('unknown', '请求失败');
    }
    if (error.kind === ApiErrorKind.TokenInvalid) {
      return VerifyResult.failure('invalid_credentials', '姓名或学号不在班级名单中');
    }
    if (error.kind === ApiErrorKind.Http) {
      if (this.isSchemaCacheError(error.message)) {
        return VerifyResult.failure('server_error', '登录服务正在更新，请稍后重试');
      }
      if (error.status >= 400 && error.status < 500) {
        return VerifyResult.failure('invalid_credentials',
          error.message.length > 0 ? error.message : '姓名或学号不在班级名单中');
      }
      return VerifyResult.failure('server_error', fallback);
    }
    if (error.kind === ApiErrorKind.Network) {
      return VerifyResult.failure('network', '网络连接失败，请检查网络后重试');
    }
    if (error.kind === ApiErrorKind.Config) {
      return VerifyResult.failure('not_configured', '云端配置缺失');
    }
    return VerifyResult.failure('parse_error', fallback);
  }
}
