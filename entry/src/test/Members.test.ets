import { describe, it, expect } from '@ohos/hypium';
import { FakeApi } from './support/FakeApi';
import { ClassMember, LeagueMember, MemberEntry } from '../main/ets/data/member/ClassMember';
import { MemberCategory, MemberCategoryBuilder, MemberCategoryCounts } from '../main/ets/data/member/MemberCategories';
import {
  ClassMembersRepository,
  ClassMembersResult,
  InMemoryClassMemberCache,
  parseMembers
} from '../main/ets/data/member/ClassMembersRepository';
import { ClassLeagueRepository, ClassLeagueResult, parseLeague } from '../main/ets/data/member/ClassLeagueRepository';
import { Blob } from '../main/ets/data/sync/JsonBlob';

const SID: string = '3260799999';

function memberJson(seat: number, name: string, role: string, badge: string): Blob {
  const out: Blob = {
    'seat': seat,
    'sid': 'sid_' + seat,
    'name': name,
    'role': role,
    'badge': badge,
    'is_admin': false
  };
  return out;
}

function membersBody(rows: Blob[]): string {
  const arr: Object[] = [];
  for (let i = 0; i < rows.length; i++) {
    arr.push(rows[i]);
  }
  return JSON.stringify(arr);
}

function leagueBody(seats: Blob[]): string {
  const arr: Object[] = [];
  for (let i = 0; i < seats.length; i++) {
    arr.push(seats[i]);
  }
  const body: Blob = { 'ok': true, 'count': arr.length, 'seats': arr };
  return JSON.stringify(body);
}

function seatJson(seat: number, name: string): Blob {
  const out: Blob = { 'seat': seat, 'name': name };
  return out;
}

export default function membersTest() {
  describe('ClassMembersParsing', () => {
    it('parse_members_skips_bad_rows', 0, () => {
      const arr: Object[] = [memberJson(1, '张一', '班长', '班委'), memberJson(0, '无座号', '', ''), 'junk'];
      const members: ClassMember[] = parseMembers(JSON.stringify(arr));
      expect(members.length).assertEqual(1);
      expect(members[0].name).assertEqual('张一');
      expect(members[0].isCommittee()).assertTrue();
      expect(parseMembers('not-json').length).assertEqual(0);
    });

    it('parse_league_reads_seats', 0, () => {
      const members: LeagueMember[] | undefined = parseLeague(leagueBody([seatJson(3, '李四'), seatJson(1, '王五')]));
      expect(members !== undefined).assertTrue();
      if (members !== undefined) {
        expect(members.length).assertEqual(2);
        expect(members[0].seat).assertEqual(1);
      }
      expect(parseLeague('{"ok":false}') === undefined).assertTrue();
      expect(parseLeague('') === undefined).assertTrue();
    });
  });

  describe('MemberCategories', () => {
    const classMembers: ClassMember[] = [
      new ClassMember(5, 'sid5', '赵六', '团支书', '班委', false),
      new ClassMember(2, 'sid2', '钱七', '', '班委', false),
      new ClassMember(1, 'sid1', '孙八', '班长', '', false),
      new ClassMember(3, 'sid3', '李九', '', '', false),
      new ClassMember(0, 'sid0', '无效', '', '', false)
    ];
    const league: LeagueMember[] = [
      new LeagueMember(5, '赵六'),
      new LeagueMember(3, '李九'),
      new LeagueMember(3, '李九')
    ];

    it('committee_uses_role_or_badge_and_sorts_by_seat', 0, () => {
      const entries: MemberEntry[] = MemberCategoryBuilder.committee(classMembers);
      expect(entries.length).assertEqual(3);
      expect(entries[0].seat).assertEqual(1);
      expect(entries[0].badge).assertEqual('班长');
      expect(entries[1].seat).assertEqual(2);
      expect(entries[1].badge).assertEqual('班委');
      expect(entries[2].seat).assertEqual(5);
      expect(entries[2].badge).assertEqual('团支书');
    });

    it('all_is_sorted_and_deduped', 0, () => {
      const entries: MemberEntry[] = MemberCategoryBuilder.all(classMembers);
      expect(entries.length).assertEqual(4);
      expect(entries[0].seat).assertEqual(1);
      expect(entries[3].seat).assertEqual(5);
    });

    it('league_dedupes_by_seat', 0, () => {
      const entries: MemberEntry[] = MemberCategoryBuilder.league(league);
      expect(entries.length).assertEqual(2);
      expect(entries[0].seat).assertEqual(3);
      expect(entries[0].badge).assertEqual('');
    });

    it('counts_match_categories', 0, () => {
      const counts: MemberCategoryCounts = MemberCategoryBuilder.counts(classMembers, league);
      expect(counts.committee).assertEqual(3);
      expect(counts.league).assertEqual(2);
      expect(counts.all).assertEqual(4);
      expect(counts.of(MemberCategory.LEAGUE)).assertEqual(2);
    });

    it('search_filters_by_name', 0, () => {
      const entries: MemberEntry[] = MemberCategoryBuilder.all(classMembers);
      expect(MemberCategoryBuilder.search(entries, '李').length).assertEqual(1);
      expect(MemberCategoryBuilder.search(entries, '   ').length).assertEqual(4);
      expect(MemberCategoryBuilder.search(entries, '不存在').length).assertEqual(0);
    });

    it('visible_entries_combines_category_and_query', 0, () => {
      const entries: MemberEntry[] = MemberCategoryBuilder.visibleEntries(MemberCategory.ALL, classMembers, league, '孙');
      expect(entries.length).assertEqual(1);
      expect(entries[0].name).assertEqual('孙八');
    });
  });

  describe('ClassMembersRepository', () => {
    it('load_fetches_and_caches', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.membersBody = membersBody([memberJson(1, '张一', '班长', '班委'), memberJson(2, '张二', '', '')]);
      const repo: ClassMembersRepository = new ClassMembersRepository(api, new InMemoryClassMemberCache(),
        () => SID, () => 1000, 6 * 60 * 60 * 1000);
      const first: ClassMembersResult = await repo.load(false);
      expect(first.ok).assertTrue();
      expect(first.fromCache).assertFalse();
      expect(first.members.length).assertEqual(2);
      const second: ClassMembersResult = await repo.load(false);
      expect(second.fromCache).assertTrue();
      expect(api.postPaths.length).assertEqual(1);
    });

    it('failure_falls_back_to_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.membersBody = membersBody([memberJson(1, '张一', '', '')]);
      let now: number = 1000;
      const repo: ClassMembersRepository = new ClassMembersRepository(api, new InMemoryClassMemberCache(),
        () => SID, () => now, 1000);
      await repo.load(false);
      now = 5000;
      api.failPosts = true;
      const second: ClassMembersResult = await repo.load(true);
      expect(second.ok).assertTrue();
      expect(second.fromCache).assertTrue();
      expect(second.members.length).assertEqual(1);
    });

    it('empty_response_is_failure_without_cache', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.membersBody = '[]';
      const repo: ClassMembersRepository = new ClassMembersRepository(api, new InMemoryClassMemberCache(),
        () => SID, () => 1000);
      const result: ClassMembersResult = await repo.load(true);
      expect(result.ok).assertFalse();
      expect(result.message.length > 0).assertTrue();
    });

    it('cached_does_not_hit_network', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.membersBody = membersBody([memberJson(9, '张九', '', '')]);
      const repo: ClassMembersRepository = new ClassMembersRepository(api, new InMemoryClassMemberCache(),
        () => SID, () => 1000);
      await repo.load(true);
      const cached: ClassMember[] = await repo.cached();
      expect(cached.length).assertEqual(1);
      expect(api.postPaths.length).assertEqual(1);
    });
  });

  describe('ClassLeagueRepository', () => {
    it('load_parses_and_caches', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.leagueBody = leagueBody([seatJson(2, '李四'), seatJson(1, '王五')]);
      const repo: ClassLeagueRepository = new ClassLeagueRepository(api, () => SID, () => 1000);
      const first: ClassLeagueResult = await repo.load(false);
      expect(first.ok).assertTrue();
      expect(first.members.length).assertEqual(2);
      expect(first.members[0].seat).assertEqual(1);
      const second: ClassLeagueResult = await repo.load(false);
      expect(second.fromCache).assertTrue();
      expect(api.postPaths.length).assertEqual(1);
    });

    it('failure_without_cache_is_failure', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.failPosts = true;
      const repo: ClassLeagueRepository = new ClassLeagueRepository(api, () => SID, () => 1000);
      const result: ClassLeagueResult = await repo.load(true);
      expect(result.ok).assertFalse();
    });
  });
}
