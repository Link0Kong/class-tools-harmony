/** 请求失败的分类，UI 据此给不同文案/行为。 */
export enum ApiErrorKind {
  Network = 'network',
  Http = 'http',
  TokenInvalid = 'token_invalid',
  Parse = 'parse',
  Config = 'config'
}

/** 统一的错误载体（不携带任何隐私字段）。 */
export class ApiError {
  kind: ApiErrorKind;
  status: number;
  code: string;
  message: string;

  constructor(kind: ApiErrorKind, status: number, code: string, message: string) {
    this.kind = kind;
    this.status = status;
    this.code = code;
    this.message = message;
  }

  /** 可直接展示给用户的中文文案。 */
  displayMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    if (this.kind === ApiErrorKind.Network) {
      return '网络连接失败，请检查网络后重试';
    }
    if (this.kind === ApiErrorKind.TokenInvalid) {
      return '身份已失效，请重新输入学号与姓名';
    }
    if (this.kind === ApiErrorKind.Config) {
      return '云端配置缺失';
    }
    return '请求失败（' + this.status + '）';
  }
}

/** 值语义的请求结果：成功带原始响应文本，失败带 ApiError。 */
export class ApiResult {
  ok: boolean;
  value: string;
  error: ApiError | undefined;

  constructor(ok: boolean, value: string, error: ApiError | undefined) {
    this.ok = ok;
    this.value = value;
    this.error = error;
  }

  static success(value: string): ApiResult {
    return new ApiResult(true, value, undefined);
  }

  static failure(error: ApiError): ApiResult {
    return new ApiResult(false, '', error);
  }
}
