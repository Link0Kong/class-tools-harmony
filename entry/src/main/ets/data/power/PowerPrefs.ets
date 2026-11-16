import { Blob, JsonBlob } from '../sync/JsonBlob';
import { PowerRooms, PowerStats } from './PowerModels';

/** `userdata.power` 快照（v6 顶层键 `power`，整段 LWW）。 */
export class PowerPrefsData {
  sel: string = '';
  at: number = 0;
  low: number = PowerStats.defaultLow();
}

/** 电费偏好读写（`power = {sel, at, low}`）。 */
export class PowerPrefs {
  static read(sections: Blob): PowerPrefsData {
    const data: PowerPrefsData = new PowerPrefsData();
    const section: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'power'));
    if (section === undefined) {
      return data;
    }
    data.sel = PowerRooms.normalizeSel(JsonBlob.asString(JsonBlob.get(section, 'sel'), ''));
    data.at = JsonBlob.asNumber(JsonBlob.get(section, 'at'), 0);
    data.low = PowerStats.normalizeLow(JsonBlob.asNumber(JsonBlob.get(section, 'low'), PowerStats.defaultLow()));
    return data;
  }

  /** 写回：只改 power 段，其余键原样保留。 */
  static write(current: Blob, sel: string, low: number, nowMillis: number): Blob {
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const section: Blob = {};
    section['sel'] = PowerRooms.normalizeSel(sel);
    section['at'] = nowMillis;
    section['low'] = PowerStats.normalizeLow(low);
    next['power'] = section;
    return next;
  }

  /** 低电判定：q < 阈值（无值不算低电）。 */
  static isLow(q: number, hasValue: boolean, low: number): boolean {
    return hasValue && q < low;
  }
}
