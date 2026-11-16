import { DrawEntry, DrawResult, DrawPoolSource, drawSortLabel } from '../draw/DrawModels';
import { FitCalc, FitInput, FitRow, fitGradeLabel, fitSexLabel } from '../fit/FitModels';
import { GroupResult, MemberGroup } from '../group/GroupModels';

/** 导出卡「参数配置」一行。 */
export class ExportParam {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** 导出卡结果胶囊（抽签号码 + 可选姓名）。 */
export class ExportChip {
  n: number;
  nm: string;

  constructor(n: number, nm: string) {
    this.n = n;
    this.nm = nm;
  }
}

/**
 * 导出卡 v2 数据（`export_card_v2_spec.md`）。
 *
 * 硬约束：参数配置区 + 斜向平铺水印 + 页脚生成时间 + 唯一编号；
 * 不出现手机号/学号/宿舍号；命名 `<类型>_<YYYYMMDD-HHMM>_<参数>.png`。
 */
export class ExportCardSpec {
  title: string = '';
  subtitle: string = '';
  /** 唯一编号（recId）。 */
  recordId: string = '';
  /** 文件名（含扩展名）。 */
  fileName: string = '';
  params: ExportParam[] = [];
  chipLabel: string = '抽签结果';
  chips: ExportChip[] = [];
  /** 分组结果（两列组卡；与 chips 二选一）。 */
  groupLabel: string = '分组结果';
  groups: ExportChip[][] = [];
  /** 文本块（体测评分明细等）。 */
  linesLabel: string = '';
  lines: string[] = [];
  /** 剔除重抽记录（文本行）。 */
  noteLabel: string = '剔除重抽';
  noteLines: string[] = [];
  /** 页脚（生成时间）。 */
  footer: string = '';
  generatedAt: number = 0;
}

/** 命名/编号工具（纯函数，时间与随机后缀可注入，便于单测）。 */
export class ExportNaming {
  static pad2(value: number): string {
    return value < 10 ? '0' + value : '' + value;
  }

  /** `YYYYMMDD-HHMM`（本地时区，与网页一致）。 */
  static stamp(now: number): string {
    const d: Date = new Date(now);
    return '' + d.getFullYear() + ExportNaming.pad2(d.getMonth() + 1) + ExportNaming.pad2(d.getDate())
      + '-' + ExportNaming.pad2(d.getHours()) + ExportNaming.pad2(d.getMinutes());
  }

  /** `YYYY-MM-DD HH:mm`（页脚展示）。 */
  static timeText(now: number): string {
    const d: Date = new Date(now);
    return '' + d.getFullYear() + '-' + ExportNaming.pad2(d.getMonth() + 1) + '-' + ExportNaming.pad2(d.getDate())
      + ' ' + ExportNaming.pad2(d.getHours()) + ':' + ExportNaming.pad2(d.getMinutes());
  }

  /** `DRAW-20261114-2230-ABC12` 形式的唯一编号。 */
  static recordId(prefix: string, now: number, suffix: string): string {
    return prefix + '-' + ExportNaming.stamp(now) + '-' + suffix.toUpperCase();
  }

  /** 文件名安全化（去掉 Windows/相册不允许的字符）。 */
  static safeName(raw: string): string {
    return raw.replace(new RegExp('[\\\\/:*?"<>|]', 'g'), '_');
  }

  static randomSuffix(): string {
    const chars: string = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    let out: string = '';
    for (let i = 0; i < 5; i++) {
      out += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return out;
  }
}

/** 抽签导出数据工厂（纯函数）。 */
export class DrawExportFactory {
  static create(result: DrawResult, now: number, suffix: string): ExportCardSpec {
    const config = result.config;
    const stamp: string = ExportNaming.stamp(now);
    const spec: ExportCardSpec = new ExportCardSpec();
    spec.title = '随机抽签结果';
    spec.subtitle = '共 ' + result.entries.length + ' 个 · 范围 ' + config.start + '–' + config.end;
    spec.recordId = ExportNaming.recordId('DRAW', now, suffix);
    spec.fileName = ExportNaming.safeName('抽签结果_' + stamp
      + '_范围' + config.start + '-' + config.end
      + '_抽' + config.count + '个'
      + '_' + (config.allowDuplicates ? '允许重复' : '不重复')
      + '_' + drawSortLabel(config.sort) + '.png');
    spec.params = DrawExportFactory.configFields(result);
    spec.chipLabel = '抽签结果';
    spec.chips = DrawExportFactory.chips(result.entries);
    spec.noteLines = DrawExportFactory.removeLines(result);
    spec.footer = '生成时间 ' + ExportNaming.timeText(now);
    spec.generatedAt = now;
    return spec;
  }

  static chips(entries: DrawEntry[]): ExportChip[] {
    const out: ExportChip[] = [];
    for (let i = 0; i < entries.length; i++) {
      out.push(new ExportChip(entries[i].number, entries[i].name));
    }
    return out;
  }

  static removeLines(result: DrawResult): string[] {
    const out: string[] = [];
    for (let i = 0; i < result.log.length; i++) {
      const removed: DrawEntry = result.log[i].removed;
      const added: DrawEntry | undefined = result.log[i].added;
      out.push('#' + (i + 1) + ' 剔除 ' + removed.label()
        + ' → 重抽 ' + (added !== undefined ? added.label() : '（未补抽）'));
    }
    return out;
  }

  static configFields(result: DrawResult): ExportParam[] {
    const config = result.config;
    const fields: ExportParam[] = [
      new ExportParam('范围', config.start + ' – ' + config.end),
      new ExportParam('抽取个数', '' + config.count),
      new ExportParam('允许重复', config.allowDuplicates ? '是' : '否'),
      new ExportParam('排除序号', config.excludedText.trim().length > 0 ? config.excludedText : '无'),
      new ExportParam('结果排序', drawSortLabel(config.sort)),
      new ExportParam('可用池', '共 ' + result.pool.length + ' 个')
    ];
    if (config.poolSource === DrawPoolSource.ROSTER) {
      fields.push(new ExportParam('候选来源', '班级名单'));
    }
    return fields;
  }
}

/** 分组导出数据工厂（纯函数）。 */
export class GroupExportFactory {
  static create(result: GroupResult, now: number, suffix: string): ExportCardSpec {
    const stamp: string = ExportNaming.stamp(now);
    const snapshot = result.snapshot;
    const spec: ExportCardSpec = new ExportCardSpec();
    spec.title = '随机分组结果';
    spec.subtitle = '共 ' + snapshot.total + ' 人 · ' + snapshot.groupCount + ' 组';
    spec.recordId = ExportNaming.recordId('GROUP', now, suffix);
    spec.fileName = ExportNaming.safeName('分组结果_' + stamp
      + '_' + snapshot.total + '人_' + snapshot.groupCount + '组'
      + '_' + (result.config.shuffle ? '打乱' : '原顺序') + '.png');
    spec.params = GroupExportFactory.configFields(result);
    spec.groupLabel = '分组结果';
    spec.groups = GroupExportFactory.groups(result);
    spec.footer = '生成时间 ' + ExportNaming.timeText(now);
    spec.generatedAt = now;
    return spec;
  }

  static groups(result: GroupResult): ExportChip[][] {
    const out: ExportChip[][] = [];
    for (let i = 0; i < result.groups.length; i++) {
      const group: MemberGroup = result.groups[i];
      const chips: ExportChip[] = [];
      for (let j = 0; j < group.members.length; j++) {
        chips.push(new ExportChip(group.members[j].seat, group.members[j].name));
      }
      out.push(chips);
    }
    return out;
  }

  static configFields(result: GroupResult): ExportParam[] {
    const snapshot = result.snapshot;
    return [
      new ExportParam('成员来源', snapshot.sourceLabel),
      new ExportParam('分组方式', snapshot.modeLabel),
      new ExportParam('成员数', '' + snapshot.total),
      new ExportParam('组数', '' + snapshot.groupCount),
      new ExportParam('分配方式', snapshot.innerLabel)
    ];
  }
}

/** 体测导出数据工厂（纯函数）。 */
export class FitExportFactory {
  static create(calc: FitCalc, input: FitInput, now: number, suffix: string): ExportCardSpec {
    const stamp: string = ExportNaming.stamp(now);
    const spec: ExportCardSpec = new ExportCardSpec();
    spec.title = '体测评分结果';
    spec.subtitle = fitSexLabel(calc.sex) + ' · ' + fitGradeLabel(calc.gradeBucket)
      + ' · 总分 ' + calc.totalText + '（' + calc.grade + '）';
    spec.recordId = ExportNaming.recordId('FIT', now, suffix);
    spec.fileName = ExportNaming.safeName('体测评分_' + stamp + '_' + calc.totalText + '分_' + calc.grade + '.png');
    spec.params = FitExportFactory.configFields(calc, input);
    spec.linesLabel = '评分明细';
    spec.lines = FitExportFactory.lines(calc);
    spec.footer = '生成时间 ' + ExportNaming.timeText(now);
    spec.generatedAt = now;
    return spec;
  }

  static configFields(calc: FitCalc, input: FitInput): ExportParam[] {
    const params: ExportParam[] = [
      new ExportParam('性别', fitSexLabel(calc.sex)),
      new ExportParam('年级', fitGradeLabel(calc.gradeBucket)),
      new ExportParam('身高', input.h.trim().length > 0 ? input.h + ' cm' : '—'),
      new ExportParam('体重', input.w.trim().length > 0 ? input.w + ' kg' : '—'),
      new ExportParam('体重指数', calc.bmi !== undefined
        ? calc.bmi.toFixed(1) + (calc.bmiCategory.length > 0 ? '（' + calc.bmiCategory + '）' : '')
        : '—'),
      new ExportParam('标准分', calc.std.toFixed(1)),
      new ExportParam('附加分', calc.plus.toFixed(1)),
      new ExportParam('已测权重', calc.wtDone + ' / 100')
    ];
    return params;
  }

  static lines(calc: FitCalc): string[] {
    const lines: string[] = [];
    for (let i = 0; i < calc.rows.length; i++) {
      const row: FitRow = calc.rows[i];
      const scoreText: string = row.score !== undefined ? '' + row.score : '缺项';
      const plusText: string = row.plus > 0 ? '（加 ' + row.plus + '）' : '';
      lines.push(row.name + '  ' + row.value + ' ' + row.sub + ' · ' + row.weight + '% · '
        + scoreText + ' 分' + plusText);
    }
    lines.push('总分 ' + calc.totalText + ' · ' + calc.grade
      + (calc.miss > 0 ? ' · 缺 ' + calc.miss + ' 项' : ''));
    return lines;
  }
}
