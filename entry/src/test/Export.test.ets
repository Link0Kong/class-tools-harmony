import { describe, it, expect } from '@ohos/hypium';
import {
  DrawConfig,
  DrawEntry,
  DrawPoolSource,
  DrawRemoveLog,
  DrawResult,
  DrawSortMode
} from '../main/ets/features/draw/DrawModels';
import { DrawExportFactory, ExportCardSpec, ExportNaming, ExportParam } from '../main/ets/features/export/ExportCard';

const NOW: number = new Date(2026, 10, 14, 22, 30, 0).getTime();

function sampleConfig(): DrawConfig {
  const config: DrawConfig = new DrawConfig();
  config.start = 1;
  config.end = 50;
  config.count = 3;
  config.excludedText = '5';
  config.sort = DrawSortMode.ASCENDING;
  return config;
}

function sampleResult(): DrawResult {
  const result: DrawResult = new DrawResult();
  result.config = sampleConfig();
  result.entries = [new DrawEntry(7, '张三'), new DrawEntry(9, ''), new DrawEntry(12, '李四')];
  const pool: DrawEntry[] = [];
  for (let n = 1; n <= 50; n++) {
    if (n !== 5) {
      pool.push(new DrawEntry(n, ''));
    }
  }
  result.pool = pool;
  result.log = [new DrawRemoveLog(new DrawEntry(3, '王五'), new DrawEntry(8, '赵六'))];
  return result;
}

function paramValue(spec: ExportCardSpec, label: string): string {
  for (let i = 0; i < spec.params.length; i++) {
    if (spec.params[i].label === label) {
      return spec.params[i].value;
    }
  }
  return '';
}

export default function exportTest() {
  describe('ExportNaming', () => {
    it('stamp_and_time_use_local_format', 0, () => {
      expect(ExportNaming.stamp(NOW)).assertEqual('20261114-2230');
      expect(ExportNaming.timeText(NOW)).assertEqual('2026-11-14 22:30');
    });

    it('record_id_uppercases_suffix', 0, () => {
      expect(ExportNaming.recordId('DRAW', NOW, 'ab12c')).assertEqual('DRAW-20261114-2230-AB12C');
    });

    it('safe_name_replaces_illegal_chars', 0, () => {
      expect(ExportNaming.safeName('a/b:c*d?"e<f>g|h.png')).assertEqual('a_b_c_d__e_f_g_h.png');
    });

    it('random_suffix_is_5_chars', 0, () => {
      expect(ExportNaming.randomSuffix().length).assertEqual(5);
    });
  });

  describe('DrawExportFactory', () => {
    it('file_name_matches_spec', 0, () => {
      const spec: ExportCardSpec = DrawExportFactory.create(sampleResult(), NOW, 'abc12');
      expect(spec.fileName).assertEqual('抽签结果_20261114-2230_范围1-50_抽3个_不重复_从小到大.png');
    });

    it('duplicates_and_random_sort_are_reflected', 0, () => {
      const result: DrawResult = sampleResult();
      result.config.allowDuplicates = true;
      result.config.sort = DrawSortMode.RANDOM;
      const spec: ExportCardSpec = DrawExportFactory.create(result, NOW, 'AA111');
      expect(spec.fileName.indexOf('允许重复') > 0).assertTrue();
      expect(spec.fileName.indexOf('随机') > 0).assertTrue();
    });

    it('record_id_and_footer', 0, () => {
      const spec: ExportCardSpec = DrawExportFactory.create(sampleResult(), NOW, 'xyz99');
      expect(spec.recordId).assertEqual('DRAW-20261114-2230-XYZ99');
      expect(spec.footer).assertEqual('生成时间 2026-11-14 22:30');
      expect(spec.generatedAt).assertEqual(NOW);
    });

    it('params_cover_draw_fields', 0, () => {
      const spec: ExportCardSpec = DrawExportFactory.create(sampleResult(), NOW, 'abc12');
      expect(spec.params.length).assertEqual(6);
      expect(paramValue(spec, '范围')).assertEqual('1 – 50');
      expect(paramValue(spec, '抽取个数')).assertEqual('3');
      expect(paramValue(spec, '允许重复')).assertEqual('否');
      expect(paramValue(spec, '排除序号')).assertEqual('5');
      expect(paramValue(spec, '结果排序')).assertEqual('从小到大');
      expect(paramValue(spec, '可用池')).assertEqual('共 49 个');
    });

    it('roster_source_adds_extra_param', 0, () => {
      const result: DrawResult = sampleResult();
      result.config.poolSource = DrawPoolSource.ROSTER;
      const spec: ExportCardSpec = DrawExportFactory.create(result, NOW, 'abc12');
      expect(spec.params.length).assertEqual(7);
      expect(paramValue(spec, '候选来源')).assertEqual('班级名单');
    });

    it('chips_keep_numbers_and_names', 0, () => {
      const spec: ExportCardSpec = DrawExportFactory.create(sampleResult(), NOW, 'abc12');
      expect(spec.chips.length).assertEqual(3);
      expect(spec.chips[0].n).assertEqual(7);
      expect(spec.chips[0].nm).assertEqual('张三');
      expect(spec.chips[1].nm).assertEqual('');
    });

    it('remove_log_lines_render_labels', 0, () => {
      const result: DrawResult = sampleResult();
      result.log.push(new DrawRemoveLog(new DrawEntry(20, ''), undefined));
      const spec: ExportCardSpec = DrawExportFactory.create(result, NOW, 'abc12');
      expect(spec.noteLines.length).assertEqual(2);
      expect(spec.noteLines[0]).assertEqual('#1 剔除 3 王五 → 重抽 8 赵六');
      expect(spec.noteLines[1]).assertEqual('#2 剔除 20 → 重抽 （未补抽）');
    });

    it('title_and_subtitle', 0, () => {
      const spec: ExportCardSpec = DrawExportFactory.create(sampleResult(), NOW, 'abc12');
      expect(spec.title).assertEqual('随机抽签结果');
      expect(spec.subtitle).assertEqual('共 3 个 · 范围 1–50');
      expect(spec.chipLabel).assertEqual('抽签结果');
    });

    it('no_remove_log_keeps_notes_empty', 0, () => {
      const result: DrawResult = sampleResult();
      result.log = [];
      const spec: ExportCardSpec = DrawExportFactory.create(result, NOW, 'abc12');
      expect(spec.noteLines.length).assertEqual(0);
    });
  });
}
