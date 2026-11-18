import { deviceInfo } from '@kit.BasicServicesKit';

/** 设备形态判断（手表端走独立 UI）。 */
export class Device {
  static type(): string {
    try {
      return String(deviceInfo.deviceType);
    } catch (e) {
      return 'phone';
    }
  }

  static isWearable(): boolean {
    return Device.type() === 'wearable';
  }
}
