import { Api } from '../net/Api';
import { ApiResult } from '../net/ApiResult';
import { Blob } from '../sync/JsonBlob';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { VisitDevice } from './VisitDevice';
import { preferences } from '@kit.ArkData';

const TAG: string = 'Visits';
const STORE_NAME: string = 'class_tools_visits';
const KEY_DID: string = 'visit_did';

/** 访问上报本机状态（按 sid 记录最近已上报的 slot）。 */
export interface VisitsStore {
  getSlot(sid: string): Promise<string>;

  setSlot(sid: string, slot: string): Promise<void>;

  /** 本机设备指纹（8..64 位十六进制；仅用于去重，不含个人信息）。 */
  deviceId(): Promise<string>;
}

export class InMemoryVisitsStore implements VisitsStore {
  private slots: Map<string, string> = new Map<string, string>();
  private did: string = '';

  constructor(did: string = 'a1b2c3d4e5f60718') {
    this.did = did;
  }

  async getSlot(sid: string): Promise<string> {
    const value: string | undefined = this.slots.get(sid);
    return value !== undefined ? value : '';
  }

  async setSlot(sid: string, slot: string): Promise<void> {
    this.slots.set(sid, slot);
  }

  async deviceId(): Promise<string> {
    return this.did;
  }
}

/** preferences 实现（体积小；不落任何隐私字段）。 */
export class PreferencesVisitsStore implements VisitsStore {
  private store: preferences.Preferences | undefined = undefined;

  private async ensure(): Promise<preferences.Preferences | undefined> {
    if (this.store !== undefined) {
      return this.store;
    }
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      this.store = await preferences.getPreferences(ctx, { name: STORE_NAME });
      return this.store;
    } catch (e) {
      Log.w(TAG, '打开 visits preferences 失败');
      return undefined;
    }
  }

  async getSlot(sid: string): Promise<string> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return '';
    }
    try {
      return store.getSync('slot_' + sid, '') as string;
    } catch (e) {
      return '';
    }
  }

  async setSlot(sid: string, slot: string): Promise<void> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return;
    }
    try {
      store.putSync('slot_' + sid, slot);
      await store.flush();
    } catch (e) {
      Log.w(TAG, '写入 visits slot 失败');
    }
  }

  async deviceId(): Promise<string> {
    const store: preferences.Preferences | undefined = await this.ensure();
    if (store === undefined) {
      return 'unknown0000000000';
    }
    try {
      const existing: string = store.getSync(KEY_DID, '') as string;
      if (existing.length >= 8) {
        return existing;
      }
      const generated: string = randomHex16();
      store.putSync(KEY_DID, generated);
      await store.flush();
      return generated;
    } catch (e) {
      return 'unknown0000000000';
    }
  }
}

/**
 * 访问上报（与网页 `visitLog()` 同口径）：
 * - `POST visits` **不带** `Prefer: return=representation`（returning 会被 RLS 拒绝）；
 * - `id = "<sid>|<slot>|<随机6位>"`、`slot = YYYY-MM-DD-HH`；
 * - 行含 `client = "harmony"`、`ver`（`CloudConfig.APP_VERSION`）、`dev`（设备短标签，
 *   统计多端详细统计契约 §1/§5）；
 * - 同一 sid 同一 slot 只报一次（本机记录），失败不记，下次重试；
 * - 版本/设备取不到也照常上报（空串 / 兜底），不阻断、不重试风暴。
 */
export class VisitsReporter {
  private api: Api;
  private store: VisitsStore;
  private sidProvider: () => string;
  private nameProvider: () => string;
  private clock: () => number;
  private devProvider: () => string;

  constructor(api: Api, store: VisitsStore, sidProvider: () => string, nameProvider: () => string,
    clock: () => number = () => Date.now(), devProvider: () => string = () => VisitDevice.current()) {
    this.api = api;
    this.store = store;
    this.sidProvider = sidProvider;
    this.nameProvider = nameProvider;
    this.clock = clock;
    this.devProvider = devProvider;
  }

  async reportOnce(): Promise<boolean> {
    const sid: string = this.sidProvider().trim();
    if (sid.length === 0 || this.nameProvider().trim().length === 0) {
      return false;
    }
    const slot: string = formatSlot(new Date(this.clock()));
    const last: string = await this.store.getSlot(sid);
    if (last === slot) {
      return false;
    }
    const did: string = await this.store.deviceId();
    const random: string = randomBase36(6);
    let dev: string = '';
    try {
      dev = this.devProvider();
    } catch (e) {
      // 契约：设备信息拿不到就写空串，不能因此阻断上报。
      dev = '';
    }
    const row: Blob = {
      'id': sid + '|' + slot + '|' + random,
      'slot': slot,
      'sid': sid,
      'name': this.nameProvider().trim(),
      'did': did,
      'ts': this.clock(),
      'client': 'harmony',
      'ver': VisitDevice.appVersion(),
      'dev': dev
    };
    const rows: Object[] = [row];
    const result: ApiResult = await this.api.post('visits', JSON.stringify(rows), '', true);
    if (!result.ok) {
      return false;
    }
    await this.store.setSlot(sid, slot);
    return true;
  }
}

/** `YYYY-MM-DD-HH`（本地时区，与网页 `vsSlot` 一致）。 */
export function formatSlot(date: Date): string {
  const month: string = pad2(date.getMonth() + 1);
  const day: string = pad2(date.getDate());
  const hour: string = pad2(date.getHours());
  return date.getFullYear() + '-' + month + '-' + day + '-' + hour;
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function randomHex16(): string {
  let out: string = '';
  for (let i = 0; i < 16; i++) {
    out += Math.floor(Math.random() * 16).toString(16);
  }
  return out;
}

function randomBase36(length: number): string {
  const chars: string = '0123456789abcdefghijklmnopqrstuvwxyz';
  let out: string = '';
  for (let i = 0; i < length; i++) {
    out += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return out;
}
