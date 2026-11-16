import { ClassMember, LeagueMember, MemberEntry } from './ClassMember';

/** 名单三分类（对齐网页/小程序「名单」工具三 tab：班委 / 团员 / 全班）。 */
export enum MemberCategory {
  COMMITTEE = '班委',
  LEAGUE = '团员',
  ALL = '全班'
}

/** 三分类计数（UI tab 徽标）。 */
export class MemberCategoryCounts {
  committee: number = 0;
  league: number = 0;
  all: number = 0;

  constructor(committee: number = 0, league: number = 0, all: number = 0) {
    this.committee = committee;
    this.league = league;
    this.all = all;
  }

  of(category: MemberCategory): number {
    if (category === MemberCategory.COMMITTEE) {
      return this.committee;
    }
    if (category === MemberCategory.LEAGUE) {
      return this.league;
    }
    return this.all;
  }
}

/** 名单分类纯逻辑（可单测；不联网、不含学号）。 */
export class MemberCategoryBuilder {
  /** 班委判定与服务端 `auth_is_committee()` 同口径：`role` 非空 **或** `badge` 含「班委」。 */
  static isCommittee(member: ClassMember): boolean {
    return member.role.trim().length > 0 || member.badge.indexOf('班委') >= 0;
  }

  /** 班委名单（按座号升序；badge 优先 role，均无则「班委」）。 */
  static committee(members: ClassMember[]): MemberEntry[] {
    const out: MemberEntry[] = [];
    for (let i = 0; i < members.length; i++) {
      const member: ClassMember = members[i];
      if (!MemberCategoryBuilder.isCommittee(member)) {
        continue;
      }
      const name: string = member.name.trim();
      if (member.seat <= 0 || name.length === 0) {
        continue;
      }
      const role: string = member.role.trim();
      const badge: string = role.length > 0 ? role
        : (member.badge.trim().length > 0 ? member.badge.trim() : '班委');
      out.push(new MemberEntry(member.seat, name, badge));
    }
    out.sort((a: MemberEntry, b: MemberEntry) => a.seat - b.seat);
    return out;
  }

  /** 团员名单（来自 ClassLeagueRepository，无 badge）。 */
  static league(members: LeagueMember[]): MemberEntry[] {
    const out: MemberEntry[] = [];
    const seen: Set<number> = new Set<number>();
    for (let i = 0; i < members.length; i++) {
      const member: LeagueMember = members[i];
      const name: string = member.name.trim();
      if (member.seat <= 0 || name.length === 0 || seen.has(member.seat)) {
        continue;
      }
      seen.add(member.seat);
      out.push(new MemberEntry(member.seat, name, ''));
    }
    out.sort((a: MemberEntry, b: MemberEntry) => a.seat - b.seat);
    return out;
  }

  /** 全班名单（座号升序；badge 用 role/badge，无则不显示）。 */
  static all(members: ClassMember[]): MemberEntry[] {
    const out: MemberEntry[] = [];
    const seen: Set<number> = new Set<number>();
    for (let i = 0; i < members.length; i++) {
      const member: ClassMember = members[i];
      const name: string = member.name.trim();
      if (member.seat <= 0 || name.length === 0 || seen.has(member.seat)) {
        continue;
      }
      seen.add(member.seat);
      const role: string = member.role.trim();
      const badge: string = role.length > 0 ? role : member.badge.trim();
      out.push(new MemberEntry(member.seat, name, badge));
    }
    out.sort((a: MemberEntry, b: MemberEntry) => a.seat - b.seat);
    return out;
  }

  /** 按分类取名单；数据不可用时返回空列表（由 UI 显示空态）。 */
  static entries(category: MemberCategory, classMembers: ClassMember[], leagueMembers: LeagueMember[]): MemberEntry[] {
    if (category === MemberCategory.COMMITTEE) {
      return MemberCategoryBuilder.committee(classMembers);
    }
    if (category === MemberCategory.LEAGUE) {
      return MemberCategoryBuilder.league(leagueMembers);
    }
    return MemberCategoryBuilder.all(classMembers);
  }

  /** 三分类计数（用于 tab 徽标）。 */
  static counts(classMembers: ClassMember[], leagueMembers: LeagueMember[]): MemberCategoryCounts {
    return new MemberCategoryCounts(
      MemberCategoryBuilder.committee(classMembers).length,
      MemberCategoryBuilder.league(leagueMembers).length,
      MemberCategoryBuilder.all(classMembers).length
    );
  }

  /** 姓名搜索（空格不敏感；空查询返回全部）。 */
  static search(entries: MemberEntry[], query: string): MemberEntry[] {
    const q: string = query.trim();
    if (q.length === 0) {
      return entries;
    }
    const out: MemberEntry[] = [];
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].name.indexOf(q) >= 0) {
        out.push(entries[i]);
      }
    }
    return out;
  }

  /** 方便 UI：按分类 + 搜索过滤。 */
  static visibleEntries(category: MemberCategory, classMembers: ClassMember[], leagueMembers: LeagueMember[],
    query: string): MemberEntry[] {
    return MemberCategoryBuilder.search(
      MemberCategoryBuilder.entries(category, classMembers, leagueMembers), query);
  }
}
