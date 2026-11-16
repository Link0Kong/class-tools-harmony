import { Blob, JsonBlob } from './JsonBlob';
import { UserdataV6 } from './UserdataV6';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG: string = 'UserdataLocalStore';
const STORE_FILE_VERSION: number = 1;

/** 落盘结构（一 sid 一文件；cache/current 直接存 JSON 文本，避免嵌套序列化边界问题）。 */
interface UserDataStoreFile {
  v?: number;
  cacheJson?: string;
  currentJson?: string;
  pendingKeys?: string[];
  pend?: boolean;
  lastPullAt?: number;
  holdUntil?: number;
  syncEnabled?: boolean;
}

/**
 * userdata 本机持久层（按 sid 隔离）。
 *
 * - `cache`  = 最近一次合并结果（脏检测基线）；
 * - `current`= 本机各 section 当前值（业务层写入）；
 * - `pend` + `pendingKeys` = 待补发标记；
 * - `lastPullAt` = 上次成功拉取时间（60s TTL）；`holdUntil` = 清除云端后的抑制期；`syncEnabled` = 云同步开关。
 */
export interface UserdataLocalStore {
  readCache(): Promise<Blob | undefined>;

  writeCache(blob: Blob): Promise<void>;

  readCurrent(): Promise<Blob>;

  writeCurrent(sections: Blob): Promise<void>;

  pend(): Promise<boolean>;

  setPend(value: boolean): Promise<void>;

  pendingKeys(): Promise<Set<string>>;

  markPending(keys: string[]): Promise<void>;

  clearPending(): Promise<void>;

  lastPullAt(): Promise<number>;

  setLastPullAt(at: number): Promise<void>;

  holdUntil(): Promise<number>;

  setHoldUntil(at: number): Promise<void>;

  syncEnabled(): Promise<boolean>;

  setSyncEnabled(enabled: boolean): Promise<void>;

  clear(): Promise<void>;
}

/** 内存实现：单测 / 预览用。 */
export class InMemoryUserdataLocalStore implements UserdataLocalStore {
  private cache: Blob | undefined = undefined;
  private current: Blob = {};
  private pendFlag: boolean = false;
  private pending: Set<string> = new Set<string>();
  private lastPull: number = 0;
  private hold: number = 0;
  private enabled: boolean = true;

  async readCache(): Promise<Blob | undefined> {
    return this.cache;
  }

  async writeCache(blob: Blob): Promise<void> {
    this.cache = blob;
  }

  async readCurrent(): Promise<Blob> {
    return this.current;
  }

  async writeCurrent(sections: Blob): Promise<void> {
    this.current = sections;
  }

  async pend(): Promise<boolean> {
    return this.pendFlag;
  }

  async setPend(value: boolean): Promise<void> {
    this.pendFlag = value;
  }

  async pendingKeys(): Promise<Set<string>> {
    return this.pending;
  }

  async markPending(keys: string[]): Promise<void> {
    this.pendFlag = true;
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].length > 0) {
        this.pending.add(keys[i]);
      }
    }
  }

  async clearPending(): Promise<void> {
    this.pendFlag = false;
    this.pending = new Set<string>();
  }

  async lastPullAt(): Promise<number> {
    return this.lastPull;
  }

  async setLastPullAt(at: number): Promise<void> {
    this.lastPull = at;
  }

  async holdUntil(): Promise<number> {
    return this.hold;
  }

  async setHoldUntil(at: number): Promise<void> {
    this.hold = at;
  }

  async syncEnabled(): Promise<boolean> {
    return this.enabled;
  }

  async setSyncEnabled(enabled: boolean): Promise<void> {
    this.enabled = enabled;
  }

  async clear(): Promise<void> {
    this.cache = undefined;
    this.current = {};
    this.pendFlag = false;
    this.pending = new Set<string>();
    this.lastPull = 0;
    this.hold = 0;
  }
}

/**
 * 文件实现：`<filesDir>/userdata/userdata_<sid>.json`。
 *
 * 不用 preferences：blob 可能超过 preferences 的单值上限。文件很小（<几十 KB），同步读写可接受；
 * 写入失败静默（本机缓存语义：失败不影响业务，下一次再写）。
 */
export class FileUserdataLocalStore implements UserdataLocalStore {
  private directory: string = '';
  private sidProvider: () => string;

  constructor(sidProvider: () => string, directory: string = '') {
    this.sidProvider = sidProvider;
    this.directory = directory;
  }

  private dir(): string {
    if (this.directory.length > 0) {
      return this.directory;
    }
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return '';
    }
    return ctx.filesDir + '/userdata';
  }

  private currentSid(): string {
    return this.sidProvider().trim();
  }

  private pathFor(sid: string): string {
    const safe: string = sid.replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '');
    return this.dir() + '/userdata_' + safe + '.json';
  }

  private readFile(): UserDataStoreFile {
    const sid: string = this.currentSid();
    if (sid.length === 0) {
      return {};
    }
    const dir: string = this.dir();
    if (dir.length === 0) {
      return {};
    }
    const path: string = this.pathFor(sid);
    try {
      if (!fs.accessSync(path)) {
        return {};
      }
      const text: string = fs.readTextSync(path);
      if (text.length === 0) {
        return {};
      }
      return JSON.parse(text) as UserDataStoreFile;
    } catch (e) {
      Log.w(TAG, '读取本机 userdata 失败');
      return {};
    }
  }

  private writeFile(next: UserDataStoreFile): void {
    const sid: string = this.currentSid();
    const dir: string = this.dir();
    if (sid.length === 0 || dir.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      next.v = STORE_FILE_VERSION;
      const file = fs.openSync(this.pathFor(sid),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(next));
      fs.closeSync(file);
    } catch (e) {
      Log.w(TAG, '写入本机 userdata 失败');
    }
  }

  async readCache(): Promise<Blob | undefined> {
    const file: UserDataStoreFile = this.readFile();
    if (file.cacheJson === undefined || file.cacheJson.length === 0) {
      return undefined;
    }
    return UserdataV6.decode(file.cacheJson);
  }

  async writeCache(blob: Blob): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.cacheJson = UserdataV6.encode(blob);
    this.writeFile(file);
  }

  async readCurrent(): Promise<Blob> {
    const file: UserDataStoreFile = this.readFile();
    if (file.currentJson === undefined || file.currentJson.length === 0) {
      return {};
    }
    const parsed: Blob | undefined = JsonBlob.parse(file.currentJson);
    return parsed !== undefined ? parsed : {};
  }

  async writeCurrent(sections: Blob): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.currentJson = JsonBlob.encode(sections);
    this.writeFile(file);
  }

  async pend(): Promise<boolean> {
    return this.readFile().pend === true;
  }

  async setPend(value: boolean): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.pend = value;
    this.writeFile(file);
  }

  async pendingKeys(): Promise<Set<string>> {
    const file: UserDataStoreFile = this.readFile();
    const keys: string[] = file.pendingKeys !== undefined ? file.pendingKeys : [];
    const set: Set<string> = new Set<string>();
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].length > 0) {
        set.add(keys[i]);
      }
    }
    return set;
  }

  async markPending(keys: string[]): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    const existing: string[] = file.pendingKeys !== undefined ? file.pendingKeys : [];
    const merged: string[] = [];
    for (let i = 0; i < existing.length; i++) {
      merged.push(existing[i]);
    }
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].length > 0 && merged.indexOf(keys[i]) < 0) {
        merged.push(keys[i]);
      }
    }
    file.pend = true;
    file.pendingKeys = merged;
    this.writeFile(file);
  }

  async clearPending(): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.pend = false;
    file.pendingKeys = [];
    this.writeFile(file);
  }

  async lastPullAt(): Promise<number> {
    const value: number | undefined = this.readFile().lastPullAt;
    return value !== undefined ? value : 0;
  }

  async setLastPullAt(at: number): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.lastPullAt = at;
    this.writeFile(file);
  }

  async holdUntil(): Promise<number> {
    const value: number | undefined = this.readFile().holdUntil;
    return value !== undefined ? value : 0;
  }

  async setHoldUntil(at: number): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.holdUntil = at;
    this.writeFile(file);
  }

  async syncEnabled(): Promise<boolean> {
    const value: boolean | undefined = this.readFile().syncEnabled;
    return value !== false;
  }

  async setSyncEnabled(enabled: boolean): Promise<void> {
    const file: UserDataStoreFile = this.readFile();
    file.syncEnabled = enabled;
    this.writeFile(file);
  }

  async clear(): Promise<void> {
    const sid: string = this.currentSid();
    const dir: string = this.dir();
    if (sid.length === 0 || dir.length === 0) {
      return;
    }
    try {
      const path: string = this.pathFor(sid);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      Log.w(TAG, '清除本机 userdata 失败');
    }
  }
}
