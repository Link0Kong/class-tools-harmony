import { deviceInfo } from '@kit.BasicServicesKit';
import { CloudConfig } from '../../config/CloudConfig';

/**
 * 访问统计的设备 / 版本短标签（契约 `web/统计多端_详细统计_契约_20261120.md` §1 / §5）。
 *
 * 口径：
 * - 设备：`品牌 + (marketName 或 productModel) + " · " + osFullName`；
 *   品牌已在型号开头时不重复；去首尾空白、连续空白合并成一个空格；截断 48；
 *   任何异常（取不到设备信息 / 单测环境）兜底「鸿蒙设备」。
 * - 版本：去掉前缀 `v`、去空白、截断 32；空串允许（旧行显示「未记录」）。
 * - 只写短标签，**不含**姓名 / 学号 / 手机号 / 设备序列号 / 完整 UA。
 *
 * 纯函数（[deviceLabel] / [versionLabel] / [normalize] / [truncate]）不碰系统 API，便于 hypium 单测。
 */
export class VisitDevice {
  /** 设备信息取不到时的兜底标签（仍满足「设备」口径，不含个人信息）。 */
  static readonly FALLBACK: string = '鸿蒙设备';
  /** 契约定长：设备 ≤ 48 字符、版本 ≤ 32 字符。 */
  static readonly MAX_DEVICE: number = 48;
  static readonly MAX_VERSION: number = 32;

  /** 当前设备短标签（`品牌 机型 · 系统`，≤48；失败兜底「鸿蒙设备」）。 */
  static current(): string {
    try {
      const brand: string = VisitDevice.read(() => deviceInfo.brand);
      let model: string = VisitDevice.read(() => deviceInfo.marketName);
      if (model.length === 0) {
        model = VisitDevice.read(() => deviceInfo.productModel);
      }
      const os: string = VisitDevice.read(() => deviceInfo.osFullName);
      const label: string = VisitDevice.deviceLabel(brand, model, os);
      return label.length > 0 ? label : VisitDevice.FALLBACK;
    } catch (e) {
      return VisitDevice.FALLBACK;
    }
  }

  /** 应用版本短标签（`CloudConfig.APP_VERSION` 去 `v` / 去空白 / ≤32）。 */
  static appVersion(): string {
    return VisitDevice.versionLabel(CloudConfig.APP_VERSION);
  }

  /** 版本标签：去 `v`/`V` 前缀、去空白、截断 32。 */
  static versionLabel(version: string): string {
    let text: string = VisitDevice.normalize(version);
    if (text.length > 0) {
      const first: string = text.charAt(0);
      if (first === 'v' || first === 'V') {
        text = text.substring(1).trim();
      }
    }
    return VisitDevice.truncate(text, VisitDevice.MAX_VERSION);
  }

  /**
   * 纯函数：品牌 + (市场名或型号) + 「 · 」+ 系统。
   *
   * 型号已以品牌开头（忽略大小写）时不再重复品牌：
   * `('Xiaomi','Xiaomi 14','Android 15')` → `Xiaomi 14 · Android 15`；
   * `('HUAWEI','Mate 60','HarmonyOS 5.0.0')` → `HUAWEI Mate 60 · HarmonyOS 5.0.0`。
   */
  static deviceLabel(brand: string, model: string, os: string): string {
    const b: string = VisitDevice.normalize(brand);
    const m: string = VisitDevice.normalize(model);
    const o: string = VisitDevice.normalize(os);
    let head: string = m;
    if (b.length > 0 && !m.toLowerCase().startsWith(b.toLowerCase())) {
      head = m.length > 0 ? b + ' ' + m : b;
    }
    let label: string = head;
    if (o.length > 0) {
      label = label.length > 0 ? label + ' · ' + o : o;
    }
    return VisitDevice.truncate(VisitDevice.normalize(label), VisitDevice.MAX_DEVICE);
  }

  /** 去首尾空白 + 把连续空白（含制表 / 换行）合并成一个空格。 */
  static normalize(text: string): string {
    if (text.length === 0) {
      return '';
    }
    let out: string = '';
    let pendingSpace: boolean = false;
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      const isSpace: boolean = code === 32 || code === 9 || code === 10 || code === 13
        || code === 0x00A0 || code === 0x3000;
      if (isSpace) {
        pendingSpace = out.length > 0;
      } else {
        if (pendingSpace) {
          out += ' ';
          pendingSpace = false;
        }
        out += text.charAt(i);
      }
    }
    return out;
  }

  /** 按字符截断（超出直接丢弃；契约要求「截断 48 / 32」）。 */
  static truncate(text: string, max: number): string {
    if (max <= 0) {
      return '';
    }
    return text.length > max ? text.substring(0, max) : text;
  }

  /** 读取单个设备字段：非字符串 / 抛异常 / 空值一律当空串（单测环境无设备信息）。 */
  private static read(source: () => string): string {
    try {
      const value: string = source();
      if (typeof value !== 'string') {
        return '';
      }
      return VisitDevice.normalize(value);
    } catch (e) {
      return '';
    }
  }
}
