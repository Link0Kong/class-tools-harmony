import { describe, it, expect } from '@ohos/hypium';
import {
  GroupConfig,
  GroupErrorCode,
  GroupMember,
  GroupMode,
  groupSourceLabel,
  GroupResult,
  GroupSource,
  GroupValidation,
  MemberGroup
} from '../main/ets/features/group/GroupModels';
import { GroupEngine, SeededGroupRandom } from '../main/ets/features/group/GroupEngine';
import { GroupConfigCodec } from '../main/ets/features/group/GroupCodec';
import { GroupExportFactory } from '../main/ets/features/export/ExportCard';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';

function members(count: number): GroupMember[] {
  const out: GroupMember[] = [];
  for (let i = 1; i <= count; i++) {
    out.push(new GroupMember(i, i % 2 === 0 ? '名' + i : ''));
  }
  return out;
}

function config(source: GroupSource, mode: GroupMode, n: number, shuffle: boolean): GroupConfig {
  const config: GroupConfig = new GroupConfig();
  config.source = source;
  config.mode = mode;
  config.n = n;
  config.shuffle = shuffle;
  return config;
}

function sizes(result: GroupResult): number[] {
  const out: number[] = [];
  for (let i = 0; i < result.groups.length; i++) {
    out.push(result.groups[i].members.length);
  }
  return out;
}

function maxDiff(values: number[]): number {
  let min: number = values[0];
  let max: number = values[0];
  for (let i = 1; i < values.length; i++) {
    if (values[i] < min) {
      min = values[i];
    }
    if (values[i] > max) {
      max = values[i];
    }
  }
  return max - min;
}

export default function groupTest() {
  describe('GroupEngineCount', () => {
    it('groups_mode_clamps_to_member_count', 0, () => {
      const list: GroupMember[] = members(10);
      expect(GroupEngine.groupCount(0, config(GroupSource.PREV, GroupMode.GROUPS, 4, false))).assertEqual(0);
      expect(GroupEngine.groupCount(10, config(GroupSource.PREV, GroupMode.GROUPS, 1, false))).assertEqual(2);
      expect(GroupEngine.groupCount(10, config(GroupSource.PREV, GroupMode.GROUPS, 99, false))).assertEqual(10);
      expect(list.length).assertEqual(10);
    });

    it('pergroup_mode_uses_ceil', 0, () => {
      expect(GroupEngine.groupCount(10, config(GroupSource.PREV, GroupMode.PER_GROUP, 3, false))).assertEqual(4);
      expect(GroupEngine.groupCount(9, config(GroupSource.PREV, GroupMode.PER_GROUP, 3, false))).assertEqual(3);
      expect(GroupEngine.groupCount(1, config(GroupSource.PREV, GroupMode.PER_GROUP, 99, false))).assertEqual(1);
    });
  });

  describe('GroupEngineGroup', () => {
    it('splits_all_members_balanced', 0, () => {
      const result: GroupResult = GroupEngine.group(members(10), config(GroupSource.PREV, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(1));
      expect(result.groups.length).assertEqual(3);
      expect(result.totalMembers()).assertEqual(10);
      expect(maxDiff(sizes(result)) <= 1).assertTrue();
      expect(result.groups[0].index).assertEqual(1);
      expect(result.groups[0].label()).assertEqual('第 1 组');
    });

    it('pergroup_splits_by_size', 0, () => {
      const result: GroupResult = GroupEngine.group(members(11), config(GroupSource.PREV, GroupMode.PER_GROUP, 4, false),
        new SeededGroupRandom(2));
      expect(result.groups.length).assertEqual(3);
      expect(result.totalMembers()).assertEqual(11);
    });

    it('no_shuffle_keeps_original_order', 0, () => {
      const list: GroupMember[] = members(6);
      const result: GroupResult = GroupEngine.group(list, config(GroupSource.PREV, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(3));
      expect(result.groups[0].members[0].seat).assertEqual(1);
      expect(result.groups[1].members[0].seat).assertEqual(2);
      expect(result.groups[2].members[0].seat).assertEqual(3);
    });

    it('shuffle_is_deterministic_per_seed', 0, () => {
      const a: GroupResult = GroupEngine.group(members(12), config(GroupSource.PREV, GroupMode.GROUPS, 3, true),
        new SeededGroupRandom(42));
      const b: GroupResult = GroupEngine.group(members(12), config(GroupSource.PREV, GroupMode.GROUPS, 3, true),
        new SeededGroupRandom(42));
      const seatsA: string[] = [];
      const seatsB: string[] = [];
      for (let i = 0; i < a.groups.length; i++) {
        for (let j = 0; j < a.groups[i].members.length; j++) {
          seatsA.push('' + a.groups[i].members[j].seat);
          seatsB.push('' + b.groups[i].members[j].seat);
        }
      }
      expect(seatsA.join(',')).assertEqual(seatsB.join(','));
    });

    it('snapshot_labels_match_contract', 0, () => {
      const result: GroupResult = GroupEngine.group(members(10), config(GroupSource.NAMES, GroupMode.PER_GROUP, 3, true),
        new SeededGroupRandom(4));
      expect(result.snapshot.total).assertEqual(10);
      expect(result.snapshot.groupCount).assertEqual(4);
      expect(result.snapshot.sourceLabel).assertEqual('班级名单（10 人）');
      expect(result.snapshot.modeLabel).assertEqual('按每组人数(3 人)');
      expect(result.snapshot.innerLabel).assertEqual('打乱后随机分配');
    });

    it('snapshot_uses_recent_draw_label', 0, () => {
      const result: GroupResult = GroupEngine.group(members(10), config(GroupSource.PREV, GroupMode.GROUPS, 4, false),
        new SeededGroupRandom(7));
      expect(result.snapshot.sourceLabel).assertEqual('最近抽签（10 人）');
      expect(groupSourceLabel(GroupSource.PREV)).assertEqual('最近抽签');
    });

    it('summary_reports_total_groups_and_range', 0, () => {
      const uneven: GroupResult = GroupEngine.group(members(10), config(GroupSource.PREV, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(8));
      expect(uneven.summary()).assertEqual('共 10 人 · 3 组 · 每组 3–4 人');

      const even: GroupResult = GroupEngine.group(members(9), config(GroupSource.PREV, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(9));
      expect(even.summary()).assertEqual('共 9 人 · 3 组 · 每组 3 人');
      expect(new GroupResult().summary()).assertEqual('共 0 人 · 0 组');
    });

    it('copy_text_lists_groups_without_student_ids', 0, () => {
      const result: GroupResult = GroupEngine.group(members(6), config(GroupSource.PREV, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(10));
      const text: string = result.copyText();
      expect(text.indexOf('随机分组结果（共 6 人 · 3 组 · 每组 2 人）') === 0).assertTrue();
      expect(text.indexOf('第 1 组（2 人）：1、4') > 0).assertTrue();
      expect(text.indexOf('第 2 组（2 人）：2 名2、5') > 0).assertTrue();
      expect(text.indexOf('学号') < 0).assertTrue();
    });
  });

  describe('GroupEngineValidate', () => {
    it('rejects_empty_members', 0, () => {
      const validation: GroupValidation = GroupEngine.validate([], config(GroupSource.PREV, GroupMode.GROUPS, 4, false));
      expect(validation.ok).assertFalse();
      expect(validation.error!.code).assertEqual(GroupErrorCode.NO_MEMBERS);
      expect(validation.error!.message.indexOf('最近抽签') >= 0).assertTrue();
    });

    it('rejects_empty_roster_selection', 0, () => {
      const validation: GroupValidation = GroupEngine.validate([], config(GroupSource.NAMES, GroupMode.GROUPS, 4, false));
      expect(validation.ok).assertFalse();
      expect(validation.error!.code).assertEqual(GroupErrorCode.ROSTER_EMPTY);
    });

    it('rejects_single_member', 0, () => {
      const validation: GroupValidation = GroupEngine.validate(members(1),
        config(GroupSource.PREV, GroupMode.GROUPS, 2, false));
      expect(validation.ok).assertFalse();
      expect(validation.error!.code).assertEqual(GroupErrorCode.MEMBERS_TOO_FEW);
    });

    it('accepts_valid_config', 0, () => {
      const validation: GroupValidation = GroupEngine.validate(members(10),
        config(GroupSource.PREV, GroupMode.GROUPS, 4, false));
      expect(validation.ok).assertTrue();
    });
  });

  describe('GroupConfigCodec', () => {
    it('roundtrip_keeps_contract_order', 0, () => {
      const c: GroupConfig = config(GroupSource.NAMES, GroupMode.PER_GROUP, 5, true);
      c.selectedSeats = [5, 3, 5, 1];
      const blob: Blob = GroupConfigCodec.toJson(c);
      expect(JsonBlob.keys(blob).join(',')).assertEqual('source,mode,n,shuffle,sel');
      const back: GroupConfig = GroupConfigCodec.fromJson(blob);
      expect(back.source).assertEqual(GroupSource.NAMES);
      expect(back.mode).assertEqual(GroupMode.PER_GROUP);
      expect(back.n).assertEqual(5);
      expect(back.shuffle).assertTrue();
      expect(back.selectedSeats.join(',')).assertEqual('1,3,5');
    });

    it('accepts_legacy_wire_values', 0, () => {
      const blob: Blob = { 'source': 'pick', 'mode': 'per', 'n': 3, 'shuffle': 'true', 'sel': [2, 1] };
      const c: GroupConfig = GroupConfigCodec.fromJson(blob);
      expect(c.source).assertEqual(GroupSource.NAMES);
      expect(c.mode).assertEqual(GroupMode.PER_GROUP);
      expect(c.n).assertEqual(3);
      expect(c.shuffle).assertTrue();
      expect(c.selectedSeats.join(',')).assertEqual('1,2');
    });

    it('missing_section_uses_defaults', 0, () => {
      const c: GroupConfig = GroupConfigCodec.fromJson(undefined);
      expect(c.source).assertEqual(GroupSource.PREV);
      expect(c.mode).assertEqual(GroupMode.GROUPS);
      expect(c.n).assertEqual(GroupConfig.DEFAULT_N);
      expect(c.shuffle).assertFalse();
      expect(c.selectedSeats.length).assertEqual(0);
    });

    it('seats_are_filtered_and_sorted', 0, () => {
      const blob: Blob = { 'sel': [0, 100, 7, '3', 7, -2] };
      const c: GroupConfig = GroupConfigCodec.fromJson(blob);
      expect(c.selectedSeats.join(',')).assertEqual('3,7');
    });

    it('unknown_fields_are_preserved_on_write', 0, () => {
      const existing: Blob = { 'source': 'prev', 'mode': 'groups', 'n': 4, 'shuffle': false, 'sel': [], 'future': 'x' };
      const written: Blob = GroupConfigCodec.toJson(config(GroupSource.NAMES, GroupMode.GROUPS, 6, false), existing);
      expect(JsonBlob.asString(JsonBlob.get(written, 'future'), '')).assertEqual('x');
      expect(JsonBlob.asString(JsonBlob.get(written, 'source'), '')).assertEqual('names');
    });
  });

  describe('GroupExportFactory', () => {
    it('builds_groups_card_spec', 0, () => {
      const result: GroupResult = GroupEngine.group(members(10), config(GroupSource.NAMES, GroupMode.GROUPS, 3, false),
        new SeededGroupRandom(5));
      const spec = GroupExportFactory.create(result, new Date(2026, 10, 14, 23, 30).getTime(), 'ab12c');
      expect(spec.title).assertEqual('随机分组结果');
      expect(spec.subtitle).assertEqual('共 10 人 · 3 组');
      expect(spec.recordId).assertEqual('GROUP-20261114-2330-AB12C');
      expect(spec.fileName).assertEqual('分组结果_20261114-2330_10人_3组_原顺序.png');
      expect(spec.params.length).assertEqual(5);
      expect(spec.groups.length).assertEqual(3);
      const firstGroup: number = spec.groups[0].length;
      expect(firstGroup >= 3 && firstGroup <= 4).assertTrue();
      const all: MemberGroup[] = result.groups;
      expect(all.length).assertEqual(3);
    });

    it('file_name_marks_shuffle', 0, () => {
      const result: GroupResult = GroupEngine.group(members(8), config(GroupSource.PREV, GroupMode.PER_GROUP, 4, true),
        new SeededGroupRandom(6));
      const spec = GroupExportFactory.create(result, new Date(2026, 0, 2, 9, 5).getTime(), 'zz999');
      expect(spec.fileName.indexOf('打乱') > 0).assertTrue();
      expect(spec.fileName.indexOf('2组') > 0).assertTrue();
    });
  });
}
