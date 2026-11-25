import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { DeskFormStore } from './DeskFormStore';
import { DeskRemote } from './DeskRemote';
import { Log } from '../common/Log';

export default class DeskFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters;
    const id = String(params?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const kind = String(params?.[formInfo.FormParam.NAME_KEY] ?? 'home');
    const dim = Number(params?.[formInfo.FormParam.DIMENSION_KEY] ?? 2);
    return DeskFormStore.binding(this.context.filesDir, id, kind, dim);
  }

  async onUpdateForm(id: string): Promise<void> {
    try {
      const form = await formProvider.getPublishedRunningFormInfoById(id);
      await DeskFormStore.update(this.context.filesDir, form);
      if (await DeskRemote.refresh(this.context)) {
        await DeskFormStore.update(this.context.filesDir, form);
      }
    } catch (_) {
      Log.w('DeskForm', '卡片暂时不可用');
    }
  }

  async onFormEvent(id: string, message: string): Promise<void> {
    // The sole message action is the color chip. The host wraps its params differently across versions.
    DeskFormStore.nextColor(this.context.filesDir, id);
    const form = await formProvider.getPublishedRunningFormInfoById(id);
    await DeskFormStore.update(this.context.filesDir, form);
  }

  onRemoveForm(id: string): void {
    DeskFormStore.remove(this.context.filesDir, id);
  }
}
