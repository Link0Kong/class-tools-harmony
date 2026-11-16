import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppGlobal } from '../app/AppGlobal';
import { Services } from '../app/Services';

const DOMAIN: number = 0x1001;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 数据层（preferences 等）依赖 UIAbilityContext，进程内只注入一次。
    AppGlobal.context = this.context;
    AppGlobal.ability = this;
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loadContent ok');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
    // 页面隐藏：立即冲刷待推送的 userdata（失败由 pending 兜底）
    Services.userdata.flush();
  }

  /**
   * Ability 级返回键：工具页打开时先关闭工具页（不退出应用）。
   *
   * 页面级 `onBackPress` 在 Stack 覆盖层场景下不一定被调用，这里做兜底。
   */
  onBackPressed(): boolean {
    if (AppGlobal.openToolId.length > 0) {
      AppGlobal.openToolId = '';
      if (AppGlobal.onToolClosed !== undefined) {
        AppGlobal.onToolClosed();
      }
      return true;
    }
    return false;
  }
}
