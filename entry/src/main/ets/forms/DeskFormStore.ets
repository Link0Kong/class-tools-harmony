import { fileIo as fs } from '@kit.CoreFileKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { util } from '@kit.ArkTS';
import { DeskFeed, deskContent } from './DeskContent';

/** UIAbility writes the feed, FormExtensionAbility owns each instance's color. */
export class DeskFormStore {
  private static updates: Promise<void> = Promise.resolve();
  static feed(dir: string): DeskFeed {
    const local = DeskFormStore.primary(dir);
    if (!local.sid) return local;
    const remote = DeskFormStore.read(dir + '/desk_remote.json');
    return remote && remote.sid === local.sid && remote.revision === local.revision ? remote : local;
  }

  static primary(dir: string): DeskFeed {
    return DeskFormStore.read(dir + '/desk_feed.json') ?? new DeskFeed();
  }

  private static read(path: string): DeskFeed | undefined {
    try {
      if (fs.accessSync(path)) {
        return JSON.parse(fs.readTextSync(path)) as DeskFeed;
      }
    } catch (_) {}
    return undefined;
  }

  static save(dir: string, feed: DeskFeed): void {
    const path = dir + '/desk_feed.json';
    feed.revision = util.generateRandomUUID(true);
    DeskFormStore.write(path + '.tmp', JSON.stringify(feed));
    fs.renameSync(path + '.tmp', path);
    const overlay = dir + '/desk_remote.json';
    if (fs.accessSync(overlay)) fs.unlinkSync(overlay);
  }

  static saveRemote(dir: string, feed: DeskFeed): void {
    const before = DeskFormStore.primary(dir);
    if (before.sid !== feed.sid || before.revision !== feed.revision) return;
    const path = dir + '/desk_remote.json';
    DeskFormStore.write(path + '.tmp', JSON.stringify(feed));
    fs.renameSync(path + '.tmp', path);
    if (DeskFormStore.primary(dir).revision !== feed.revision && fs.accessSync(path)) fs.unlinkSync(path);
  }

  private static write(path: string, text: string): void {
    const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      fs.writeSync(f.fd, text);
    } finally {
      fs.closeSync(f);
    }
  }

  private static colorPath(dir: string, id: string): string {
    if (!new RegExp('^[0-9]+$').test(id)) {
      throw new Error('invalid form ID');
    }
    return dir + '/desk_palette_' + id;
  }

  static color(dir: string, id: string): number {
    try {
      const path = DeskFormStore.colorPath(dir, id);
      if (fs.accessSync(path)) {
        const value = Number(fs.readTextSync(path));
        if ([0, 1, 2, 3].includes(value)) return value;
      }
    } catch (_) {}
    return 0;
  }

  static nextColor(dir: string, id: string): void {
    const path = DeskFormStore.colorPath(dir, id);
    DeskFormStore.write(path + '.tmp', String((DeskFormStore.color(dir, id) + 1) % 4));
    fs.renameSync(path + '.tmp', path);
  }

  static remove(dir: string, id: string): void {
    const path = DeskFormStore.colorPath(dir, id);
    if (fs.accessSync(path)) fs.unlinkSync(path);
  }

  static binding(dir: string, id: string, kind: string, dim: number): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(deskContent(kind, DeskFormStore.feed(dir), dim,
      DeskFormStore.color(dir, id), Date.now()));
  }

  static async update(dir: string, form: formInfo.RunningFormInfo): Promise<void> {
    if (form.abilityName !== 'DeskFormAbility') return;
    await formProvider.updateForm(form.formId, DeskFormStore.binding(dir, form.formId, form.formName, form.dimension));
  }

  static publish(dir: string): Promise<void> {
    DeskFormStore.updates = DeskFormStore.updates.catch(() => {}).then(() => DeskFormStore.updateAll(dir));
    return DeskFormStore.updates;
  }

  private static async updateAll(dir: string): Promise<void> {
    const infos = await formProvider.getPublishedRunningFormInfos();
    for (const info of infos) {
      // Instances may disappear while the launcher is updating its form list.
      try {
        await DeskFormStore.update(dir, info);
      } catch (_) {}
    }
  }
}
