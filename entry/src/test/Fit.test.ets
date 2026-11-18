import { describe, it, expect } from '@ohos/hypium';
import {
  FIT_INPUT_FIELDS,
  FitCalc,
  FitFieldSpec,
  FitFields,
  FitGrade,
  FitHistory,
  FitInput,
  FitRecord,
  FitSex,
  SavedHistory
} from '../main/ets/features/fit/FitModels';
import { FitTables } from '../main/ets/features/fit/FitTables';
import { FitScoring } from '../main/ets/features/fit/FitScoring';
import { FitCodec } from '../main/ets/features/fit/FitCodec';
import { ExportCardSpec, FitExportFactory } from '../main/ets/features/export/ExportCard';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';

function fullInput(): FitInput {
  const input: FitInput = new FitInput();
  input.sex = FitSex.MALE;
  input.grade = FitGrade.G12;
  input.h = '178';
  input.w = '65';
  input.vc = '4200';
  input.r50 = '7.0';
  input.sit = '10';
  input.jump = '230';
  input.pull = '12';
  input.durM = '4';
  input.durS = '0';
  return input;
}

function rowScore(calc: FitCalc, index: number): number | undefined {
  return calc.rows[index].score;
}

export default function fitTest() {
  describe('FitHelpers', () => {
    it('num_parses_and_rejects', 0, () => {
      expect(FitScoring.num(' 12.5 ')).assertEqual(12.5);
      expect(FitScoring.num('') === undefined).assertTrue();
      expect(FitScoring.num('abc') === undefined).assertTrue();
    });

    it('sec_combines_minutes_and_seconds', 0, () => {
      expect(FitScoring.sec('4', '30')).assertEqual(270);
      expect(FitScoring.sec('', '45')).assertEqual(45);
      expect(FitScoring.sec('3', '')).assertEqual(180);
      expect(FitScoring.sec('', '') === undefined).assertTrue();
    });

    it('ms_formats', 0, () => {
      expect(FitScoring.ms(270)).assertEqual('4\'30"');
      expect(FitScoring.ms(59.6)).assertEqual('1\'00"');
      expect(FitScoring.ms(undefined)).assertEqual('—');
    });

    it('round10_rounds_one_decimal', 0, () => {
      expect(FitScoring.round10(78.65)).assertEqual(78.7);
      expect(FitScoring.round10(12.34)).assertEqual(12.3);
    });

    it('sanitize_keeps_digits_and_decimals', 0, () => {
      const h: FitFieldSpec = FIT_INPUT_FIELDS[0];
      expect(FitScoring.sanitizeInput('17a8.55', h)).assertEqual('178.5');
      const sit: FitFieldSpec = FIT_INPUT_FIELDS[4];
      expect(FitScoring.sanitizeInput('-12.5', sit)).assertEqual('-12.5');
      const vc: FitFieldSpec = FIT_INPUT_FIELDS[2];
      expect(FitScoring.sanitizeInput('4200.9', vc)).assertEqual('4200');
    });
  });

  describe('FitTablesScoring', () => {
    it('vc_top_score', 0, () => {
      expect(FitScoring.scoreOf(FitTables.VC, 5040, FitSex.MALE, FitGrade.G12)).assertEqual(100);
      expect(FitScoring.scoreOf(FitTables.VC, 4200, FitSex.MALE, FitGrade.G12)).assertEqual(78);
      expect(FitScoring.scoreOf(FitTables.VC, 100, FitSex.MALE, FitGrade.G12)).assertEqual(0);
    });

    it('r50_lower_is_better', 0, () => {
      expect(FitScoring.scoreOf(FitTables.R50, 6.7, FitSex.MALE, FitGrade.G12)).assertEqual(100);
      expect(FitScoring.scoreOf(FitTables.R50, 7.0, FitSex.MALE, FitGrade.G12)).assertEqual(85);
      expect(FitScoring.scoreOf(FitTables.R50, 11.0, FitSex.MALE, FitGrade.G12)).assertEqual(0);
    });

    it('sit_negative_values_score', 0, () => {
      expect(FitScoring.scoreOf(FitTables.SIT, -1.3, FitSex.MALE, FitGrade.G12)).assertEqual(10);
      expect(FitScoring.scoreOf(FitTables.SIT, 24.9, FitSex.MALE, FitGrade.G12)).assertEqual(100);
    });

    it('female_tables_differ', 0, () => {
      expect(FitScoring.scoreOf(FitTables.SUP, 56, FitSex.FEMALE, FitGrade.G12)).assertEqual(100);
      expect(FitScoring.scoreOf(FitTables.SUP, 56, FitSex.FEMALE, FitGrade.G34)).assertEqual(95);
      expect(FitScoring.scoreOf(FitTables.PULL, 19, FitSex.FEMALE, FitGrade.G12) === undefined).assertTrue();
    });

    it('plus_tables', 0, () => {
      expect(FitScoring.plusOf(FitTables.PULL_PLUS, 6)).assertEqual(6);
      expect(FitScoring.plusOf(FitTables.PULL_PLUS, 20)).assertEqual(10);
      expect(FitScoring.plusOf(FitTables.PULL_PLUS, 0)).assertEqual(0);
      expect(FitScoring.plusOf(FitTables.DUR_MALE_PLUS, 37)).assertEqual(10);
    });
  });

  describe('FitCalc', () => {
    it('full_male_example', 0, () => {
      const calc: FitCalc = FitScoring.calc(fullInput());
      expect(calc.rows.length).assertEqual(7);
      expect(rowScore(calc, 0)).assertEqual(100); // BMI
      expect(rowScore(calc, 1)).assertEqual(78); // 肺活量
      expect(rowScore(calc, 2)).assertEqual(85); // 50m
      expect(rowScore(calc, 3)).assertEqual(68); // 坐位体前屈
      expect(rowScore(calc, 4)).assertEqual(70); // 立定跳远
      expect(rowScore(calc, 5)).assertEqual(68); // 引体
      expect(rowScore(calc, 6)).assertEqual(72); // 1000m
      expect(calc.std).assertEqual(78.7);
      expect(calc.plus).assertEqual(0);
      expect(calc.total).assertEqual(78.7);
      expect(calc.grade).assertEqual('及格');
      expect(calc.miss).assertEqual(0);
      expect(calc.wtDone).assertEqual(100);
      expect(calc.bmi !== undefined).assertTrue();
      expect(calc.bmiCategory).assertEqual('正常');
    });

    it('bmi_categories', 0, () => {
      const low: FitInput = fullInput();
      low.w = '50';
      expect(FitScoring.calc(low).bmiCategory).assertEqual('低体重');
      const over: FitInput = fullInput();
      over.w = '80';
      expect(FitScoring.calc(over).bmiCategory).assertEqual('超重');
      const obese: FitInput = fullInput();
      obese.w = '95';
      expect(FitScoring.calc(obese).bmiCategory).assertEqual('肥胖');
      expect(FitScoring.calc(obese).rows[0].score).assertEqual(60);
    });

    it('missing_fields_counted_and_weighted', 0, () => {
      const input: FitInput = new FitInput();
      input.sex = FitSex.MALE;
      input.grade = FitGrade.G12;
      input.h = '178';
      input.w = '65';
      const calc: FitCalc = FitScoring.calc(input);
      expect(calc.miss).assertEqual(6);
      expect(calc.wtDone).assertEqual(15);
      expect(calc.std).assertEqual(15);
      expect(calc.grade).assertEqual('不及格');
    });

    it('female_uses_situp_and_800m', 0, () => {
      const input: FitInput = fullInput();
      input.sex = FitSex.FEMALE;
      input.pull = '56';
      input.durM = '4';
      input.durS = '10';
      const calc: FitCalc = FitScoring.calc(input);
      expect(calc.rows[5].name).assertEqual('1 分钟仰卧起坐');
      expect(calc.rows[6].name).assertEqual('800 米跑');
      expect(calc.rows[5].score).assertEqual(100);
    });

    it('plus_points_added', 0, () => {
      const input: FitInput = fullInput();
      input.pull = '25';
      input.durM = '2';
      input.durS = '40';
      const calc: FitCalc = FitScoring.calc(input);
      expect(calc.rows[5].plus).assertEqual(6);
      expect(calc.rows[6].plus).assertEqual(10);
      expect(calc.plus).assertEqual(16);
      expect(calc.total).assertEqual(FitScoring.round10(calc.std + 16));
    });

    it('invalid_values_treated_as_missing', 0, () => {
      const input: FitInput = fullInput();
      input.r50 = '1.0'; // 小于 3 秒，非法
      const calc: FitCalc = FitScoring.calc(input);
      expect(calc.rows[2].score === undefined).assertTrue();
      expect(calc.miss).assertEqual(1);
    });
  });

  describe('FitCodec', () => {
    it('userdata_fit_roundtrip', 0, () => {
      const input: FitInput = fullInput();
      const blob: Blob = FitCodec.toJson(input);
      expect(JsonBlob.keys(blob).join(',')).assertEqual('sex,grade,h,w,vc,r50,sit,jump,pull,durM,durS');
      const back: FitInput = FitCodec.inputFromJson(blob);
      expect(back.sex).assertEqual(FitSex.MALE);
      expect(back.grade).assertEqual(FitGrade.G12);
      expect(back.h).assertEqual('178');
      expect(back.durS).assertEqual('0');
    });

    it('missing_section_defaults', 0, () => {
      const input: FitInput = FitCodec.inputFromJson(undefined);
      expect(input.sex).assertEqual(FitSex.MALE);
      expect(input.grade).assertEqual(FitGrade.G12);
      expect(input.h).assertEqual('');
    });

    it('unknown_fields_preserved', 0, () => {
      const existing: Blob = { 'sex': 'm', 'grade': '12', 'future': 'x' };
      const written: Blob = FitCodec.toJson(fullInput(), existing);
      expect(JsonBlob.asString(JsonBlob.get(written, 'future'), '')).assertEqual('x');
    });

    it('record_roundtrip', 0, () => {
      const record: FitRecord = new FitRecord();
      record.id = 'fit_1';
      record.ts = 1762310000000;
      record.name = '期中';
      record.sex = 'f';
      record.gradeBucket = '34';
      record.fields = fullInput().toFields();
      record.total = 88.5;
      record.grade = '良好';
      const data: string = FitCodec.recordToData(record);
      const back: FitRecord | undefined = FitCodec.recordFromData(data);
      expect(back !== undefined).assertTrue();
      if (back !== undefined) {
        expect(back.id).assertEqual('fit_1');
        expect(back.name).assertEqual('期中');
        expect(back.sexEnum()).assertEqual(FitSex.FEMALE);
        expect(back.gradeEnum()).assertEqual(FitGrade.G34);
        expect(back.fields.r50).assertEqual('7.0');
        expect(back.total).assertEqual(88.5);
        expect(back.grade).assertEqual('良好');
      }
      expect(FitCodec.recordFromData('not-json') === undefined).assertTrue();
    });
  });

  describe('FitHistory', () => {

    it('subset_detection', 0, () => {
      const input: FitInput = fullInput();
      const subset: FitFields = input.toFields();
      const partial: FitFields = new FitRecord().fields;
      partial.h = '178';
      partial.w = '65';
      expect(FitHistory.isSubset(partial, subset)).assertTrue();
      partial.vc = '9999';
      expect(FitHistory.isSubset(partial, subset)).assertFalse();
      const empty: FitFields = new FitRecord().fields;
      expect(FitHistory.isSubset(empty, subset)).assertFalse();
    });

    it('merge_updates_existing_record', 0, () => {
      // 先只记身高体重，再补填其它项 → 旧记录非空项与新记录一致，应合并到同一条
      const partial: FitInput = new FitInput();
      partial.h = '178';
      partial.w = '65';
      const first: SavedHistory = FitHistory.save([], partial, FitScoring.calc(partial), 'id1', 1000, '');
      expect(first.records.length).assertEqual(1);
      expect(first.merged).assertFalse();

      const richer: FitInput = fullInput();
      const second: SavedHistory = FitHistory.save(first.records, richer, FitScoring.calc(richer), 'id2', 2000, '');
      expect(second.merged).assertTrue();
      expect(second.records.length).assertEqual(1);
      expect(second.records[0].id).assertEqual('id1');
      expect(second.records[0].ts).assertEqual(2000);
      expect(second.records[0].fields.vc).assertEqual('4200');
    });

    it('keeps_two_and_reports_dropped', 0, () => {
      const calc: FitCalc = FitScoring.calc(fullInput());
      const a: SavedHistory = FitHistory.save([], fullInput(), calc, 'id1', 1000, '');
      const other: FitInput = fullInput();
      other.sex = FitSex.FEMALE;
      const b: SavedHistory = FitHistory.save(a.records, other, FitScoring.calc(other), 'id2', 2000, '');
      const third: FitInput = new FitInput();
      third.sex = FitSex.MALE;
      third.grade = FitGrade.G34;
      third.h = '180';
      const c: SavedHistory = FitHistory.save(b.records, third, FitScoring.calc(third), 'id3', 3000, '');
      expect(c.records.length).assertEqual(2);
      expect(c.dropped.length).assertEqual(1);
      expect(c.records[0].id).assertEqual('id3');
    });

    it('delete_rename_restore', 0, () => {
      const calc: FitCalc = FitScoring.calc(fullInput());
      const saved: SavedHistory = FitHistory.save([], fullInput(), calc, 'id1', 1000, '');
      const renamed: FitRecord[] = FitHistory.renameAt(saved.records, 0, '  期末体测  ');
      expect(renamed[0].name).assertEqual('期末体测');
      const restored: FitInput | undefined = FitHistory.restoreAt(renamed, 0);
      expect(restored !== undefined).assertTrue();
      if (restored !== undefined) {
        expect(restored.h).assertEqual('178');
        expect(restored.grade).assertEqual(FitGrade.G12);
      }
      expect(FitHistory.deleteAt(renamed, 0).length).assertEqual(0);
    });
  });

  describe('FitExportFactory', () => {
    it('builds_export_spec', 0, () => {
      const calc: FitCalc = FitScoring.calc(fullInput());
      const spec: ExportCardSpec = FitExportFactory.create(calc, fullInput(), new Date(2026, 10, 14, 23, 40).getTime(), 'ab12c');
      expect(spec.title).assertEqual('体测评分结果');
      expect(spec.recordId).assertEqual('FIT-20261114-2340-AB12C');
      expect(spec.fileName).assertEqual('体测评分_20261114-2340_78.7分_及格.png');
      expect(spec.params.length).assertEqual(8);
      expect(spec.lines.length).assertEqual(8);
      expect(spec.lines[0].indexOf('体重指数') === 0).assertTrue();
      expect(spec.lines[7].indexOf('总分 78.7') === 0).assertTrue();
    });
  });
}
