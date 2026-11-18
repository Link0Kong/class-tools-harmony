import { JsonBlob, Blob } from '../sync/JsonBlob';

/** 隐藏项（仅自己不可见，跨端同步）：作业 hwHide / 通知 ntHide。 */
export class HideData {
  hwHide: Set<string> = new Set<string>();
  ntHide: Set<string> = new Set<string>();
}

/** userdata.hide 段读写（保留未知字段，与网页 D.d.hwHide/ntHide 同结构）。 */
export class HidePrefs {
  static read(sections: Blob): HideData {
    const data: HideData = new HideData();
    const hide: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'hide'));
    if (hide === undefined) {
      return data;
    }
    HidePrefs.collect(JsonBlob.asBlob(JsonBlob.get(hide, 'hwHide')), data.hwHide);
    HidePrefs.collect(JsonBlob.asBlob(JsonBlob.get(hide, 'ntHide')), data.ntHide);
    return data;
  }

  private static collect(blob: Blob | undefined, target: Set<string>): void {
    if (blob === undefined) {
      return;
    }
    const keys: string[] = JsonBlob.keys(blob);
    for (let i = 0; i < keys.length; i++) {
      if (JsonBlob.asBoolean(JsonBlob.get(blob, keys[i]), false)
        || JsonBlob.asString(JsonBlob.get(blob, keys[i]), '') === 'true') {
        target.add(keys[i]);
      }
    }
  }

  /** 写回：复制所有顶层键，仅替换 hide（保留 hide 内未知键）。 */
  static write(current: Blob, data: HideData): Blob {
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const hide: Blob = {};
    const oldHide: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'hide'));
    if (oldHide !== undefined) {
      const oldKeys: string[] = JsonBlob.keys(oldHide);
      for (let i = 0; i < oldKeys.length; i++) {
        if (oldKeys[i] !== 'hwHide' && oldKeys[i] !== 'ntHide') {
          hide[oldKeys[i]] = oldHide[oldKeys[i]];
        }
      }
    }
    hide['hwHide'] = HidePrefs.toBlob(data.hwHide);
    hide['ntHide'] = HidePrefs.toBlob(data.ntHide);
    next['hide'] = hide;
    return next;
  }

  private static toBlob(set: Set<string>): Blob {
    const out: Blob = {};
    set.forEach((id: string) => {
      out[id] = true;
    });
    return out;
  }

  static isHwHidden(sections: Blob, id: string): boolean {
    return HidePrefs.read(sections).hwHide.has(id);
  }

  static isNtHidden(sections: Blob, id: string): boolean {
    return HidePrefs.read(sections).ntHide.has(id);
  }
}
