/**
 * 本机教务密码的纯逻辑（不 import 安全存储，hypium 可直接测）。
 *
 * 为什么需要：教务登录需要「本机保存的教务密码」。
 * 存储实现见 `data/jw/JwCredentialStore.ets`（HarmonyOS Asset Store，应用私有 + 系统加密）。
 *
 * 红线：密码只在本机安全存储与内存中出现；**不参与 userdata 云同步、不上传、不写日志、不导出**；
 * 别名不含学号明文（FNV-1a 指纹），避免存储条目本身泄漏学号。
 */
export class JwCredentialLogic {
  /** 存储别名前缀（版本化，便于以后换存储实现时清理）。 */
  static readonly ALIAS_PREFIX: string = 'jw_pwd_v1_';

  /** 密码最大长度（与 CAS 输入框 maxlength 一致）。 */
  static readonly MAX_PASSWORD_LENGTH: number = 32;

  /** 保存说明（界面唯一一句说明）。 */
  static readonly STORAGE_NOTE: string =
    '密码只保存在本机安全存储（应用私有、系统加密），用于教务登录自动填充；不上传、不参与云同步。';

  /** 别名：学号 FNV-1a 指纹（不含学号明文；同 sid 稳定，不同 sid 不同）。 */
  static aliasOf(sid: string): string {
    const text: string = sid.trim();
    let hash: number = 0x811C9DC5;
    for (let i = 0; i < text.length; i++) {
      hash = hash ^ text.charCodeAt(i);
      // FNV-1a 32 位乘法（用 16 位拆分避免浮点精度损失）
      hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))) >>> 0;
    }
    let hex: string = hash.toString(16);
    while (hex.length < 8) {
      hex = '0' + hex;
    }
    return JwCredentialLogic.ALIAS_PREFIX + hex;
  }

  /** 密码校验：合法返回空串，否则返回可直接展示的中文提示。 */
  static validatePassword(password: string): string {
    if (password.length === 0) {
      return '请输入教务密码';
    }
    if (password.length > JwCredentialLogic.MAX_PASSWORD_LENGTH) {
      return '密码过长（最多 ' + JwCredentialLogic.MAX_PASSWORD_LENGTH + ' 位）';
    }
    return '';
  }

  /** 是否可自动填充：有学号 + 本机已保存密码。 */
  static canAutoFill(sid: string, hasSavedCredential: boolean): boolean {
    return sid.trim().length > 0 && hasSavedCredential;
  }

  /** 本机凭据状态文案。 */
  static savedStateText(hasSavedCredential: boolean): string {
    return hasSavedCredential ? '已保存到本机' : '本机未保存';
  }

  /** 保存按钮文案（已保存 → 更新）。 */
  static saveButtonText(hasSavedCredential: boolean): string {
    return hasSavedCredential ? '更新密码' : '保存密码';
  }

  /** 清除按钮是否可见（只有已保存时才给「清除」）。 */
  static showClearButton(hasSavedCredential: boolean): boolean {
    return hasSavedCredential;
  }

  /** 密码脱敏展示（仅用于调试/单测，UI 不展示密码本身）：固定 `••••••`。 */
  static masked(): string {
    return '••••••';
  }
}
