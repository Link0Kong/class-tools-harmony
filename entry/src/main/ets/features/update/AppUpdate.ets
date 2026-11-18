import { updateManager } from '@kit.AppGalleryKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';

export class UpdateCheckResult {
  available: boolean = false;
  message: string = '';
}

/**
 * 应用市场版本更新提醒（AppGallery Kit updateManager）。
 *
 * - 启动后静默检查一次：有新版本时拉起系统升级对话框；
 * - 「我的 → 检查更新」主动检查：无论结果都给出提示；
 * - 未上架/未同意隐私协议/不在前台等失败场景只做降级提示，不影响主流程。
 */
export class AppUpdate {
  private static checking: boolean = false;

  static async check(showDialog: boolean): Promise<UpdateCheckResult> {
    const result: UpdateCheckResult = new UpdateCheckResult();
    if (AppUpdate.checking) {
      result.message = '正在检查更新';
      return result;
    }
    const context: common.UIAbilityContext | undefined = AppGlobal.context;
    if (context === undefined) {
      result.message = '暂时无法检查更新';
      return result;
    }
    AppUpdate.checking = true;
    try {
      const checked: updateManager.CheckUpdateResult = await updateManager.checkAppUpdate(context);
      result.available = checked.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST;
      if (result.available) {
        result.message = '发现新版本';
        if (showDialog) {
          try {
            await updateManager.showUpdateDialog(context);
          } catch (e) {
            AppUpdate.logError('showUpdateDialog', e);
          }
        }
      } else {
        result.message = '已是最新版本';
      }
      return result;
    } catch (e) {
      result.message = AppUpdate.describe(e);
      AppUpdate.logError('checkAppUpdate', e);
      return result;
    } finally {
      AppUpdate.checking = false;
    }
  }

  private static describe(e: Object): string {
    if (!(e instanceof Error)) {
      return '检查更新失败，请稍后重试';
    }
    const err: BusinessError = e as BusinessError;
    if (err.code === 1009400003) {
      return '网络不可用，请联网后重试';
    }
    if (err.code === 1009400004) {
      return '请保持应用在前台后重试';
    }
    if (err.code === 1009400005) {
      return '需先同意隐私协议，才能检查更新';
    }
    if (err.code === 1009400006 || err.code === 1009400007) {
      return '检查更新过于频繁，请稍后再试';
    }
    return '检查更新失败，请稍后重试';
  }

  private static logError(scene: string, e: Object): void {
    const err: BusinessError = e as BusinessError;
    Log.w('AppUpdate', scene + ' 失败 code=' + err.code + ' msg=' + err.message);
  }
}
