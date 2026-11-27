import { fileIo as fs } from '@kit.CoreFileKit';
import { AppGlobal } from '../../app/AppGlobal';
import { LedgerData } from './SharedLedger';

export class WaterLedgerFile {
  private path: string;

  constructor(sid: string, room: string) {
    const ctx = AppGlobal.context;
    this.path = !ctx || !sid || !room ? '' : ctx.filesDir + '/water_' + encodeURIComponent(sid) + '_' +
      encodeURIComponent(room) + '.json';
  }

  load(): LedgerData {
    if (!this.path || !fs.accessSync(this.path)) return new LedgerData();
    const data: LedgerData = JSON.parse(fs.readTextSync(this.path)) as LedgerData;
    if (!Array.isArray(data.rows) || typeof data.knownRows !== 'boolean' || typeof data.knownPeople !== 'boolean') {
      throw new Error('共享账本缓存无法读取');
    }
    return data;
  }

  save(data: LedgerData): void {
    if (!this.path) throw new Error('当前身份无法保存草稿');
    const tmp = this.path + '.tmp';
    const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(data));
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(tmp, this.path);
  }
}
