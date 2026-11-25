import { fileIo as fs } from '@kit.CoreFileKit';
import { FileMarksLocalStore, InMemoryMarksLocalStore, MarksRefreshResult, MarksRepository } from '../marks/MarksRepository';
import { HttpClient } from '../net/HttpClient';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { mergeTaskEdits, TaskWire } from '../tasks/TaskMerge';
import { PersonalTask } from '../tasks/TaskModels';

/** Read the server snapshot together with pending device edits, without uploading from an extension. */
export class BackgroundReads {
  static async marks(api: HttpClient, sid: string, dir: string): Promise<MarksRefreshResult> {
    const files = new FileMarksLocalStore(() => sid, dir + '/marks');
    const memory = new InMemoryMarksLocalStore();
    await memory.writeCache(await files.readCache());
    await memory.writePending(await files.readPending());
    return new MarksRepository(api, () => sid, memory).refresh(true);
  }

  static async tasks(api: HttpClient, sid: string, dir: string): Promise<PersonalTask[] | undefined> {
    const got = await api.get('taskdata?id=eq.' + encodeURIComponent(sid) + '&select=blob,ts');
    if (!got.ok) return undefined;
    try {
      const rows = JSON.parse(got.value) as Blob[];
      if (!Array.isArray(rows)) return undefined;
      const wire = TaskWire.read(rows.length ? rows[0]['blob'] : undefined);
      if (!wire) return undefined;
      const remote = wire.snapshot;
      const path = dir + '/tasks_' + encodeURIComponent(sid) + '.json';
      if (!fs.accessSync(path)) return PersonalTask.list(remote);
      const envelope = JsonBlob.parse(fs.readTextSync(path));
      const base = JsonBlob.asBlob(envelope?.['base']);
      const local = JsonBlob.asBlob(envelope?.['local']);
      if (!base || !local) return undefined;
      return PersonalTask.list(mergeTaskEdits(base, local, remote));
    } catch (_) {
      return undefined;
    }
  }
}
