import { describe, it, expect } from '@ohos/hypium';
import { DrawConfig, DrawEntry, DrawPoolSource, DrawResult, DrawSortMode } from '../main/ets/features/draw/DrawModels';
import { DrawRandom, SeededDrawRandom, shuffledInts } from '../main/ets/features/draw/DrawRandom';
import { DrawValidator, ExcludedParse } from '../main/ets/features/draw/DrawValidator';
import { DrawEngine, DrawOutcome } from '../main/ets/features/draw/DrawEngine';
import { DrawStep, DrawTransition, DrawWorkflow, DrawWorkflowState } from '../main/ets/features/draw/DrawWorkflow';
import { DrawConfigCodec } from '../main/ets/features/draw/DrawConfigCodec';
import { DrawLast, DrawLastCodec } from '../main/ets/features/draw/DrawLastCodec';
import { Blob, JsonBlob, JsonValue } from '../main/ets/data/sync/JsonBlob';
import { FakeApi } from './support/FakeApi';
import { InMemoryUserdataLocalStore } from '../main/ets/data/sync/UserdataLocalStore';
import { UserdataRepository, UserdataPushResult } from '../main/ets/data/sync/UserdataRepository';
import { UserdataV6 } from '../main/ets/data/sync/UserdataV6';

function config(start: number, end: number, count: number): DrawConfig {
  const c: DrawConfig = new DrawConfig();
  c.start = start;
  c.end = end;
  c.count = count;
  return c;
}

function numbersOf(entries: DrawEntry[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < entries.length; i++) {
    out.push(entries[i].number);
  }
  return out;
}

function uniqueCount(numbers: number[]): number {
  const set: Set<number> = new Set<number>();
  for (let i = 0; i < numbers.length; i++) {
    set.add(numbers[i]);
  }
  return set.size;
}

export default function drawTest() {
  describe('DrawRandom', () => {
    it('same_seed_same_sequence', 0, () => {
      const a: DrawRandom = new SeededDrawRandom(42);
      const b: DrawRandom = new SeededDrawRandom(42);
      for (let i = 0; i < 20; i++) {
        expect(a.nextInt(100)).assertEqual(b.nextInt(100));
      }
    });

    it('next_int_stays_in_bound', 0, () => {
      const rng: DrawRandom = new SeededDrawRandom(7);
      for (let i = 0; i < 200; i++) {
        const value: number = rng.nextInt(10);
        expect(value >= 0 && value < 10).assertTrue();
      }
      expect(rng.nextInt(0)).assertEqual(0);
    });

    it('shuffle_is_permutation', 0, () => {
      const order: number[] = shuffledInts(50, new SeededDrawRandom(9));
      expect(order.length).assertEqual(50);
      expect(uniqueCount(order)).assertEqual(50);
    });
  });

  describe('DrawValidator', () => {
    it('parses_exclusions_with_ranges', 0, () => {
      const parsed: ExcludedParse = DrawValidator.parseExcluded('3,7,10-12，15、20~22');
      expect(parsed.isValid()).assertTrue();
      expect(parsed.numbers.has(3)).assertTrue();
      expect(parsed.numbers.has(11)).assertTrue();
      expect(parsed.numbers.has(22)).assertTrue();
      expect(parsed.numbers.size).assertEqual(9);
    });

    it('rejects_bad_exclusions', 0, () => {
      const parsed: ExcludedParse = DrawValidator.parseExcluded('abc,5-2,1000');
      expect(parsed.isValid()).assertFalse();
      expect(parsed.invalidTokens.length).assertEqual(3);
    });

    it('rejects_start_greater_than_end', 0, () => {
      const result = DrawValidator.validate(config(50, 10, 5), []);
      expect(result.ok).assertFalse();
    });

    it('rejects_count_out_of_range', 0, () => {
      const result = DrawValidator.validate(config(1, 10, 0), []);
      expect(result.ok).assertFalse();
    });

    it('rejects_exclusion_format', 0, () => {
      const c: DrawConfig = config(1, 10, 3);
      c.excludedText = 'x';
      const result = DrawValidator.validate(c, []);
      expect(result.ok).assertFalse();
    });

    it('rejects_count_exceeding_pool', 0, () => {
      const result = DrawValidator.validate(config(1, 5, 6), []);
      expect(result.ok).assertFalse();
    });

    it('allows_duplicates_exceeding_pool', 0, () => {
      const c: DrawConfig = config(1, 5, 20);
      c.allowDuplicates = true;
      expect(DrawValidator.validate(c, []).ok).assertTrue();
    });

    it('pool_excludes_numbers', 0, () => {
      const c: DrawConfig = config(1, 10, 5);
      c.excludedText = '2,4';
      const result = DrawValidator.validate(c, []);
      expect(result.ok).assertTrue();
      expect(result.numbers.length).assertEqual(8);
      expect(result.numbers.indexOf(2) < 0).assertTrue();
    });

    it('roster_source_intersects_seats', 0, () => {
      const c: DrawConfig = config(1, 10, 3);
      c.poolSource = DrawPoolSource.ROSTER;
      const result = DrawValidator.validate(c, [2, 4, 6, 99]);
      expect(result.ok).assertTrue();
      expect(result.numbers.join(',')).assertEqual('2,4,6');
    });

    it('roster_source_without_seats_is_error', 0, () => {
      const c: DrawConfig = config(1, 10, 3);
      c.poolSource = DrawPoolSource.ROSTER;
      expect(DrawValidator.validate(c, []).ok).assertFalse();
    });
  });

  describe('DrawEngine', () => {
    it('unique_draw_has_no_duplicates_and_stays_in_range', 0, () => {
      const outcome: DrawOutcome = DrawEngine.draw(config(1, 70, 10), [], (n: number) => '', new SeededDrawRandom(1));
      expect(outcome.ok).assertTrue();
      const numbers: number[] = numbersOf(outcome.result!.entries);
      expect(numbers.length).assertEqual(10);
      expect(uniqueCount(numbers)).assertEqual(10);
      for (let i = 0; i < numbers.length; i++) {
        expect(numbers[i] >= 1 && numbers[i] <= 70).assertTrue();
      }
    });

    it('duplicates_allowed_can_repeat', 0, () => {
      const c: DrawConfig = config(1, 3, 30);
      c.allowDuplicates = true;
      const outcome: DrawOutcome = DrawEngine.draw(c, [], (n: number) => '', new SeededDrawRandom(2));
      expect(outcome.ok).assertTrue();
      expect(outcome.result!.entries.length).assertEqual(30);
      expect(uniqueCount(numbersOf(outcome.result!.entries)) < 30).assertTrue();
    });

    it('name_mapping_is_used', 0, () => {
      const outcome: DrawOutcome = DrawEngine.draw(config(1, 3, 3), [], (n: number) => '名' + n,
        new SeededDrawRandom(3));
      expect(outcome.ok).assertTrue();
      expect(outcome.result!.entries[0].name.indexOf('名') === 0).assertTrue();
      expect(outcome.result!.entries[0].label().indexOf('名') > 0).assertTrue();
    });

    it('ascending_sort_orders_numbers', 0, () => {
      const c: DrawConfig = config(1, 70, 8);
      c.sort = DrawSortMode.ASCENDING;
      const outcome: DrawOutcome = DrawEngine.draw(c, [], (n: number) => '', new SeededDrawRandom(4));
      const numbers: number[] = numbersOf(outcome.result!.entries);
      for (let i = 1; i < numbers.length; i++) {
        expect(numbers[i] >= numbers[i - 1]).assertTrue();
      }
    });

    it('descending_sort_orders_numbers', 0, () => {
      const c: DrawConfig = config(1, 70, 8);
      c.sort = DrawSortMode.DESCENDING;
      const outcome: DrawOutcome = DrawEngine.draw(c, [], (n: number) => '', new SeededDrawRandom(5));
      const numbers: number[] = numbersOf(outcome.result!.entries);
      for (let i = 1; i < numbers.length; i++) {
        expect(numbers[i] <= numbers[i - 1]).assertTrue();
      }
    });

    it('remove_and_redraw_restores_size_and_keeps_unique', 0, () => {
      const rng: DrawRandom = new SeededDrawRandom(6);
      let outcome: DrawOutcome = DrawEngine.draw(config(1, 10, 3), [], (n: number) => '', rng);
      const removedNumber: number = outcome.result!.entries[0].number;
      outcome = DrawEngine.removeAndRedraw(outcome.result!, 0, true, rng);
      expect(outcome.ok).assertTrue();
      const numbers: number[] = numbersOf(outcome.result!.entries);
      expect(numbers.length).assertEqual(3);
      expect(uniqueCount(numbers)).assertEqual(3);
      expect(numbers.indexOf(removedNumber) < 0).assertTrue();
      expect(outcome.result!.log.length).assertEqual(1);
      expect(outcome.result!.log[0].added !== undefined).assertTrue();
    });

    it('remove_without_redraw_shrinks', 0, () => {
      const rng: DrawRandom = new SeededDrawRandom(7);
      let outcome: DrawOutcome = DrawEngine.draw(config(1, 10, 3), [], (n: number) => '', rng);
      outcome = DrawEngine.removeAndRedraw(outcome.result!, 0, false, rng);
      expect(outcome.result!.entries.length).assertEqual(2);
      expect(outcome.result!.log[0].added === undefined).assertTrue();
    });

    it('remove_invalid_index_fails', 0, () => {
      const rng: DrawRandom = new SeededDrawRandom(8);
      const outcome: DrawOutcome = DrawEngine.draw(config(1, 10, 2), [], (n: number) => '', rng);
      expect(DrawEngine.removeAndRedraw(outcome.result!, 5, true, rng).ok).assertFalse();
    });

    it('reroll_keeps_pool_and_count', 0, () => {
      const rng: DrawRandom = new SeededDrawRandom(9);
      const outcome: DrawOutcome = DrawEngine.draw(config(1, 20, 5), [], (n: number) => '', rng);
      const again: DrawOutcome = DrawEngine.reroll(outcome.result!, rng);
      expect(again.ok).assertTrue();
      expect(again.result!.entries.length).assertEqual(5);
      expect(again.result!.pool.length).assertEqual(20);
    });
  });

  describe('DrawWorkflow', () => {
    it('config_to_preview_to_result', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(1, 20, 3));
      const preview: DrawTransition = DrawWorkflow.toPreview(state, [], (n: number) => '');
      expect(preview.ok).assertTrue();
      state = preview.state!;
      expect(state.step).assertEqual(DrawStep.PREVIEW);
      expect(state.candidates.length).assertEqual(20);

      const drawn: DrawTransition = DrawWorkflow.startDraw(state, new SeededDrawRandom(10));
      expect(drawn.ok).assertTrue();
      state = drawn.state!;
      expect(state.step).assertEqual(DrawStep.RESULT);
      expect(state.result!.entries.length).assertEqual(3);
    });

    it('invalid_config_blocks_preview', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(30, 10, 3));
      const preview: DrawTransition = DrawWorkflow.toPreview(state, [], (n: number) => '');
      expect(preview.ok).assertFalse();
      expect(preview.error !== undefined).assertTrue();
    });

    it('start_draw_requires_preview', 0, () => {
      const state: DrawWorkflowState = new DrawWorkflowState();
      expect(DrawWorkflow.startDraw(state, new SeededDrawRandom(1)).ok).assertFalse();
    });

    it('back_walks_steps_and_clears', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(1, 10, 2));
      state = DrawWorkflow.toPreview(state, [], (n: number) => '').state!;
      state = DrawWorkflow.startDraw(state, new SeededDrawRandom(2)).state!;
      state = DrawWorkflow.back(state);
      expect(state.step).assertEqual(DrawStep.PREVIEW);
      expect(state.result === undefined).assertTrue();
      state = DrawWorkflow.back(state);
      expect(state.step).assertEqual(DrawStep.CONFIG);
      expect(state.candidates.length).assertEqual(0);
    });

    it('change_sort_updates_config', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(1, 30, 4));
      state = DrawWorkflow.toPreview(state, [], (n: number) => '').state!;
      state = DrawWorkflow.startDraw(state, new SeededDrawRandom(3)).state!;
      const changed: DrawTransition = DrawWorkflow.changeSort(state, DrawSortMode.ASCENDING, new SeededDrawRandom(4));
      expect(changed.ok).assertTrue();
      state = changed.state!;
      expect(state.config.sort).assertEqual(DrawSortMode.ASCENDING);
      expect(state.result!.config.sort).assertEqual(DrawSortMode.ASCENDING);
      const numbers: number[] = numbersOf(state.result!.entries);
      for (let i = 1; i < numbers.length; i++) {
        expect(numbers[i] >= numbers[i - 1]).assertTrue();
      }
    });

    it('config_is_locked_after_preview', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(1, 10, 2));
      state = DrawWorkflow.toPreview(state, [], (n: number) => '').state!;
      const changed: DrawWorkflowState = DrawWorkflow.updateConfig(state, config(1, 99, 9));
      expect(changed.config.end).assertEqual(10);
    });

    it('reset_keeps_config_clears_data', 0, () => {
      let state: DrawWorkflowState = new DrawWorkflowState();
      state = DrawWorkflow.updateConfig(state, config(1, 10, 2));
      state = DrawWorkflow.toPreview(state, [], (n: number) => '').state!;
      state = DrawWorkflow.startDraw(state, new SeededDrawRandom(5)).state!;
      state = DrawWorkflow.reset(state);
      expect(state.step).assertEqual(DrawStep.CONFIG);
      expect(state.config.end).assertEqual(10);
      expect(state.result === undefined).assertTrue();
    });
  });

  describe('DrawConfigCodec', () => {
    it('roundtrip_keeps_contract_key_order', 0, () => {
      const c: DrawConfig = config(2, 50, 10);
      c.excludedText = '3,7';
      c.sort = DrawSortMode.ASCENDING;
      const blob: Blob = DrawConfigCodec.toJson(c);
      expect(JsonBlob.keys(blob).join(',')).assertEqual('start,end,count,dup,excl,sort');
      const back: DrawConfig = DrawConfigCodec.fromJson(blob);
      expect(back.start).assertEqual(2);
      expect(back.end).assertEqual(50);
      expect(back.count).assertEqual(10);
      expect(back.excludedText).assertEqual('3,7');
      expect(back.sort).assertEqual(DrawSortMode.ASCENDING);
    });

    it('missing_section_uses_defaults', 0, () => {
      const c: DrawConfig = DrawConfigCodec.fromJson(undefined);
      expect(c.start).assertEqual(DrawConfig.DEFAULT_START);
      expect(c.end).assertEqual(DrawConfig.DEFAULT_END);
      expect(c.count).assertEqual(DrawConfig.DEFAULT_COUNT);
      expect(c.sort).assertEqual(DrawSortMode.DRAW_ORDER);
    });

    it('dirty_values_are_clamped', 0, () => {
      const blob: Blob = {
        'start': 0,
        'end': 99999,
        'count': -3,
        'dup': 'yes',
        'excl': 5,
        'sort': 'unknown'
      };
      const c: DrawConfig = DrawConfigCodec.fromJson(blob);
      expect(c.start).assertEqual(DrawConfig.MIN_NUMBER);
      expect(c.end).assertEqual(DrawConfig.MAX_NUMBER);
      expect(c.count).assertEqual(DrawConfig.MIN_COUNT);
      expect(c.allowDuplicates).assertFalse();
      expect(c.excludedText).assertEqual('');
      expect(c.sort).assertEqual(DrawSortMode.DRAW_ORDER);
    });

    it('string_numbers_are_accepted', 0, () => {
      const blob: Blob = { 'start': '3', 'end': '12', 'count': '4' };
      const c: DrawConfig = DrawConfigCodec.fromJson(blob);
      expect(c.start).assertEqual(3);
      expect(c.end).assertEqual(12);
      expect(c.count).assertEqual(4);
    });

    it('pool_source_is_not_persisted', 0, () => {
      const c: DrawConfig = config(1, 10, 2);
      c.poolSource = DrawPoolSource.ROSTER;
      const back: DrawConfig = DrawConfigCodec.fromJson(DrawConfigCodec.toJson(c));
      expect(back.poolSource).assertEqual(DrawPoolSource.RANGE);
    });

    it('unknown_fields_are_preserved_on_write', 0, () => {
      const existing: Blob = {
        'start': 1,
        'end': 70,
        'count': 10,
        'dup': false,
        'excl': '',
        'sort': 'draw',
        'names': '1 甲\n2 乙'
      };
      const written: Blob = DrawConfigCodec.toJson(config(2, 20, 3), existing);
      expect(JsonBlob.asString(JsonBlob.get(written, 'names'), '')).assertEqual('1 甲\n2 乙');
      expect(JsonBlob.numMs(JsonBlob.get(written, 'end'))).assertEqual(20);
    });

    it('draw_section_syncs_through_userdata', 0, async () => {
      const api: FakeApi = new FakeApi();
      const store: InMemoryUserdataLocalStore = new InMemoryUserdataLocalStore();
      const repo: UserdataRepository = new UserdataRepository(api, store, () => '3260799999', () => 5000);
      await repo.pull(true);

      // 模拟 UI：读当前 draw section（含未知 names），写回新参数
      const current: Blob = repo.currentSections();
      const next: Blob = {};
      const keys: string[] = JsonBlob.keys(current);
      for (let i = 0; i < keys.length; i++) {
        next[keys[i]] = current[keys[i]];
      }
      const existing: Blob = { 'names': '7 张三' };
      const edited: DrawConfig = config(3, 33, 6);
      edited.excludedText = '5';
      next['draw'] = DrawConfigCodec.toJson(edited, existing);
      await repo.updateCurrent(next);

      const pushed: UserdataPushResult = await repo.flush();
      expect(pushed.ok()).assertTrue();
      expect(pushed.pushed).assertTrue();

      const rows: Object[] | undefined = JsonBlob.asArray(JSON.parse(api.lastPostBody()) as JsonValue);
      expect(rows !== undefined).assertTrue();
      if (rows !== undefined) {
        const row: Blob | undefined = JsonBlob.asBlob(rows[0]);
        const blobText: string = JsonBlob.asString(JsonBlob.get(row, 'blob'), '');
        const blob: Blob | undefined = UserdataV6.decode(blobText);
        expect(blob !== undefined).assertTrue();
        if (blob !== undefined) {
          const draw: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(blob, 'draw'));
          expect(JsonBlob.numMs(JsonBlob.get(draw, 'start'))).assertEqual(3);
          expect(JsonBlob.numMs(JsonBlob.get(draw, 'end'))).assertEqual(33);
          expect(JsonBlob.asString(JsonBlob.get(draw, 'names'), '')).assertEqual('7 张三');
          expect(UserdataV6.atValue(blob, 'draw')).assertEqual(5000);
        }
      }
    });
  });

  describe('DrawLastCodec', () => {
    it('roundtrip_keeps_result_names_pool_and_config', 0, () => {
      const result: DrawResult = new DrawResult();
      result.entries = [new DrawEntry(7, '甲'), new DrawEntry(3, '')];
      result.pool = [new DrawEntry(1, ''), new DrawEntry(3, ''), new DrawEntry(5, ''),
        new DrawEntry(7, '甲')];
      result.config = config(1, 70, 2);
      result.config.sort = DrawSortMode.DESCENDING;
      result.config.allowDuplicates = true;

      const blob: Blob = DrawLastCodec.encode(result, 1700000000000);
      expect(JsonBlob.keys(blob).join(',')).assertEqual('v,at,result,names,pool,cfg');

      const last: DrawLast | undefined = DrawLastCodec.decode(blob);
      expect(last !== undefined).assertTrue();
      if (last !== undefined) {
        expect(last.at).assertEqual(1700000000000);
        expect(last.result.entries.length).assertEqual(2);
        expect(last.result.entries[0].number).assertEqual(7);
        expect(last.result.entries[0].name).assertEqual('甲');
        expect(last.result.entries[1].name).assertEqual('');
        expect(last.result.pool.length).assertEqual(4);
        expect(last.result.config.start).assertEqual(1);
        expect(last.result.config.end).assertEqual(70);
        expect(last.result.config.count).assertEqual(2);
        expect(last.result.config.allowDuplicates).assertTrue();
        expect(last.result.config.sort).assertEqual(DrawSortMode.DESCENDING);
      }
    });

    it('partial_payload_falls_back_to_defaults', 0, () => {
      const blob: Blob = { 'result': [3, '7', 0, 1000], 'names': ['甲', 7] };
      const last: DrawLast | undefined = DrawLastCodec.decode(blob);
      expect(last !== undefined).assertTrue();
      if (last !== undefined) {
        expect(last.at).assertEqual(0);
        expect(last.result.entries.length).assertEqual(2);
        expect(last.result.entries[0].number).assertEqual(3);
        expect(last.result.entries[0].name).assertEqual('甲');
        expect(last.result.entries[1].number).assertEqual(7);
        expect(last.result.entries[1].name).assertEqual('');
        expect(last.result.pool.length).assertEqual(0);
        expect(last.result.config.start).assertEqual(DrawConfig.DEFAULT_START);
        expect(last.result.config.sort).assertEqual(DrawSortMode.DRAW_ORDER);
      }
    });

    it('empty_or_malformed_payload_is_ignored', 0, () => {
      expect(DrawLastCodec.decode(undefined) === undefined).assertTrue();
      expect(DrawLastCodec.decode({}) === undefined).assertTrue();
      expect(DrawLastCodec.decode({ 'result': [] }) === undefined).assertTrue();
      expect(DrawLastCodec.decode({ 'result': [0, 1000] }) === undefined).assertTrue();
    });

    it('duplicates_are_preserved_for_dup_mode', 0, () => {
      const result: DrawResult = new DrawResult();
      result.entries = [new DrawEntry(5, ''), new DrawEntry(5, '')];
      result.config = config(1, 5, 2);
      result.config.allowDuplicates = true;
      const last: DrawLast | undefined = DrawLastCodec.decode(DrawLastCodec.encode(result, 1));
      expect(last !== undefined).assertTrue();
      if (last !== undefined) {
        expect(last.result.entries.length).assertEqual(2);
        expect(last.result.entries[0].number).assertEqual(5);
        expect(last.result.entries[1].number).assertEqual(5);
        expect(last.result.config.allowDuplicates).assertTrue();
      }
    });

    it('encodes_current_result_only', 0, () => {
      const first: DrawResult = new DrawResult();
      first.entries = [new DrawEntry(2, '')];
      const second: DrawResult = new DrawResult();
      second.entries = [new DrawEntry(9, '乙')];
      const last: DrawLast | undefined = DrawLastCodec.decode(DrawLastCodec.encode(second, 2));
      expect(last !== undefined).assertTrue();
      if (last !== undefined) {
        expect(last.result.entries.length).assertEqual(1);
        expect(last.result.entries[0].number).assertEqual(9);
        expect(last.result.entries[0].name).assertEqual('乙');
      }
      const earlier: DrawLast | undefined = DrawLastCodec.decode(DrawLastCodec.encode(first, 1));
      expect(earlier !== undefined && earlier.result.entries[0].number === 2).assertTrue();
    });
  });
}
