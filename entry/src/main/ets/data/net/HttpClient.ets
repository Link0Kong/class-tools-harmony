import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudConfig } from '../../config/CloudConfig';
import { Log } from '../../common/Log';
import { Api } from './Api';
import { ApiError, ApiErrorKind, ApiResult } from './ApiResult';

const TAG: string = 'HttpClient';

export enum HttpMethod {
  GET = 'GET',
  POST = 'POST',
  PATCH = 'PATCH',
  DELETE = 'DELETE'
}

/** 一次请求的完整描述。 */
export class HttpRequestSpec {
  method: HttpMethod = HttpMethod.GET;
  path: string = '';
  body: string = '';
  prefer: string = '';
  authenticated: boolean = true;
  extraHeaders: Record<string, string> = {};
  retryOnNetworkFailure: boolean = false;
  /** >0 时覆盖全局 READ_TIMEOUT_MS（大响应/通知整表等单独放宽）。 */
  readTimeoutMs: number = 0;
}

interface PostgrestErrorBody {
  code?: string;
  message?: string;
  details?: string;
  hint?: string;
}

/**
 * CloudBase PostgREST 网关客户端（契约：android-class-tools/docs/BACKEND_CONTRACT.md §1）。
 *
 * - 头：`Authorization: Bearer <publishableKey>`、`Content-Type/Accept`、`Cache-Control: no-store`，
 *   有身份时才加 `X-Class-Token`（**绝不发空 token**）。
 * - 超时：连接/读 10s。
 * - 重试：仅 GET 的网络层失败重试 1 次（~350ms）；写请求不重试（防重复写入）。
 * - 401/403 → TokenInvalid，并回调登出（清会话回身份页）。
 */
export class HttpClient implements Api {
  private tokenProvider: () => string = () => '';
  private onTokenInvalid: () => void = () => {};

  setTokenProvider(provider: () => string): void {
    this.tokenProvider = provider;
  }

  setTokenInvalidHandler(handler: () => void): void {
    this.onTokenInvalid = handler;
  }

  async get(path: string, authenticated: boolean = true, readTimeoutMs: number = 0,
    retryOnNetworkFailure: boolean = true): Promise<ApiResult> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = HttpMethod.GET;
    spec.path = path;
    spec.authenticated = authenticated;
    spec.retryOnNetworkFailure = retryOnNetworkFailure;
    spec.readTimeoutMs = readTimeoutMs;
    return await this.request(spec);
  }

  async post(path: string, body: string, prefer: string = '', authenticated: boolean = true,
    readTimeoutMs: number = 0): Promise<ApiResult> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = HttpMethod.POST;
    spec.path = path;
    spec.body = body;
    spec.prefer = prefer;
    spec.authenticated = authenticated;
    spec.readTimeoutMs = readTimeoutMs;
    return await this.request(spec);
  }

  async patch(path: string, body: string, prefer: string = '', authenticated: boolean = true): Promise<ApiResult> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = HttpMethod.PATCH;
    spec.path = path;
    spec.body = body;
    spec.prefer = prefer;
    spec.authenticated = authenticated;
    return await this.request(spec);
  }

  async delete(path: string, authenticated: boolean = true): Promise<ApiResult> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = HttpMethod.DELETE;
    spec.path = path;
    spec.authenticated = authenticated;
    spec.prefer = 'return=minimal';
    return await this.request(spec);
  }

  async request(spec: HttpRequestSpec): Promise<ApiResult> {
    const first: ApiResult = await this.execute(spec);
    if (!first.ok && spec.retryOnNetworkFailure && first.error !== undefined
      && first.error.kind === ApiErrorKind.Network) {
      Log.w(TAG, 'GET 网络失败，350ms 后重试一次');
      await delay(CloudConfig.GET_RETRY_DELAY_MS);
      return await this.execute(spec);
    }
    return first;
  }

  private buildHeaders(spec: HttpRequestSpec): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Authorization'] = 'Bearer ' + CloudConfig.PUBLISHABLE_KEY;
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    headers['Cache-Control'] = 'no-store';
    if (spec.authenticated) {
      const token: string = this.tokenProvider();
      if (token.length > 0) {
        headers['X-Class-Token'] = token;
      }
    }
    if (spec.prefer.length > 0) {
      headers['Prefer'] = spec.prefer;
    }
    const extra: Record<string, string> = spec.extraHeaders;
    const keys: string[] = Object.keys(extra);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      headers[k] = extra[k];
    }
    return headers;
  }

  private async execute(spec: HttpRequestSpec): Promise<ApiResult> {
    if (!CloudConfig.isConfigured()) {
      return ApiResult.failure(new ApiError(ApiErrorKind.Config, 0, 'not_configured', '云端配置缺失'));
    }
    const headers = this.buildHeaders(spec);
    const requestToken = headers['X-Class-Token'];
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: toNetMethod(spec.method),
      header: headers,
      connectTimeout: CloudConfig.CONNECT_TIMEOUT_MS,
      readTimeout: spec.readTimeoutMs > 0 ? spec.readTimeoutMs : CloudConfig.READ_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false
    };
    if (spec.body.length > 0) {
      options.extraData = spec.body;
    }
    const url: string = CloudConfig.url(spec.path);
    try {
      const response: http.HttpResponse = await request.request(url, options);
      const status: number = response.responseCode;
      const text: string = bodyToText(response.result);
      if (status >= 200 && status < 300) {
        return ApiResult.success(text);
      }
      if (status === 401 || status === 403) {
        const err: ApiError = new ApiError(ApiErrorKind.TokenInvalid, status, 'unauthorized', '身份已失效');
        // A missing push entitlement or token binding must not invalidate the user's class session.
        const pushDenied = spec.path === 'push_tokens' || spec.path.startsWith('push_tokens?');
        if (!pushDenied && spec.authenticated && requestToken && this.tokenProvider() === requestToken) {
          this.onTokenInvalid();
        }
        return ApiResult.failure(err);
      }
      return ApiResult.failure(parseHttpError(status, text));
    } catch (e) {
      const be: BusinessError = e as BusinessError;
      Log.w(TAG, '请求失败 code=' + be.code + ' msg=' + be.message);
      return ApiResult.failure(new ApiError(ApiErrorKind.Network, 0, 'network', '网络连接失败，请检查网络后重试'));
    } finally {
      request.destroy();
    }
  }
}

function toNetMethod(method: HttpMethod): http.RequestMethod {
  if (method === HttpMethod.POST) {
    return http.RequestMethod.POST;
  }
  if (method === HttpMethod.PATCH) {
    return http.RequestMethod.PATCH;
  }
  if (method === HttpMethod.DELETE) {
    return http.RequestMethod.DELETE;
  }
  return http.RequestMethod.GET;
}

function bodyToText(result: string | Object | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  if (result instanceof ArrayBuffer) {
    return '';
  }
  return JSON.stringify(result);
}

function parseHttpError(status: number, text: string): ApiError {
  let message: string = '';
  let code: string = '';
  if (text.length > 0) {
    try {
      const parsed: PostgrestErrorBody = JSON.parse(text) as PostgrestErrorBody;
      message = parsed.message !== undefined ? parsed.message : '';
      code = parsed.code !== undefined ? parsed.code : '';
    } catch (e) {
      message = '';
    }
  }
  return new ApiError(ApiErrorKind.Http, status, code, message);
}

export function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}
