import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { common } from '@kit.AbilityKit';
import { AppGlobal } from '../../app/AppGlobal';
import { ReminderPlan } from '../../features/reminder/ReminderModels';

export class ReminderPublishResult {
  ok: boolean = false;
  reminderId: number = -1;
  message: string = '';
}

/**
 * 系统提醒（reminderAgentManager）+ 通知兜底。
 *
 * - 首选：发布系统日历提醒（需 `ohos.permission.PUBLISH_AGENT_REMINDER`，失败则降级）；
 * - 兜底：`notificationManager.publish` 立即通知，告知用户需手动留意（避免静默失败）。
 */
export class ReminderAgent {
  static async publish(plan: ReminderPlan): Promise<ReminderPublishResult> {
    const result: ReminderPublishResult = new ReminderPublishResult();
    const context = AppGlobal.context;
    if (context === undefined) {
      result.message = '应用上下文缺失';
      return result;
    }
    try {
      const date: Date = new Date(plan.triggerAt);
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: date.getFullYear(),
          month: date.getMonth() + 1,
          day: date.getDate(),
          hour: date.getHours(),
          minute: date.getMinutes(),
          second: 0
        },
        title: plan.title,
        content: plan.content,
        expiredContent: plan.content,
        ringDuration: 3,
        snoozeTimes: 0,
        wantAgent: {
          pkgName: 'com.furina.classtools',
          abilityName: 'EntryAbility'
        }
      };
      const id: number = await reminderAgentManager.publishReminder(request);
      result.ok = id >= 0;
      result.reminderId = id;
      if (!result.ok) {
        result.message = '系统未接受提醒';
      }
      return result;
    } catch (e) {
      result.message = '系统提醒不可用，已改为立即通知';
      await ReminderAgent.notifyNow(plan, context);
      return result;
    }
  }

  static async cancel(reminderId: number): Promise<boolean> {
    if (reminderId < 0) {
      return true;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
      return true;
    } catch (e) {
      return false;
    }
  }

  private static async notifyNow(plan: ReminderPlan, context: common.UIAbilityContext): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: Math.floor(plan.triggerAt % 100000),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: plan.title,
            text: plan.content,
            additionalText: '班级工具站'
          }
        }
      };
      await notificationManager.publish(request);
    } catch (e) {
      // 通知权限缺失时不阻塞业务流程
    }
  }
}
