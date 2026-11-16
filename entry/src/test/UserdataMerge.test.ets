import { describe, it, expect } from '@ohos/hypium';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';
import { UserdataV6 } from '../main/ets/data/sync/UserdataV6';
import { UserdataMerge } from '../main/ets/data/sync/UserdataMerge';
import {
  EXPECTED_MERGE_MP_WEB,
  EXPECTED_MERGE_WEB_MP,
  EXPECTED_V5_MIGRATE,
  LEGACY_V5,
  USERDATA_V6_MP,
  USERDATA_V6_WEB
} from './fixtures/SyncFixtures';

function blobOf(text: string): Blob {
  const parsed: Blob | undefined = JsonBlob.parse(text);
  return parsed !== undefined ? parsed : {};
}

function allSections(): Set<string> {
  const set: Set<string> = new Set<string>();
  for (let i = 0; i < UserdataV6.SECTION_KEYS.length; i++) {
    set.add(UserdataV6.SECTION_KEYS[i]);
  }
  return set;
}

function emptySet(): Set<string> {
  return new Set<string>();
}

export default function userdataMergeTest() {
  describe('UserdataMergeOracle', () => {
    it('merge_remote_mp_local_web_matches_oracle', 0, () => {
      const merged: Blob = UserdataMerge.merge(blobOf(USERDATA_V6_MP), blobOf(USERDATA_V6_WEB));
      expect(JsonBlob.deepEqual(merged, blobOf(EXPECTED_MERGE_WEB_MP))).assertTrue();
    });

    it('merge_remote_web_local_mp_matches_oracle', 0, () => {
      const merged: Blob = UserdataMerge.merge(blobOf(USERDATA_V6_WEB), blobOf(USERDATA_V6_MP));
      expect(JsonBlob.deepEqual(merged, blobOf(EXPECTED_MERGE_MP_WEB))).assertTrue();
    });

    it('v5_migration_matches_oracle', 0, () => {
      const localAt: Blob = {};
      const localFit: Blob = { 'sex': 'm' };
      const local: Blob = { 'at': localAt, 'fit': localFit };
      const merged: Blob = UserdataMerge.merge(blobOf(LEGACY_V5), local);
      expect(JsonBlob.deepEqual(merged, blobOf(EXPECTED_V5_MIGRATE))).assertTrue();
    });

    it('merge_output_has_contract_key_order', 0, () => {
      const merged: Blob = UserdataMerge.merge(blobOf(USERDATA_V6_MP), blobOf(USERDATA_V6_WEB));
      expect(JsonBlob.keys(merged).join(',')).assertEqual(UserdataV6.TOP_LEVEL_KEYS.join(','));
    });

    it('merge_is_idempotent', 0, () => {
      const once: Blob = UserdataMerge.merge(blobOf(USERDATA_V6_MP), blobOf(USERDATA_V6_WEB));
      const twice: Blob = UserdataMerge.merge(once, once);
      expect(JsonBlob.deepEqual(once, twice)).assertTrue();
    });
  });

  describe('UserdataMergeRules', () => {
    it('remote_wins_on_timestamp_tie', 0, () => {
      const remoteAt: Blob = { 'nick': 100 };
      const remote: Blob = { 'v': 6, 'at': remoteAt, 'nick': 'remote' };
      const localAt: Blob = { 'nick': 100 };
      const local: Blob = { 'at': localAt, 'nick': 'local' };
      const merged: Blob = UserdataMerge.merge(remote, local);
      expect(JsonBlob.asString(JsonBlob.get(merged, 'nick'), '')).assertEqual('remote');
      expect(UserdataV6.atValue(merged, 'nick')).assertEqual(100);
    });

    it('local_wins_when_newer', 0, () => {
      const remoteAt: Blob = { 'nick': 100 };
      const remote: Blob = { 'v': 6, 'at': remoteAt, 'nick': 'remote' };
      const localAt: Blob = { 'nick': 200 };
      const local: Blob = { 'at': localAt, 'nick': 'local' };
      const merged: Blob = UserdataMerge.merge(remote, local);
      expect(JsonBlob.asString(JsonBlob.get(merged, 'nick'), '')).assertEqual('local');
      expect(UserdataV6.atValue(merged, 'nick')).assertEqual(200);
    });

    it('null_value_does_not_count_as_present', 0, () => {
      const remoteAt: Blob = { 'tt': 500 };
      const remote: Blob = { 'v': 6, 'at': remoteAt, 'tt': null };
      const localAt: Blob = { 'tt': 100 };
      const localTt: Blob = { 'ttView': 'day' };
      const local: Blob = { 'at': localAt, 'tt': localTt };
      const merged: Blob = UserdataMerge.merge(remote, local);
      expect(UserdataV6.atValue(merged, 'tt')).assertEqual(100);
      const tt: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(merged, 'tt'));
      expect(tt !== undefined).assertTrue();
    });

    it('defaults_fill_when_both_sides_missing', 0, () => {
      const merged: Blob = UserdataMerge.merge(undefined, undefined);
      expect(JsonBlob.deepEqual(JsonBlob.get(merged, 'draw'), UserdataV6.defaultSection('draw'))).assertTrue();
      expect(JsonBlob.deepEqual(JsonBlob.get(merged, 'roster'), UserdataV6.defaultSection('roster'))).assertTrue();
      expect(UserdataV6.atValue(merged, 'draw')).assertEqual(0);
      expect(JsonBlob.numMs(JsonBlob.get(merged, 'homeToolsAt'))).assertEqual(0);
      expect(JsonBlob.numMs(JsonBlob.get(merged, 'v'))).assertEqual(6);
    });

    it('bad_json_is_treated_as_no_data', 0, () => {
      expect(JsonBlob.parse('not-json') === undefined).assertTrue();
      expect(JsonBlob.parse('[1,2]') === undefined).assertTrue();
      expect(JsonBlob.parse('') === undefined).assertTrue();
    });

    it('homeToolsAt_mirrors_at_homeTools', 0, () => {
      const remoteAt: Blob = { 'homeTools': 1762310000000 };
      const homeTools: Object[] = ['hw'];
      const remote: Blob = { 'v': 6, 'at': remoteAt, 'homeTools': homeTools };
      const merged: Blob = UserdataMerge.merge(remote, undefined);
      expect(JsonBlob.numMs(JsonBlob.get(merged, 'homeToolsAt'))).assertEqual(1762310000000);
    });
  });

  describe('UserdataLocalView', () => {
    it('dirty_section_gets_now_timestamp', 0, () => {
      const base: Blob = blobOf(USERDATA_V6_WEB);
      const current: Blob = blobOf(USERDATA_V6_WEB);
      current['nick'] = '改了昵称';
      const now: number = 1762400000000;
      const view: Blob = UserdataMerge.localView(base, current, base, emptySet(), now, allSections());
      expect(UserdataV6.atValue(view, 'nick')).assertEqual(now);
      expect(JsonBlob.asString(JsonBlob.get(view, 'nick'), '')).assertEqual('改了昵称');
      expect(UserdataV6.atValue(view, 'fit')).assertEqual(UserdataV6.atValue(base, 'fit'));
    });

    it('no_base_is_not_dirty', 0, () => {
      const current: Blob = blobOf(USERDATA_V6_WEB);
      const view: Blob = UserdataMerge.localView(undefined, current, undefined, emptySet(), 1762400000000, allSections());
      expect(UserdataV6.atValue(view, 'nick')).assertEqual(0);
    });

    it('force_keys_are_dirty_even_without_change', 0, () => {
      const base: Blob = blobOf(USERDATA_V6_WEB);
      const force: Set<string> = new Set<string>();
      force.add('power');
      const now: number = 1762400000000;
      const view: Blob = UserdataMerge.localView(base, base, base, force, now, allSections());
      expect(UserdataV6.atValue(view, 'power')).assertEqual(now);
    });

    it('power_section_mirrors_at_power', 0, () => {
      const base: Blob = blobOf(USERDATA_V6_WEB);
      const force: Set<string> = new Set<string>();
      force.add('power');
      const now: number = 1762400000000;
      const view: Blob = UserdataMerge.localView(base, base, base, force, now, allSections());
      const power: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(view, 'power'));
      expect(power !== undefined).assertTrue();
      if (power !== undefined) {
        expect(JsonBlob.numMs(JsonBlob.get(power, 'at'))).assertEqual(now);
        expect(JsonBlob.asString(JsonBlob.get(power, 'sel'), '')).assertEqual(
          JsonBlob.asString(JsonBlob.get(JsonBlob.asBlob(JsonBlob.get(base, 'power')), 'sel'), ''));
      }
    });

    it('local_view_output_has_contract_key_order', 0, () => {
      const base: Blob = blobOf(USERDATA_V6_WEB);
      const view: Blob = UserdataMerge.localView(base, base, base, emptySet(), 1762400000000, allSections());
      expect(JsonBlob.keys(view).join(',')).assertEqual(UserdataV6.TOP_LEVEL_KEYS.join(','));
    });

    it('dirty_sections_detects_change_only', 0, () => {
      const base: Blob = blobOf(USERDATA_V6_WEB);
      const current: Blob = blobOf(USERDATA_V6_WEB);
      current['nick'] = 'x';
      const dirty: Set<string> = UserdataMerge.dirtySections(base, current, allSections());
      expect(dirty.has('nick')).assertTrue();
      expect(dirty.has('fit')).assertFalse();
    });

    it('changed_keys_vs_defaults_skips_prefs', 0, () => {
      const current: Blob = UserdataV6.empty();
      current['nick'] = 'x';
      const changed: Set<string> = UserdataMerge.changedKeysVsDefaults(current, allSections());
      expect(changed.has('nick')).assertTrue();
      expect(changed.has('prefs')).assertFalse();
      expect(changed.has('fit')).assertFalse();
    });
  });

  describe('JsonBlobSemantics', () => {
    it('deep_equal_ignores_object_key_order', 0, () => {
      const aInner: Blob = { 'p': 1, 'q': 2 };
      const bInner: Blob = { 'q': 2, 'p': 1 };
      const a: Blob = { 'x': 1, 'y': aInner };
      const b: Blob = { 'y': bInner, 'x': 1 };
      expect(JsonBlob.deepEqual(a, b)).assertTrue();
    });

    it('deep_equal_is_strict_about_arrays', 0, () => {
      const a: Object[] = [1, 2];
      const b: Object[] = [2, 1];
      expect(JsonBlob.deepEqual(a, b)).assertFalse();
    });

    it('num_ms_rejects_string_and_non_positive', 0, () => {
      expect(JsonBlob.numMs('1762310000000')).assertEqual(0);
      expect(JsonBlob.numMs(0)).assertEqual(0);
      expect(JsonBlob.numMs(-5)).assertEqual(0);
      expect(JsonBlob.numMs(1762310000000)).assertEqual(1762310000000);
    });

    it('json_value_helpers_have_defaults', 0, () => {
      const value: JsonValue = null;
      expect(JsonBlob.asString(value, 'd')).assertEqual('d');
      expect(JsonBlob.asNumber(value, 7)).assertEqual(7);
      expect(JsonBlob.asBoolean(value, true)).assertTrue();
      expect(JsonBlob.asBlob(value) === undefined).assertTrue();
      expect(JsonBlob.asArray(value) === undefined).assertTrue();
    });
  });
}
