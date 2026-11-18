import { describe, it, expect } from '@ohos/hypium';
import { ClassMember } from '../main/ets/data/member/ClassMember';
import {
  RollCodec,
  RollCounts,
  RollLogic,
  RollRow,
  RollScope,
  RollState,
  RollStatus
} from '../main/ets/features/roll/RollModels';
import { Blob } from '../main/ets/data/sync/JsonBlob';

function member(seat: number, name: string, role: string, badge: string): ClassMember {
  return new ClassMember(seat, 'sid' + seat, name, role, badge, false);
}

function members(): ClassMember[] {
  return [
    member(3, '丙', '班长', '班委'),
    member(1, '甲', '', ''),
    member(2, '乙', '', '班委'),
    member(4, '丁', '', '')
  ];
}

export default function rollTest() {
  describe('RollCodec', () => {
    it('reads_roll_fields_and_preserves_others', 0, () => {
      const sections: Blob = JSON.parse('{"roster":{"rosterSel":[1,2],"groupSel":[3],"rollSel":[2,3],'
        + '"rollNames":"名单","rollSt":{"1":"到","2":"假","3":"x","0":"到"}},'
        + '"power":{"sel":"4-23A---321","low":30},"draw":{"count":3}}') as Blob;
      const state: RollState = RollCodec.read(sections);
      expect(state.rollSel.join(',')).assertEqual('2,3');
      expect(state.rosterSel.join(',')).assertEqual('1,2');
      expect(state.groupSel.join(',')).assertEqual('3');
      expect(state.rollSt.size).assertEqual(2);
      expect(state.rollSt.get(1)).assertEqual('到');
      expect(state.rollSt.get(2)).assertEqual('假');
      expect(state.rollSt.get(3) === undefined).assertTrue();
    });

    it('writes_roll_fields_keeping_other_data', 0, () => {
      const sections: Blob = JSON.parse('{"roster":{"rosterSel":[5],"rollSel":[1],"rollSt":{}},'
        + '"power":{"sel":"x"},"v":6}') as Blob;
      const state: RollState = RollCodec.read(sections);
      state.rollSt.set(1, '到');
      state.rollSt.set(2, '假');
      const next: Blob = RollCodec.write(sections, state);
      const nextRoster: Blob | undefined = next['roster'] as Blob;
      expect(nextRoster !== undefined).assertTrue();
      const rollSt: Blob | undefined = nextRoster['rollSt'] as Blob;
      expect(rollSt !== undefined).assertTrue();
      expect(Object.keys(rollSt).sort().join(',')).assertEqual('1,2');
      expect((nextRoster['rosterSel'] as number[]).join(',')).assertEqual('5');
      expect((next['power'] as Blob)['sel']).assertEqual('x');
      expect(next['v']).assertEqual(6);
    });
  });

  describe('RollLogic', () => {
    it('scope_seats', 0, () => {
      expect(RollLogic.scopeSeats(members(), [1, 4], RollScope.ALL).size).assertEqual(0);
      const committee: Set<number> = RollLogic.scopeSeats(members(), [1, 4], RollScope.COMMITTEE);
      expect(committee.has(3)).assertTrue();
      expect(committee.has(2)).assertTrue();
      expect(committee.has(1)).assertFalse();
      const league: Set<number> = RollLogic.scopeSeats(members(), [1, 4], RollScope.LEAGUE);
      expect(league.has(4)).assertTrue();
      expect(league.has(3)).assertFalse();
    });

    it('rows_pending_first_then_processed', 0, () => {
      const statuses: Map<number, string> = new Map<number, string>();
      statuses.set(3, '到');
      statuses.set(1, '假');
      const rows: RollRow[] = RollLogic.rows(members(), statuses, new Set<number>());
      expect(rows.length).assertEqual(4);
      expect(rows[0].seat).assertEqual(2);
      expect(rows[1].seat).assertEqual(4);
      expect(rows[2].processed).assertTrue();
      expect(rows[3].processed).assertTrue();
      expect(rows[2].seat).assertEqual(1);
    });

    it('counts_and_progress', 0, () => {
      const rows: RollRow[] = [];
      const done: RollRow = new RollRow();
      done.seat = 1;
      done.status = RollStatus.DONE;
      rows.push(done);
      const absent: RollRow = new RollRow();
      absent.seat = 2;
      absent.status = RollStatus.ABSENT;
      rows.push(absent);
      const pending: RollRow = new RollRow();
      pending.seat = 3;
      rows.push(pending);
      const counts: RollCounts = RollLogic.counts(rows);
      expect(counts.done).assertEqual(1);
      expect(counts.absent).assertEqual(1);
      expect(counts.pending).assertEqual(1);
      expect(counts.total).assertEqual(3);
      expect(counts.progress()).assertEqual(67);
      expect(RollLogic.counts([]).progress()).assertEqual(0);
    });

    it('toggle_and_clear', 0, () => {
      let statuses: Map<number, string> = new Map<number, string>();
      statuses = RollLogic.toggle(statuses, 1, '到');
      expect(statuses.get(1)).assertEqual('到');
      statuses = RollLogic.toggle(statuses, 1, '到');
      expect(statuses.get(1) === undefined).assertTrue();
      statuses = RollLogic.toggle(statuses, 1, '到');
      statuses = RollLogic.toggle(statuses, 2, '假');
      statuses = RollLogic.toggle(statuses, 3, '到');
      const scope: Set<number> = new Set<number>();
      scope.add(1);
      scope.add(2);
      const cleared: Map<number, string> = RollLogic.clear(statuses, scope);
      expect(cleared.size).assertEqual(1);
      expect(cleared.get(3)).assertEqual('到');
      expect(RollLogic.clear(statuses, new Set<number>()).size).assertEqual(0);
    });

    it('intersect_custom_roster', 0, () => {
      const scope: Set<number> = new Set<number>();
      scope.add(1);
      scope.add(2);
      scope.add(3);
      expect(RollLogic.intersect(scope, []).size).assertEqual(3);
      expect(RollLogic.intersect(scope, [2]).size).assertEqual(1);
      expect(RollLogic.intersect(scope, [2, 9]).size).assertEqual(1);
      expect(RollLogic.intersect(new Set<number>(), [5, 6]).size).assertEqual(2);
    });

    it('writes_roll_sel', 0, () => {
      const sections: Blob = JSON.parse('{"roster":{"rollSel":[],"rollSt":{}},"v":6}') as Blob;
      const state: RollState = RollCodec.read(sections);
      state.rollSel = [3, 5];
      const next: Blob = RollCodec.write(sections, state);
      const roster: Blob | undefined = next['roster'] as Blob;
      const seats: Object[] | undefined = roster['rollSel'] as Object[];
      expect(seats !== undefined && seats.length === 2).assertTrue();
    });

    it('names_of_status', 0, () => {
      const rows: RollRow[] = RollLogic.rows(members(), new Map<number, string>(), new Set<number>());
      rows[0].status = '假';
      expect(RollLogic.namesOf(rows, '假').length).assertEqual(1);
      expect(RollLogic.namesOf(rows, '').length).assertEqual(3);
    });
  });
}
