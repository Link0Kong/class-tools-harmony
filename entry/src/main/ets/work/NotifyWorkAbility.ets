import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { Log } from '../common/Log';
import { SessionStore } from '../data/session/SessionStore';
import { NotifyWork } from '../data/notify/NotifyWork';
import { NotifyStore } from '../data/notify/NotifyStore';
import { NotifyCenter } from '../data/notify/NotifyCenter';
import { NotificationInputs } from '../data/notify/NotificationInputs';
import { ReminderStore } from '../data/reminder/ReminderStore';
import { AppPush } from '../features/push/AppPush';

export default class NotifyWorkAbility extends WorkSchedulerExtensionAbility {
  private runId: number = 0;

  onWorkStart(work: workScheduler.WorkInfo): void {
    const run = ++this.runId;
    this.refresh(run).catch(() => { Log.w('NotifyWork', '本次后台刷新未完成'); }).finally(() => {
      if (run !== this.runId || work.workId !== NotifyWork.ID || !work.bundleName || !work.abilityName) return;
      try { workScheduler.stopWork(work, false); } catch (_) {}
    });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    this.runId++;
  }

  private async refresh(run: number): Promise<void> {
    const ctx = this.context;
    const owner = NotifyWork.owner(ctx);
    if (!owner || !await AppPush.systemEnabled()) return;
    const session = await new SessionStore(ctx).load();
    if (!session?.token || !owner.startsWith(session.sid + '|')) return;
    const stillOwner = async (): Promise<boolean> => run === this.runId && NotifyWork.owner(ctx) === owner
      && (session.expiresAt <= 0 || session.expiresAt > Date.now());
    const settings = await NotifyStore.loadSettings(session.sid, ctx);
    if (!settings.master || !await stillOwner()) return;
    Log.i('NotifyWork', '已开始后台提醒刷新');
    const feeds = await NotificationInputs.read(ctx, session, settings);
    if (!await stillOwner()) return;
    const manual = await ReminderStore.load(session.sid, ctx);
    feeds.input.manualHomework = Array.from(manual.ids.keys());
    if (await NotifyCenter.syncBackground(ctx, session.sid, feeds.input, stillOwner, feeds.tasks)) {
      Log.i('NotifyWork', '已完成后台提醒刷新');
    } else {
      Log.i('NotifyWork', '后台刷新未完成全部投递');
    }
  }
}
