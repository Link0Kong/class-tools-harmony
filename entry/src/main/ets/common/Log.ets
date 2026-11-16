import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x1001;
const PREFIX: string = 'ClassTools';

/**
 * 统一日志封装。
 *
 * 红线：**不打印** token、学号、姓名、宿舍号等隐私字段；调用方传入的文本必须已脱敏。
 */
export class Log {
  static i(tag: string, message: string): void {
    hilog.info(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, message);
  }

  static w(tag: string, message: string): void {
    hilog.warn(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, message);
  }

  static e(tag: string, message: string): void {
    hilog.error(DOMAIN, PREFIX, '[%{public}s] %{public}s', tag, message);
  }
}
