import { ApiResult } from './ApiResult';

/**
 * 数据层依赖的最小网络接口（便于单测注入假实现）。
 *
 * 真实实现：`HttpClient`（PostgREST 网关封装）。
 */
export interface Api {
  get(path: string, authenticated?: boolean, readTimeoutMs?: number,
    retryOnNetworkFailure?: boolean): Promise<ApiResult>;

  post(path: string, body: string, prefer?: string, authenticated?: boolean, readTimeoutMs?: number): Promise<ApiResult>;

  patch(path: string, body: string, prefer?: string, authenticated?: boolean): Promise<ApiResult>;

  delete(path: string, authenticated?: boolean): Promise<ApiResult>;
}
