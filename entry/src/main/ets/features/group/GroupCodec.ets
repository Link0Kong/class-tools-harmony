import { Blob, JsonBlob, JsonValue } from '../../data/sync/JsonBlob';
import { GroupConfig, GroupMode, groupModeFromWire, GroupSource, groupSourceFromWire } from './GroupModels';

/**
 * `userdata.group` section 编解码（契约 USERDATA_V6.md §1.2）：
 *
 * `{ "source": "prev", "mode": "groups", "n": 4, "shuffle": false, "sel": [1,3,5] }`
 *
 * 规则：source 兼容 `pick/paste/roster` → names；mode 兼容 `per/size` → pergroup；
 * `sel` 只保留 1..99 整数、去重升序；未知字段写入时原样保留。
 */
export class GroupConfigCodec {
  static fromJson(section: JsonValue | undefined): GroupConfig {
    const obj: Blob | undefined = JsonBlob.asBlob(section);
    const config: GroupConfig = new GroupConfig();
    if (obj === undefined) {
      return config;
    }
    config.source = groupSourceFromWire(JsonBlob.asString(JsonBlob.get(obj, 'source'), ''));
    config.mode = groupModeFromWire(JsonBlob.asString(JsonBlob.get(obj, 'mode'), ''));
    const n: number = JsonBlob.asNumber(JsonBlob.get(obj, 'n'), GroupConfig.DEFAULT_N);
    config.n = Math.round(n);
    config.shuffle = GroupConfigCodec.readBool(JsonBlob.get(obj, 'shuffle'));
    config.selectedSeats = GroupConfigCodec.readSeats(JsonBlob.get(obj, 'sel'));
    return config;
  }

  /** 输出固定字段顺序（source/mode/n/shuffle/sel），保留未知字段（如以后新增的字段）。 */
  static toJson(config: GroupConfig, existing?: Blob): Blob {
    const seats: number[] = GroupConfigCodec.normalizeSeats(config.selectedSeats);
    const out: Blob = {
      'source': config.source,
      'mode': config.mode,
      'n': Math.round(config.n),
      'shuffle': config.shuffle,
      'sel': GroupConfigCodec.seatsToObjects(seats)
    };
    if (existing !== undefined) {
      const keys: string[] = JsonBlob.keys(existing);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        if (JsonBlob.get(out, key) === undefined) {
          out[key] = existing[key];
        }
      }
    }
    return out;
  }

  static empty(): Blob {
    return GroupConfigCodec.toJson(new GroupConfig());
  }

  static normalizeSeats(seats: number[]): number[] {
    const set: Set<number> = new Set<number>();
    for (let i = 0; i < seats.length; i++) {
      const seat: number = Math.round(seats[i]);
      if (seat >= 1 && seat <= 99) {
        set.add(seat);
      }
    }
    const out: number[] = [];
    set.forEach((seat: number) => {
      out.push(seat);
    });
    out.sort((a: number, b: number) => a - b);
    return out;
  }

  /** 兼容 true 与字符串 "true"（小程序旧数据把 bool 存成字符串）。 */
  private static readBool(value: JsonValue | undefined): boolean {
    if (typeof value === 'boolean') {
      return value as boolean;
    }
    if (typeof value === 'string') {
      return (value as string).toLowerCase() === 'true';
    }
    return false;
  }

  private static readSeats(value: JsonValue | undefined): number[] {    const array: Object[] | undefined = JsonBlob.asArray(value);
    if (array === undefined) {
      return [];
    }
    const seats: number[] = [];
    for (let i = 0; i < array.length; i++) {
      const raw: JsonValue | undefined = array[i];
      let seat: number = Number.NaN;
      if (typeof raw === 'number') {
        seat = raw as number;
      } else if (typeof raw === 'string') {
        seat = Number((raw as string).trim());
      }
      if (Number.isFinite(seat)) {
        seats.push(Math.round(seat));
      }
    }
    return GroupConfigCodec.normalizeSeats(seats);
  }

  private static seatsToObjects(seats: number[]): Object[] {
    const out: Object[] = [];
    for (let i = 0; i < seats.length; i++) {
      out.push(seats[i]);
    }
    return out;
  }
}
