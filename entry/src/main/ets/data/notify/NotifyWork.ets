import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { Log } from '../../common/Log';

export class NotifyWork {
  static readonly ID: number = 19477;
  private static changes: Promise<void> = Promise.resolve();

  static owner(ctx: common.Context): string {
    try {
      return fs.readTextSync(ctx.filesDir + '/notify_work_owner');
    } catch (_) {
      return '';
    }
  }

  static configure(enabled: boolean): Promise<void> {
    const ctx = AppGlobal.context;
    if (!ctx || !canIUse('SystemCapability.ResourceSchedule.WorkScheduler')) return Promise.resolve();
    const sid = enabled ? Services.currentSid : '';
    const path = ctx.filesDir + '/notify_work_owner';
    try {
      if (sid && !NotifyWork.owner(ctx).startsWith(sid + '|')) {
        const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        try { fs.writeSync(file.fd, sid + '|' + util.generateRandomUUID(true)); }
        finally { fs.closeSync(file); }
        fs.renameSync(path + '.tmp', path);
      } else if (!sid && fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (_) {
      Log.w('NotifyWork', '无法更新后台提醒的账号状态');
      return Promise.resolve();
    }
    const work: workScheduler.WorkInfo = {
      workId: NotifyWork.ID, bundleName: ctx.abilityInfo.bundleName, abilityName: 'NotifyWorkAbility',
      isPersisted: true, networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true, repeatCycleTime: 2 * 60 * 60 * 1000
    };
    NotifyWork.changes = NotifyWork.changes.then(async () => {
      const jobs = await workScheduler.obtainAllWorks();
      const exists = jobs.some((item: workScheduler.WorkInfo) => item.workId === work.workId);
      const wanted = !!NotifyWork.owner(ctx);
      if (wanted && !exists) workScheduler.startWork(work);
      if (!wanted && exists) workScheduler.stopWork(work, true);
    }).catch(() => { Log.w('NotifyWork', '系统暂未接受后台提醒刷新任务'); });
    return NotifyWork.changes;
  }
}
