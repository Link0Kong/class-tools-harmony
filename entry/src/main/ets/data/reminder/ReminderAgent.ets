import { calendarManager } from '@kit.CalendarKit';
import reminderAgentManager from '@ohos.reminderAgentManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { APP_BUNDLE, NotificationDelivery } from '../notify/NotificationDelivery';
import { AppPush } from '../../features/push/AppPush';
import { AppGlobal } from '../../app/AppGlobal';
import { ReminderPlan } from '../../features/reminder/ReminderModels';

export class ReminderPublishResult {
  ok: boolean = false;
  code: number = 0;
  reminderId: number = -1;
  message: string = '';
}

export class ReminderAgent {
  static async publish(plan: ReminderPlan, interactive: boolean = true): Promise<ReminderPublishResult> {
    const result: ReminderPublishResult = new ReminderPublishResult();
    const allowed: boolean = interactive ? await AppPush.ensurePermission() : await AppPush.systemEnabled();
    if (!allowed) {
      result.message = '请在系统设置中允许枫丹工具箱发送通知';
      return result;
    }
    if (!Number.isFinite(plan.triggerAt) || plan.triggerAt <= Date.now()) {
      result.message = '请选择将来的提醒时间';
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
          second: date.getSeconds()
        },
        title: plan.title,
        content: plan.content,
        expiredContent: plan.content,
        ringDuration: 3,
        snoozeTimes: 0,
        autoDeletedTime: plan.expiresAt || undefined,
        notificationId: plan.notificationId || NotificationDelivery.id('reminder:' + plan.toolId + ':' + (plan.taskId || plan.homeworkId || plan.noticeId || plan.title) + ':' + plan.triggerAt),
        wantAgent: {
          pkgName: APP_BUNDLE,
          abilityName: 'EntryAbility',
          parameters: plan.launchParameters ?? NotificationDelivery.route(plan.toolId, plan.homeworkId, plan.taskId, plan.noticeId)
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
      const code: number = (e as BusinessError).code;
      result.code = code;
      if (code === 1700002) {
        result.message = '系统提醒配额不可用或已用完（1700002）。请检查应用的代理提醒权益';
      } else if (code === 1700001) {
        result.message = '请在系统通知设置中允许枫丹工具箱发送通知';
      } else {
        result.message = '系统未接受定时提醒（' + code + '），请稍后重试';
      }
      return result;
    }
  }

  /** 只在用户点击「添加到系统日历」后打开确认页，返回值由系统保存/取消操作决定。 */
  static async calendar(plan: ReminderPlan): Promise<string> {
    const context = AppGlobal.context;
    if (!context || !canIUse('SystemCapability.Applications.CalendarData')) {
      return '当前设备无法打开系统日历';
    }
    if (!Number.isFinite(plan.triggerAt) || plan.triggerAt <= Date.now()) {
      return '请选择将来的提醒时间';
    }
    const start = plan.calendarStart();
    try {
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: plan.title,
        description: plan.content,
        startTime: start,
        endTime: start + 60000,
        reminderTime: [plan.calendarLeadMinutes()]
      };
      const manager = calendarManager.getCalendarManager(context);
      const id: number = await manager.editEvent(event);
      return id > 0 ? '已保存到系统日历，可在日历中修改或删除' : '未保存日历提醒';
    } catch (error) {
      return '系统日历未能保存提醒';
    }
  }

  /** 清除旧版本因分隔符缺陷未保存代理 ID 的排程，保留显式作业提醒。 */
  static async removeLegacy(manualIds: Set<number>): Promise<void> {
    try {
      const valid = await reminderAgentManager.getAllValidReminders();
      for (const info of valid) {
        const req = info.reminderReq;
        if (manualIds.has(info.reminderId) || req.wantAgent?.parameters?.['toolId']) continue;
        const title: string = req.title || '';
        if (title.startsWith('上课提醒 · ') || ['作业即将截止', '活动即将截止', '活动开抢提醒', '投票结果可查看'].includes(title)) {
          await ReminderAgent.cancel(info.reminderId);
        }
      }
    } catch (error) {
      // 未开通系统代理提醒时没有可迁移的排程。
    }
  }

  static async cancelAll(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (error) {
      // 系统未开通代理服务时，应用仍可撤回已发送的普通通知。
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
      return (e as BusinessError).code === 1700003;
    }
  }

}
