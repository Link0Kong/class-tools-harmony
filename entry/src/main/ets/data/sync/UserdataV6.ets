import { Blob, JsonBlob, JsonValue } from './JsonBlob';

/**
 * `userdata` v6 blob 结构与默认值（契约：BACKEND_CONTRACT.md §4 + mp `utils/privacy.js` DEFAULTS）。
 *
 * 顶层 14 键固定顺序：`v, at, homeTools, fit, draw, group, roster, hide, tt, prefs, nick, power, water, homeToolsAt`。
 * 11 个 section 的顺序即合并输出顺序，必须与 web `UD_KEYS` / mp `SECTION_KEYS` / `merge_ref.js` 完全一致。
 */
export class UserdataV6 {
  static readonly VERSION: number = 6;

  static readonly SECTION_KEYS: string[] = [
    'homeTools', 'fit', 'draw', 'group', 'roster', 'hide', 'tt', 'prefs', 'nick', 'power', 'water'
  ];

  static readonly TOP_LEVEL_KEYS: string[] = [
    'v', 'at', 'homeTools', 'fit', 'draw', 'group', 'roster', 'hide', 'tt', 'prefs', 'nick', 'power', 'water',
    'homeToolsAt'
  ];

  /** 某 section 的默认值（与 merge_ref.js DEFAULTS 逐字段一致）。 */
  static defaultSection(key: string): JsonValue {
    if (key === 'homeTools') {
      const arr: Object[] = [];
      return arr;
    }
    if (key === 'fit' || key === 'group') {
      const empty: Blob = {};
      return empty;
    }
    if (key === 'draw') {
      // 2026-11-12 抽签升级 v1：draw section 内新增 names 字段（空 = 未设置），不新增顶层键
      const draw: Blob = { 'names': '' };
      return draw;
    }
    if (key === 'roster') {
      const rosterSel: Object[] = [];
      const rollSel: Object[] = [];
      const rollSt: Blob = {};
      const roster: Blob = {
        'rosterSel': rosterSel,
        'rollSel': rollSel,
        'rollSt': rollSt,
        'rollNames': ''
      };
      return roster;
    }
    if (key === 'hide') {
      const hwHide: Blob = {};
      const ntHide: Blob = {};
      const hide: Blob = { 'hwHide': hwHide, 'ntHide': ntHide };
      return hide;
    }
    if (key === 'tt') {
      const tt: Blob = { 'ttView': '', 'ttUseMine': false, 'ttLocal': null, 'termStart': '' };
      return tt;
    }
    if (key === 'prefs') {
      const hwRemind: Blob = {};
      const prefs: Blob = { 'hwRemind': hwRemind, 'ntSub': false, 'ntSubAt': 0 };
      return prefs;
    }
    if (key === 'nick') {
      return '';
    }
    if (key === 'power') {
      const power: Blob = { 'sel': '', 'at': 0, 'low': 30 };
      return power;
    }
    if (key === 'water') {
      const rooms: Blob = {};
      const water: Blob = { 'rooms': rooms };
      return water;
    }
    return null;
  }

  /** 空 v6 blob（等价 mp `privacy.emptyV6()`：清除云端副本/初始化基线用）。 */
  static empty(): Blob {
    const at: Blob = {};
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      at[UserdataV6.SECTION_KEYS[i]] = 0;
    }
    const out: Blob = {};
    out['v'] = UserdataV6.VERSION;
    out['at'] = at;
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      out[key] = UserdataV6.defaultSection(key);
    }
    out['homeToolsAt'] = 0;
    return out;
  }

  static emptyBlobText(): string {
    return JsonBlob.encode(UserdataV6.empty());
  }

  /** 坏 JSON / 非对象 → undefined（视为无云端数据，不覆盖本机）。 */
  static decode(text: string | undefined): Blob | undefined {
    if (text === undefined) {
      return undefined;
    }
    return JsonBlob.parse(text);
  }

  static encode(blob: Blob): string {
    return JsonBlob.encode(blob);
  }

  /** 只保留 11 个 section 的值（去掉 v/at/homeToolsAt）。 */
  static sectionsOf(blob: Blob | undefined): Blob {
    const out: Blob = {};
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      const value: JsonValue | undefined = JsonBlob.get(blob, key);
      if (value !== undefined) {
        out[key] = value;
      }
    }
    return out;
  }

  static atMap(blob: Blob | undefined): Blob {
    const at: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'at'));
    return at !== undefined ? at : {};
  }

  static atValue(blob: Blob | undefined, key: string): number {
    return JsonBlob.numMs(JsonBlob.get(UserdataV6.atMap(blob), key));
  }

  static numMs(value: JsonValue | undefined): number {
    return JsonBlob.numMs(value);
  }
}
