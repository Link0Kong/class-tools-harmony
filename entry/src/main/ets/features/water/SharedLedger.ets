import { Api } from '../../data/net/Api';
import { ApiResult } from '../../data/net/ApiResult';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { WaterRecord, WaterRoomState } from './WaterModels';
import { WaterCodec } from './WaterCodec';

export class MonthlyReading {
  month: string = '';
  reading: number = 0;
  persons: number = 4;
}

export class WaterIntent {
  kind: string = '';
  month: string = '';
  reading: number = 0;
  persons: number = 4;
  base: string = '?';
  sent: boolean = false;
}

export class LedgerData {
  rows: MonthlyReading[] = [];
  people: number = 0;
  knownRows: boolean = false;
  knownPeople: boolean = false;
  pending: WaterIntent | null = null;
  denied: boolean = false;
}

function parseRows(value: string): Blob[] {
  const raw = JSON.parse(value) as Object;
  if (!Array.isArray(raw)) throw new Error('共享行格式异常');
  return raw as Blob[];
}

function people(value: Object | null): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || Number(value) < 1 || Number(value) > 6) {
    throw new Error('共享人数异常');
  }
  return Number(value);
}

export class SharedLedger {
  data: LedgerData;
  rowsFresh: boolean = false;
  peopleFresh: boolean = false;
  status: string = '';
  private api: Api;
  private room: string;
  private sid: string;
  private active: () => boolean;
  private writeCache: (value: LedgerData) => void;
  private version: number = 0;

  constructor(api: Api, sid: string, room: string, data: LedgerData, active: () => boolean,
    writeCache: (value: LedgerData) => void) {
    this.api = api;
    this.sid = sid;
    this.room = room;
    this.data = data;
    this.active = active;
    this.writeCache = writeCache;
  }

  private current(v: number): void {
    if (!this.active() || v !== this.version) throw new Error('页面或会话已切换');
  }

  private response(result: ApiResult, v: number): string {
    this.current(v);
    if (!result.ok) {
      if (result.error && (result.error.status === 401 || result.error.status === 403)) this.deny();
      throw new Error('共享服务暂不可用');
    }
    return result.value;
  }

  private deny(): void {
    this.data.denied = true;
    this.data.knownRows = false;
    this.data.knownPeople = false;
    this.data.rows = [];
    this.data.people = 0;
    this.rowsFresh = false;
    this.peopleFresh = false;
    this.writeCache(this.data);
    throw new Error('班级身份未获授权');
  }

  private async loadRows(v: number): Promise<MonthlyReading[]> {
    const out: MonthlyReading[] = [];
    let last: string = '';
    while (true) {
      this.current(v);
      const url = 'water?select=roomverify,month,reading,persons&roomverify=eq.' + encodeURIComponent(this.room)
        + '&order=month.asc&limit=100' + (last === '' ? '' : '&month=gt.' + last);
      const page = parseRows(this.response(await this.api.get(url), v));
      if (page.length === 0) return out;
      for (let i = 0; i < page.length; i++) {
        const row = page[i];
        const m = JsonBlob.asString(row['month'], '');
        const value = row['reading'];
        if (row['roomverify'] !== this.room || !WaterCodec.normalizeMonth(m) || m <= last ||
          (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+(\.\d+)?$/.test(String(value)))) ||
          !Number.isFinite(Number(value)) || Number(value) < 0) throw new Error('共享读数格式异常');
        const r = new MonthlyReading();
        r.month = m;
        r.reading = Number(value);
        r.persons = people(row['persons']);
        last = m;
        out.push(r);
      }
    }
  }

  private async verify(v: number): Promise<void> {
    const row = JsonBlob.parse(this.response(await this.api.post('rpc/class_whoami', '{}'), v));
    if (row === undefined) throw new Error('无法解析身份回执');
    if (row['sid'] !== this.sid || row['ok'] === false) this.deny();
  }

  async refresh(): Promise<void> {
    const v = ++this.version;
    this.rowsFresh = false;
    this.peopleFresh = false;
    this.current(v);
    try {
      await this.verify(v);
      this.data.denied = false;
      try {
        const rows = await this.loadRows(v);
        if (rows.length === 0) await this.verify(v);
        this.current(v);
        this.data.rows = rows;
        this.data.knownRows = true;
        this.rowsFresh = true;
      } catch (e) {
        this.current(v);
        if (this.data.denied) throw new Error('班级身份未获授权');
      }
      const url = 'water_room?select=roomverify,persons&roomverify=eq.' + encodeURIComponent(this.room);
      const values = parseRows(this.response(await this.api.get(url), v));
      if (values.length > 1 || (values.length === 1 && values[0]['roomverify'] !== this.room)) {
        throw new Error('房间人数格式异常');
      }
      if (values.length === 0) await this.verify(v);
      this.current(v);
      this.data.people = values.length === 0 ? 0 : people(values[0]['persons']);
      this.data.knownPeople = true;
      this.peopleFresh = true;
    } catch (e) {
      this.current(v);
    }
    this.status = this.data.denied ? '班级身份未获授权' : (this.rowsFresh && this.peopleFresh ? '共享账本已刷新'
      : (this.rowsFresh ? '人数待核对' : (this.peopleFresh ? '月读数待核对' : '离线或读取失败，显示上次确认值')));
    this.writeCache(this.data);
  }

  roomState(): WaterRoomState {
    const display = new WaterRoomState();
    if (this.data.denied || !this.active()) return display;
    display.persons = this.data.people || 4;
    this.data.rows.forEach((r: MonthlyReading) => {
      const item = new WaterRecord();
      item.month = r.month;
      item.reading = r.reading;
      display.records.push(item);
    });
    return display;
  }

  private baseline(op: WaterIntent): string {
    if (op.kind === 'persons') return this.data.knownPeople ? String(this.data.people) : '?';
    if (!this.data.knownRows) return '?';
    const row = this.data.rows.find((r: MonthlyReading) => r.month === op.month);
    return row ? String(row.reading) + '/' + String(row.persons) : '-';
  }

  private target(op: WaterIntent): string {
    if (op.kind === 'persons') return String(op.persons);
    return op.kind === 'delete' ? '-' : String(op.reading) + '/' + String(op.persons);
  }

  prepare(kind: string, month: string, reading: number, count: number): void {
    this.current(this.version);
    if (this.data.denied || this.data.pending) throw new Error('请先处理现有待确认操作');
    if (kind !== 'persons' && kind !== 'save' && kind !== 'delete') throw new Error('操作无效');
    if (kind !== 'persons' && !WaterCodec.normalizeMonth(month)) throw new Error('月份无效');
    if (kind === 'save' && (!Number.isFinite(reading) || reading < 0)) throw new Error('读数无效');
    const op = new WaterIntent();
    op.kind = kind;
    op.month = month;
    op.reading = Math.round(reading * 100) / 100;
    op.persons = people(count);
    op.base = this.baseline(op);
    this.data.pending = op;
    this.writeCache(this.data);
  }

  discard(): void {
    this.current(this.version);
    this.data.pending = null;
    this.writeCache(this.data);
  }

  async submit(reconfirm: boolean = false): Promise<string> {
    const op = this.data.pending;
    if (!op) return '';
    const observed = this.baseline(op);
    const v = this.version + 1;
    await this.refresh();
    this.current(v);
    if (this.data.denied || !(op.kind === 'persons' ? this.peopleFresh : this.rowsFresh)) return this.status;
    const now = this.baseline(op);
    if (now === this.target(op)) {
      this.discard();
      return '共享账本已确认';
    }
    if ((op.sent || op.base === '?' || now !== op.base) && !(reconfirm && observed === now)) {
      return '共享值已变化或上次提交结果未知。请核对后确认或放弃草稿';
    }
    op.base = now;
    op.sent = true;
    this.writeCache(this.data);
    const filter = 'roomverify=eq.' + encodeURIComponent(this.room);
    const body: Blob = { 'roomverify': this.room, 'persons': op.persons };
    let answer: ApiResult;
    if (op.kind === 'persons') {
      answer = now === '0' ? await this.api.post('water_room', JSON.stringify(body))
        : await this.api.patch('water_room?' + filter + '&persons=eq.' + now, JSON.stringify(body));
    } else {
      const match = now === '-' ? '' : '&reading=eq.' + now.split('/')[0] + '&persons=eq.' + now.split('/')[1];
      const url = 'water?' + filter + '&month=eq.' + op.month + match;
      if (op.kind === 'delete') {
        answer = await this.api.delete(url);
      } else {
        body['month'] = op.month;
        body['reading'] = op.reading;
        answer = now === '-' ? await this.api.post('water', JSON.stringify(body)) : await this.api.patch(url, JSON.stringify(body));
      }
    }
    this.current(v);
    if (answer.error && (answer.error.status === 401 || answer.error.status === 403)) this.deny();
    const confirmation = this.version + 1;
    await this.refresh();
    this.current(confirmation);
    if (!this.data.denied && (op.kind === 'persons' ? this.peopleFresh : this.rowsFresh) && this.baseline(op) === this.target(op)) {
      this.discard();
      return '共享账本已确认';
    }
    return '尚未确认写入，请核对共享值后重试';
  }
}
