import { common, UIAbility } from '@kit.AbilityKit';

/**
 * 进程级全局对象。
 *
 * `context` 由 EntryAbility.onCreate 注入，供 preferences / 文件等需要 Context 的数据层使用。
 * `openToolId` 记录当前打开的工具页（根页面维护），供 Ability 级返回键处理使用。
 */
export class AppGlobal {
  static context: common.UIAbilityContext | undefined = undefined;

  /** 当前 UIAbility（Push Kit 的 tokenUpdate 需要 Ability 实例）。 */
  static ability: UIAbility | undefined = undefined;

  /** 当前打开的工具 id（'' = 在根页面）。 */
  static openToolId: string = '';

  /** Ability 级返回键关闭工具页时回调根页面（由 Index 注册）。 */
  static onToolClosed: (() => void) | undefined = undefined;
}
