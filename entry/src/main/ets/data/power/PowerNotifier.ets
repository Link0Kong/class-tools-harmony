import notificationManager from '@ohos.notificationManager';
import { Log } from '../../common/Log';

const TAG: string = 'PowerNotifier';

/** 低电提醒（本机会话内去重；不写云端）。 */
export class PowerNotifier {
  private static lastNotifiedAt: number = 0;
  private static lastNotifiedQ: number = -1;

  /** 低电时发一条本地通知（同一电量值 6 小时内不重复）。 */
  static async notifyIfLow(roomLabel: string, q: number, low: number): Promise<boolean> {
    const now: number = Date.now();
    if (q >= low) {
      return false;
    }
    if (Math.abs(q - PowerNotifier.lastNotifiedQ) < 0.01
      && now - PowerNotifier.lastNotifiedAt < 6 * 60 * 60 * 1000) {
      return false;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: 20261115,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '电费不足提醒',
            text: roomLabel + ' 剩余 ' + q.toFixed(2) + ' 度（阈值 ' + low + ' 度）',
            additionalText: '班级工具站'
          }
        }
      };
      await notificationManager.publish(request);
      PowerNotifier.lastNotifiedQ = q;
      PowerNotifier.lastNotifiedAt = now;
      return true;
    } catch (e) {
      Log.w(TAG, '低电通知发送失败');
      return false;
    }
  }
}
