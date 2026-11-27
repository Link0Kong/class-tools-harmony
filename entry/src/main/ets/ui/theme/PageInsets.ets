import { display } from '@kit.ArkUI';
import { Device } from '../../common/Device';
import { Breakpoints } from './Breakpoints';

/** 内容页和标题栏共用设备边距，避免用工具内容区宽度推断设备。 */
export class PageInsets {
  static readonly HORIZONTAL: number = PageInsets.horizontal();

  private static horizontal(): number {
    const type: string = Device.type();
    if (type === 'phone' || type === 'default') {
      try {
        return Breakpoints.pagePadding(type, display.isFoldable());
      } catch (_) {
        // 不提供折叠状态 API 的设备沿用手机边距。
      }
    }
    return Breakpoints.pagePadding(type);
  }
}
