import { Blob, JsonBlob, JsonValue } from './JsonBlob';
import { UserdataV6 } from './UserdataV6';

/**
 * userdata v6 合并算法（纯函数，与 `mp-class-tools-tests/_sync_fixtures/merge_ref.js` 逐字节等价）。
 *
 * 规则（契约 §4 / docs/api/USERDATA_V6.md §2/§6）：
 * - 逐 section 比较 `at`，`remote.at[k] >= local.at[k]` 时云端赢（相等云端赢 = 幂等收敛）；
 * - 值是否参与比较用「非 null」判定；
 * - 双方都无 → DEFAULTS[k] + at=0；
 * - 输出固定顺序 `v, at, <11 sections>, homeToolsAt`，且 `homeToolsAt = at.homeTools`；
 * - `v=5` 先归一为 v6 再合并。
 */
export class UserdataMerge {
  /** 与 merge_ref.js `mergeBlob()` 等价。 */
  static merge(remoteIn: Blob | undefined, localIn: Blob | undefined): Blob {
    let remote: Blob | undefined = remoteIn;
    if (remoteIn !== undefined && UserdataV6.numMs(JsonBlob.get(remoteIn, 'v')) === 5) {
      remote = UserdataMerge.normalizeV5(remoteIn);
    }

    const values: Blob = {};
    const atOut: Blob = {};

    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      const ra: number = UserdataV6.atValue(remote, key);
      const la: number = UserdataV6.atValue(localIn, key);
      const remoteValue: JsonValue | undefined = withoutNull(JsonBlob.get(remote, key));
      const localValue: JsonValue | undefined = withoutNull(JsonBlob.get(localIn, key));
      if (remoteValue !== undefined && (localValue === undefined || ra >= la)) {
        values[key] = remoteValue;
        atOut[key] = ra;
      } else if (localValue !== undefined) {
        values[key] = localValue;
        atOut[key] = la;
      } else {
        values[key] = UserdataV6.defaultSection(key);
        atOut[key] = 0;
      }
    }

    const out: Blob = {};
    out['v'] = UserdataV6.VERSION;
    out['at'] = atOut;
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      out[key] = values[key];
    }
    out['homeToolsAt'] = UserdataV6.numMs(JsonBlob.get(atOut, 'homeTools'));
    return out;
  }

  /** 与 merge_ref.js `normalizeV5()` 等价。 */
  static normalizeV5(old: Blob): Blob {
    const at: Blob = {};
    at['homeTools'] = UserdataV6.numMs(JsonBlob.get(old, 'homeToolsAt'));
    at['fit'] = 0;

    const out: Blob = {};
    out['v'] = UserdataV6.VERSION;
    out['at'] = at;
    const homeTools: JsonValue | undefined = JsonBlob.asArray(JsonBlob.get(old, 'homeTools'));
    if (homeTools !== undefined) {
      out['homeTools'] = homeTools;
    }
    const fit: JsonValue | undefined = JsonBlob.asBlob(JsonBlob.get(old, 'fit'));
    if (fit !== undefined) {
      out['fit'] = fit;
    }
    return out;
  }

  /**
   * 本机视图（push 的 local 输入），与 web `UD.localView` / mp `udSections()+udOwnedDirty` 等价。
   *
   * - 拥有的 section 取本机当前值；不拥有的从「最近合并基线」原样带上；
   * - 与基线不同 = 脏 → at = max(now, base.at+1, remote.at+1)；
   * - forceKeys 显式强制为脏；
   * - power.at 镜像 at.power；
   * - 输出固定顺序。
   */
  static localView(base: Blob | undefined, current: Blob, remote: Blob | undefined,
    forceKeys: Set<string>, now: number, ownedSections: Set<string>): Blob {
    const values: Blob = {};
    const atOut: Blob = {};

    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      const owned: boolean = ownedSections.has(key);
      const currentValue: JsonValue | undefined = withoutNull(JsonBlob.get(current, key));
      const baseValue: JsonValue | undefined = withoutNull(JsonBlob.get(base, key));

      let value: JsonValue = null;
      if (owned && currentValue !== undefined) {
        value = currentValue;
      } else if (!owned) {
        value = baseValue !== undefined ? baseValue : UserdataV6.defaultSection(key);
      } else {
        value = UserdataV6.defaultSection(key);
      }

      const ba: number = UserdataV6.atValue(base, key);
      const ra: number = UserdataV6.atValue(remote, key);
      // 无基线（base===undefined）时不算脏：先 pull 建基线，避免默认值覆盖云端（契约 §4.4-5）
      let dirty: boolean = owned && base !== undefined && (baseValue === undefined || !JsonBlob.deepEqual(baseValue, value));
      if (owned && forceKeys.has(key)) {
        dirty = true;
      }
      let la: number = ba;
      if (dirty) {
        la = Math.max(now, ba + 1, ra + 1);
      }

      values[key] = value;
      atOut[key] = la;
    }

    // power 值内 at 与 at.power 镜像（契约 §1.3）
    const power: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(values, 'power'));
    if (power !== undefined) {
      const mirrored: Blob = {};
      const keys: string[] = JsonBlob.keys(power);
      for (let i = 0; i < keys.length; i++) {
        mirrored[keys[i]] = power[keys[i]];
      }
      mirrored['at'] = UserdataV6.numMs(JsonBlob.get(atOut, 'power'));
      values['power'] = mirrored;
    }

    const out: Blob = {};
    out['v'] = UserdataV6.VERSION;
    out['at'] = atOut;
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      out[key] = values[key];
    }
    out['homeToolsAt'] = UserdataV6.numMs(JsonBlob.get(atOut, 'homeTools'));
    return out;
  }

  /** 脏 section：本机当前值与基线不同（含「基线缺该键」= 脏），只考虑 ownedSections。 */
  static dirtySections(base: Blob | undefined, current: Blob, ownedSections: Set<string>): Set<string> {
    const dirty: Set<string> = new Set<string>();
    if (base === undefined) {
      return dirty;
    }
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      if (!ownedSections.has(key)) {
        continue;
      }
      const baseValue: JsonValue | undefined = withoutNull(JsonBlob.get(base, key));
      const currentRaw: JsonValue | undefined = withoutNull(JsonBlob.get(current, key));
      const currentValue: JsonValue = currentRaw !== undefined ? currentRaw : UserdataV6.defaultSection(key);
      if (baseValue === undefined || !JsonBlob.deepEqual(baseValue, currentValue)) {
        dirty.add(key);
      }
    }
    return dirty;
  }

  /** 无基线时判断「哪些 section 与默认值不同」= 本机真实改动（跳过 prefs，避免默认偏好覆盖云端）。 */
  static changedKeysVsDefaults(current: Blob, ownedSections: Set<string>): Set<string> {
    const changed: Set<string> = new Set<string>();
    for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
      const key: string = UserdataV6.SECTION_KEYS[i];
      if (!ownedSections.has(key) || key === 'prefs') {
        continue;
      }
      const raw: JsonValue | undefined = withoutNull(JsonBlob.get(current, key));
      const value: JsonValue = raw !== undefined ? raw : UserdataV6.defaultSection(key);
      if (!JsonBlob.deepEqual(value, UserdataV6.defaultSection(key))) {
        changed.add(key);
      }
    }
    return changed;
  }
}

/** JSON 值是否参与比较：null 与缺失等价（契约用「非 null」判定）。 */
function withoutNull(value: JsonValue | undefined): JsonValue | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }
  return value;
}
