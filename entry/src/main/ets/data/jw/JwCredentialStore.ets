import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { JwCredentialLogic } from '../../features/jw/JwCredentialLogic';
import { Log } from '../../common/Log';

const TAG: string = 'JwCredentialStore';

/**
 * 本机教务 / 统一身份认证密码的安全存储（HarmonyOS Asset Store）。
 *
 * - 系统加密、应用私有；仅在设备首次解锁后可读（`DEVICE_FIRST_UNLOCKED`）；
 * - 不参与云同步（`SYNC_TYPE=NEVER`），卸载即清除（`IS_PERSISTENT=false`）；
 * - 别名 = 学号指纹（不含学号明文）；密码**不写日志/不上传/不导出**。
 *
 * 存储失败（设备不支持/服务异常）时返回 false，页面回退「每次手动输入」，不阻塞其它功能。
 */
export class JwCredentialStore {
  /** 保存/更新密码（同别名覆盖）。 */
  static async save(sid: string, password: string): Promise<boolean> {
    const alias: string = JwCredentialLogic.aliasOf(sid);
    if (alias.length === 0 || password.length === 0) {
      return false;
    }
    try {
      const attrs: asset.AssetMap = new Map();
      attrs.set(asset.Tag.ALIAS, JwCredentialStore.encode(alias));
      attrs.set(asset.Tag.SECRET, JwCredentialStore.encode(password));
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
      attrs.set(asset.Tag.IS_PERSISTENT, false);
      attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      await asset.add(attrs);
      return true;
    } catch (e) {
      Log.w(TAG, '保存本机凭据失败');
      return false;
    }
  }

  /** 读取密码；未保存/失败返回空串。 */
  static async load(sid: string): Promise<string> {
    const alias: string = JwCredentialLogic.aliasOf(sid);
    if (alias.length === 0) {
      return '';
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, JwCredentialStore.encode(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: asset.AssetMap[] = await asset.query(query);
      if (result.length === 0) {
        return '';
      }
      const secret = result[0].get(asset.Tag.SECRET);
      if (secret === undefined || typeof secret === 'number' || typeof secret === 'boolean') {
        return '';
      }
      return JwCredentialStore.decode(secret as Uint8Array);
    } catch (e) {
      Log.w(TAG, '读取本机凭据失败');
      return '';
    }
  }

  /** 是否已保存（不读明文，只按别名查询）。 */
  static async has(sid: string): Promise<boolean> {
    const secret: string = await JwCredentialStore.load(sid);
    return secret.length > 0;
  }

  /** 清除本机密码。 */
  static async clear(sid: string): Promise<boolean> {
    const alias: string = JwCredentialLogic.aliasOf(sid);
    if (alias.length === 0) {
      return false;
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, JwCredentialStore.encode(alias));
      await asset.remove(query);
      return true;
    } catch (e) {
      Log.w(TAG, '清除本机凭据失败');
      return false;
    }
  }

  private static encode(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  private static decode(bytes: Uint8Array): string {
    try {
      return new util.TextDecoder().decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }
}
