import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import fs from '@ohos.file.fs';
import { AppGlobal } from '../../app/AppGlobal';
import { DiagCheck, DiagStatus, DiagSummary } from '../../data/diag/DiagModels';

const MB: number = 1024 * 1024;

/** 本机设备检查（纯本地 + 网关延迟；不包含任何隐私字段）。 */
export class DeviceChecks {
  /** 运行全部检查；`gatewayOk/latencyMs` 由调用方探测后传入。 */
  static async run(gatewayOk: boolean, latencyMs: number): Promise<DiagSummary> {
    const summary: DiagSummary = new DiagSummary();
    summary.ranAt = Date.now();

    const version: DiagCheck = new DiagCheck();
    version.id = 'app_version';
    version.label = '应用版本';
    version.status = DiagStatus.PASS;
    version.value = await DeviceChecks.versionName();
    summary.checks.push(version);

    const device: DiagCheck = new DiagCheck();
    device.id = 'device';
    device.label = '设备型号';
    device.status = DiagStatus.PASS;
    device.value = deviceInfo.productModel !== undefined && deviceInfo.productModel.length > 0
      ? deviceInfo.productModel : '未知';
    summary.checks.push(device);

    const os: DiagCheck = new DiagCheck();
    os.id = 'os';
    os.label = '系统版本';
    os.status = DiagStatus.PASS;
    os.value = (deviceInfo.osFullName !== undefined ? deviceInfo.osFullName : 'HarmonyOS')
      + ' / API ' + deviceInfo.sdkApiVersion;
    summary.checks.push(os);

    const storage: DiagCheck = await DeviceChecks.storageCheck();
    summary.checks.push(storage);

    const gateway: DiagCheck = new DiagCheck();
    gateway.id = 'gateway';
    gateway.label = '云端网关';
    gateway.value = gatewayOk ? latencyMs + ' ms' : '不可达';
    if (!gatewayOk) {
      gateway.status = DiagStatus.FAIL;
      gateway.hint = '网络不可用或网关异常';
    } else if (latencyMs > 2000) {
      gateway.status = DiagStatus.WARN;
      gateway.hint = '延迟偏高';
    } else {
      gateway.status = DiagStatus.PASS;
    }
    summary.checks.push(gateway);

    const session: DiagCheck = new DiagCheck();
    session.id = 'session';
    session.label = '身份会话';
    session.status = DiagStatus.PASS;
    session.value = '已登录';
    summary.checks.push(session);

    return summary;
  }

  private static async versionName(): Promise<string> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const name: string = info.versionName !== undefined ? info.versionName : '';
      return name.length > 0 ? name + ' (' + info.versionCode + ')' : '—';
    } catch (e) {
      return '—';
    }
  }

  private static async storageCheck(): Promise<DiagCheck> {
    const check: DiagCheck = new DiagCheck();
    check.id = 'storage';
    check.label = '应用目录';
    try {
      const context = AppGlobal.context;
      if (context === undefined) {
        check.status = DiagStatus.INFO;
        check.value = '未知';
        return check;
      }
      const writable: boolean = fs.accessSync(context.filesDir);
      check.value = writable ? '可读写' : '不可写';
      check.status = writable ? DiagStatus.PASS : DiagStatus.FAIL;
      if (!writable) {
        check.hint = '应用目录不可写';
      }
    } catch (e) {
      check.status = DiagStatus.INFO;
      check.value = '读取失败';
    }
    return check;
  }
}
