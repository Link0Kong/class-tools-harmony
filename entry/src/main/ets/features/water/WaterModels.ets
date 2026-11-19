/** 计费规则常量（网页/小程序同值；页面唯一来源）。 */
export class WaterRules {
  /** 电 0.58 元/度。 */
  static readonly ELEC_PRICE: number = 0.58;
  /** 水 3.03 元/吨（无阶梯、无加价）。 */
  static readonly WATER_PRICE: number = 3.03;
  /** 免费水量 2 吨/人/月。 */
  static readonly WATER_FREE_PER_PERSON: number = 2.0;
  /** 免费电量 5 度/人/月（展示用）。 */
  static readonly ELEC_FREE_PER_PERSON: number = 5.0;
  static readonly PERSONS_DEFAULT: number = 4;
  static readonly PERSONS_OPTIONS: number[] = [1, 2, 3, 4, 5, 6];
  static readonly MAX_RECORDS_PER_ROOM: number = 120;
  static readonly CYCLE_MONTHS: number = 10;

  /** 1 吨水折合扣电（≈5.2241 度）。 */
  static tonToDegree(): number {
    return WaterRules.WATER_PRICE / WaterRules.ELEC_PRICE;
  }
}

/** 一条抄表记录。 */
export class WaterRecord {
  month: string = '';
  reading: number = 0;
  ts: number = 0;
}

/** 一间宿舍的水量状态。 */
export class WaterRoomState {
  persons: number = WaterRules.PERSONS_DEFAULT;
  records: WaterRecord[] = [];

  latest(): WaterRecord | undefined {
    return this.records.length > 0 ? this.records[this.records.length - 1] : undefined;
  }
}

/** 整个 water section。 */
export class WaterState {
  rooms: Map<string, WaterRoomState> = new Map<string, WaterRoomState>();

  room(roomVerify: string): WaterRoomState | undefined {
    return this.rooms.get(roomVerify.trim());
  }

  roomOrDefault(roomVerify: string): WaterRoomState {
    const found: WaterRoomState | undefined = this.room(roomVerify);
    return found !== undefined ? found : new WaterRoomState();
  }

  recordOf(roomVerify: string, month: string): WaterRecord | undefined {
    const room: WaterRoomState | undefined = this.room(roomVerify);
    if (room === undefined) {
      return undefined;
    }
    for (let i = 0; i < room.records.length; i++) {
      if (room.records[i].month === month) {
        return room.records[i];
      }
    }
    return undefined;
  }

  /** 深拷贝（避免共享引用）。 */
  copy(): WaterState {
    const next: WaterState = new WaterState();
    this.rooms.forEach((room: WaterRoomState, key: string) => {
      const roomCopy: WaterRoomState = new WaterRoomState();
      roomCopy.persons = room.persons;
      for (let i = 0; i < room.records.length; i++) {
        roomCopy.records.push(cloneRecord(room.records[i]));
      }
      next.rooms.set(key, roomCopy);
    });
    return next;
  }
}

/** 一次抄表读数/水费计算。 */
export class WaterCharge {
  usage: number = 0;
  hasUsage: boolean = false;
  free: number = 0;
  excess: number = 0;
  fee: number = 0;
  degree: number = 0;
  within: boolean = false;
  hasPrevious: boolean = false;
}

/** 某个月份的统计。 */
export class WaterMonthStats {
  month: string = '';
  persons: number = WaterRules.PERSONS_DEFAULT;
  record: WaterRecord | undefined = undefined;
  previous: WaterRecord | undefined = undefined;
  charge: WaterCharge = new WaterCharge();
  dailyAverage: number = 0;
  hasDailyAverage: boolean = false;
  previousMonthUsage: number = 0;
  hasPreviousMonthUsage: boolean = false;
  deltaVsPreviousMonth: number = 0;
  hasDelta: boolean = false;
}

/** 抄表校验结果。 */
export class WaterRecordReview {
  valid: boolean = false;
  message: string = '';
  record: WaterRecord | undefined = undefined;
  replaceExisting: boolean = false;
}

export function cloneRecord(record: WaterRecord): WaterRecord {
  const copy: WaterRecord = new WaterRecord();
  copy.month = record.month;
  copy.reading = record.reading;
  copy.ts = record.ts;
  return copy;
}
