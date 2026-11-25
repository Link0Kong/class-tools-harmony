import notificationManager from '@ohos.notificationManager';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { Log } from '../../common/Log';

export const APP_BUNDLE: string = 'com.furina.classtools';

export class NotificationDelivery {
  static id(key: string): number {
    let hash: number = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) | 0;
    }
    return Math.abs(hash) % 2000000000 + 1;
  }

  static route(toolId: string, homeworkId: string = '', taskId: string = '', noticeId: string = ''): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['toolId'] = toolId;
    if (homeworkId) out['homeworkId'] = homeworkId;
    if (taskId) out['taskId'] = taskId;
    if (noticeId) out['noticeId'] = noticeId;
    return out;
  }

  static async action(id: number, parameters: Record<string, Object>): Promise<WantAgent | undefined> {
    return await wantAgent.getWantAgent({
      wants: [{ bundleName: APP_BUNDLE, abilityName: 'EntryAbility', parameters: parameters }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: id,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  static async publish(id: number, title: string, message: string, parameters: Record<string, Object>,
    until: number = 0): Promise<boolean> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        isAlertOnce: true,
        wantAgent: await NotificationDelivery.action(id, parameters),
        autoDeletedTime: until,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: message }
        }
      };
      await notificationManager.publish(request);
      return true;
    } catch (error) {
      Log.w('NotificationDelivery', '发布系统通知失败');
      return false;
    }
  }
}

