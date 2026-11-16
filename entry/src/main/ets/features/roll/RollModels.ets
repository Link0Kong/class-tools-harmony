import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { ClassMember } from '../../data/member/ClassMember';

/** 点名状态（到 / 假；空 = 未点）。 */
export class RollStatus {
  static readonly DONE: string = '到';
  static readonly ABSENT: string = '假';
}

/** `userdata.roster` 里的点名相关字段（其余字段原样保留）。 */
export class RollState {
  rollSel: number[] = [];
  rollSt: Map<number, string> = new Map<number, string>();
  rollNames: string = '';
  rosterSel: number[] = [];
  groupSel: number[] = [];
}

/** 点名范围。 */
export enum RollScope {
  ALL = '全班',
  COMMITTEE = '班委',
  LEAGUE = '团员'
}

/** 一行点名记录（UI 用）。 */
export class RollRow {
  seat: number = 0;
  name: string = '';
  status: string = '';
  processed: boolean = false;
}

export class RollCounts {
  done: number = 0;
  absent: number = 0;
  pending: number = 0;
  total: number = 0;

  progress(): number {
    if (this.total <= 0) {
      return 0;
    }
    return Math.round((this.done + this.absent) / this.total * 100);
  }
}

/** `userdata.roster` 点名字段读写（保留 rosterSel/groupSel 等其它字段）。 */
export class RollCodec {
  static read(sections: Blob): RollState {
    const state: RollState = new RollState();
    const roster: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(sections, 'roster'));
    if (roster === undefined) {
      return state;
    }
    state.rollSel = seatsOf(JsonBlob.get(roster, 'rollSel'));
    state.rosterSel = seatsOf(JsonBlob.get(roster, 'rosterSel'));
    state.groupSel = seatsOf(JsonBlob.get(roster, 'groupSel'));
    state.rollNames = JsonBlob.asString(JsonBlob.get(roster, 'rollNames'), '');
    const rollSt: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(roster, 'rollSt'));
    if (rollSt !== undefined) {
      const keys: string[] = JsonBlob.keys(rollSt);
      for (let i = 0; i < keys.length; i++) {
        const seat: number = Number(keys[i]);
        const value: string = JsonBlob.asString(JsonBlob.get(rollSt, keys[i]), '');
        if (Number.isFinite(seat) && seat > 0 && (value === RollStatus.DONE || value === RollStatus.ABSENT)) {
          state.rollSt.set(Math.round(seat), value);
        }
      }
    }
    return state;
  }

  /** 写回：只改 roster 段的点名字段，其它 section/字段原样保留。 */
  static write(current: Blob, state: RollState): Blob {
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const roster: Blob = {};
    const existing: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'roster'));
    if (existing !== undefined) {
      const rosterKeys: string[] = JsonBlob.keys(existing);
      for (let i = 0; i < rosterKeys.length; i++) {
        roster[rosterKeys[i]] = existing[rosterKeys[i]];
      }
    }
    roster['rollSel'] = state.rollSel.slice(0);
    roster['rollNames'] = state.rollNames;
    const rollSt: Blob = {};
    state.rollSt.forEach((value: string, seat: number) => {
      if (value === RollStatus.DONE || value === RollStatus.ABSENT) {
        rollSt['' + seat] = value;
      }
    });
    roster['rollSt'] = rollSt;
    next['roster'] = roster;
    return next;
  }
}

/** 点名纯逻辑。 */
export class RollLogic {
  /** 范围座号（未指定 = 不限）。 */
  static scopeSeats(members: ClassMember[], leagueSeats: number[], scope: RollScope): Set<number> {
    const seats: Set<number> = new Set<number>();
    if (scope === RollScope.ALL) {
      return seats;
    }
    if (scope === RollScope.COMMITTEE) {
      for (let i = 0; i < members.length; i++) {
        if (members[i].isCommittee() || members[i].badge.indexOf('班委') >= 0) {
          seats.add(members[i].seat);
        }
      }
      return seats;
    }
    for (let i = 0; i < leagueSeats.length; i++) {
      seats.add(leagueSeats[i]);
    }
    return seats;
  }

  /** 自定义名单与范围求交（picked 为空 → 范围全量）。 */
  static intersect(scope: Set<number>, picked: number[]): Set<number> {
    const out: Set<number> = new Set<number>();
    if (picked.length === 0) {
      scope.forEach((seat: number) => {
        out.add(seat);
      });
      return out;
    }
    for (let i = 0; i < picked.length; i++) {
      const seat: number = picked[i];
      if (scope.size === 0 || scope.has(seat)) {
        out.add(seat);
      }
    }
    return out;
  }

  /** 生成点名行：未处理在前（按座号），已处理沉底。 */
  static rows(members: ClassMember[], statuses: Map<number, string>, scope: Set<number>): RollRow[] {
    const pending: RollRow[] = [];
    const processed: RollRow[] = [];
    for (let i = 0; i < members.length; i++) {
      const member: ClassMember = members[i];
      if (scope.size > 0 && !scope.has(member.seat)) {
        continue;
      }
      const row: RollRow = new RollRow();
      row.seat = member.seat;
      row.name = member.name;
      const status: string | undefined = statuses.get(member.seat);
      row.status = status !== undefined ? status : '';
      row.processed = row.status.length > 0;
      if (row.processed) {
        processed.push(row);
      } else {
        pending.push(row);
      }
    }
    pending.sort((a: RollRow, b: RollRow) => a.seat - b.seat);
    processed.sort((a: RollRow, b: RollRow) => a.seat - b.seat);
    const out: RollRow[] = [];
    for (let i = 0; i < pending.length; i++) {
      out.push(pending[i]);
    }
    for (let i = 0; i < processed.length; i++) {
      out.push(processed[i]);
    }
    return out;
  }

  static counts(rows: RollRow[]): RollCounts {
    const counts: RollCounts = new RollCounts();
    counts.total = rows.length;
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].status === RollStatus.DONE) {
        counts.done += 1;
      } else if (rows[i].status === RollStatus.ABSENT) {
        counts.absent += 1;
      } else {
        counts.pending += 1;
      }
    }
    return counts;
  }

  /** 切换状态：同状态再点一次 = 取消（返回新 Map）。 */
  static toggle(statuses: Map<number, string>, seat: number, status: string): Map<number, string> {
    const next: Map<number, string> = new Map<number, string>();
    statuses.forEach((value: string, key: number) => {
      next.set(key, value);
    });
    if (next.get(seat) === status) {
      next.delete(seat);
    } else {
      next.set(seat, status);
    }
    return next;
  }

  /** 清空指定范围的已点状态（空范围 = 全清）。 */
  static clear(statuses: Map<number, string>, scope: Set<number>): Map<number, string> {
    const next: Map<number, string> = new Map<number, string>();
    statuses.forEach((value: string, key: number) => {
      if (scope.size > 0 && !scope.has(key)) {
        next.set(key, value);
      }
    });
    return next;
  }

  /** 未到/请假名单（导出用）。 */
  static namesOf(rows: RollRow[], status: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].status === status) {
        out.push(rows[i].name);
      }
    }
    return out;
  }
}

function seatsOf(value: Object | null | undefined): number[] {
  const array: Object[] | undefined = JsonBlob.asArray(value);
  if (array === undefined) {
    return [];
  }
  const seats: number[] = [];
  for (let i = 0; i < array.length; i++) {
    const seat: number = JsonBlob.asNumber(array[i], 0);
    if (Number.isFinite(seat) && seat > 0) {
      const rounded: number = Math.round(seat);
      if (seats.indexOf(rounded) < 0) {
        seats.push(rounded);
      }
    }
  }
  seats.sort((a: number, b: number) => a - b);
  return seats;
}
