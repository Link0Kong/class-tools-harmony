import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppGlobal } from '../app/AppGlobal';
import { Services } from '../app/Services';
import { LiveActivity } from '../data/notify/LiveActivity';
import { NotifyCenter } from '../data/notify/NotifyCenter';
import { ToolLaunch } from '../app/ToolLaunch';
import { DeskForms } from '../forms/DeskForms';
import { TaskRepository } from '../data/tasks/TaskRepository';

const DOMAIN: number = 0x1001;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 数据层（preferences 等）依赖 UIAbilityContext，进程内只注入一次。
    AppGlobal.context = this.context;
    AppGlobal.ability = this;
    AppGlobal.requestTool(ToolLaunch.parse(want.parameters, want.uri));
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppGlobal.requestTool(ToolLaunch.parse(want.parameters, want.uri));
  }

  onDestroy(): void {
    LiveActivity.releasePage();
    AppGlobal.onLaunch = undefined;
    AppGlobal.onToolClosed = undefined;
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageCreate');
    // 全屏布局：让页面背景与内容延伸到手势条区域，去掉底部系统留白。
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FF000000',
        navigationBarContentColor: '#FF000000'
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed');
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const win: window.Window = windowStage.getMainWindowSync();
        const avoid: window.AvoidArea = win.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_SYSTEM);
        AppGlobal.statusBarPx = avoid.topRect.height;
        hilog.info(DOMAIN, TAG, 'statusBarPx=%{public}d', AppGlobal.statusBarPx);
      } catch (inner) {
        AppGlobal.statusBarPx = 0;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loadContent ok');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    AppStorage.setOrCreate<number>('waterForeground', Date.now());
    NotifyCenter.setForeground(true);
    if (Services.currentSid.length > 0) {
      TaskRepository.load(true).then(() => DeskForms.refresh());
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
    // 回到前台补一次扫描（内部 3 分钟节流），把错过的截止/新通知补成系统提醒
    NotifyCenter.syncAll();
  }

  onBackground(): void {
    NotifyCenter.setForeground(false);
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
    // 页面隐藏：立即冲刷待推送的 userdata（失败由 pending 兜底）
    Services.userdata.flush();
    // 退到后台前把未来 7 天的提醒排进系统日程，应用被关闭后仍由系统按时触发
    NotifyCenter.syncAll(true);
  }

  /**
   * Ability 级返回键：工具页打开时先关闭工具页（不退出应用）。
   *
   * 页面级 `onBackPress` 在 Stack 覆盖层场景下不一定被调用，这里做兜底。
   */
  onBackPressed(): boolean {
    if (AppGlobal.openToolId.length > 0) {
      if (AppGlobal.toolBack?.()) return true;
      AppGlobal.openToolId = '';
      if (AppGlobal.onToolClosed !== undefined) {
        AppGlobal.onToolClosed();
      }
      return true;
    }
    return false;
  }
}
