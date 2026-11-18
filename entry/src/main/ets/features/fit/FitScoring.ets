import { FitCalc, FitFieldSpec, FitGrade, FitInput, FitRow, FitSex } from './FitModels';
import { FitPlusTable, FitScoreTable, FitTables } from './FitTables';

/**
 * 体测评分（纯函数，对齐 `mp-class-tools/utils/fit.js ftCalc()` / 网页 fit 实现）。
 *
 * 权重：BMI 15%、肺活量 15%、50m 20%、坐位体前屈 10%、立定跳远 10%、引体/仰卧 10%、长跑 20%（合计 100）；
 * 附加分 ≤20（引体/仰卧、1000/800m 加分表）；等级：≥90 优秀 / ≥80 良好 / ≥60 及格 / <60 不及格；
 * 未填项按缺项计（不计入标准分），并计入 miss。
 */
export class FitScoring {
  /** 数值文本解析：空/非法 → undefined（与 mp `ftNum` 一致）。 */
  static num(text: string): number | undefined {
    const s: string = text.trim();
    if (s.length === 0) {
      return undefined;
    }
    const value: number = Number(s);
    if (!Number.isFinite(value)) {
      return undefined;
    }
    return value;
  }

  /** 长跑「分:秒」→ 秒（两者都空 → undefined；只有一个时另一个按 0）。 */
  static sec(minutesText: string, secondsText: string): number | undefined {
    const m: number | undefined = FitScoring.num(minutesText);
    const s: number | undefined = FitScoring.num(secondsText);
    if (m === undefined && s === undefined) {
      return undefined;
    }
    return (m !== undefined ? m : 0) * 60 + (s !== undefined ? s : 0);
  }

  /** 输入合法性：长跑只要求 >0 秒；其它按 FTRANGE；非法 → undefined（视为缺项）。 */
  static valid(key: string, value: number | undefined): number | undefined {
    if (value === undefined) {
      return undefined;
    }
    if (key === 'dur') {
      return value > 0 ? value : undefined;
    }
    const range: number[] = FitTables.rangeOf(key);
    if (range.length !== 2) {
      return value;
    }
    return value >= range[0] && value <= range[1] ? value : undefined;
  }

  /** 单项得分：任一阈值命中即返回 SCORES[i]；都不命中 → 0。 */
  static scoreOf(table: FitScoreTable, value: number | undefined, sex: FitSex,
    grade: FitGrade): number | undefined {
    if (value === undefined) {
      return undefined;
    }
    const column: number[] = table.column(sex, grade);
    if (column.length === 0) {
      return undefined;
    }
    for (let i = 0; i < column.length; i++) {
      if (table.hi) {
        if (value >= column[i]) {
          return FitTables.SCORES[i];
        }
      } else if (value <= column[i]) {
        return FitTables.SCORES[i];
      }
    }
    return 0;
  }

  /** 附加分：gap 超过表中阈值则取对应加分（gap≤0 → 0）。 */
  static plusOf(table: FitPlusTable | undefined, gap: number): number {
    return table !== undefined ? table.plusFor(gap) : 0;
  }

  /** 秒 → `m'ss"`（与 mp `ftMS` 一致；undefined → `—`）。 */
  static ms(seconds: number | undefined): string {
    if (seconds === undefined) {
      return '—';
    }
    let m: number = Math.floor(seconds / 60);
    let s: number = Math.round(seconds - m * 60);
    if (s >= 60) {
      m += 1;
      s -= 60;
    }
    return m + "'" + (s < 10 ? '0' : '') + s + '"';
  }

  /** 保留 1 位小数（四舍五入）。 */
  static round10(value: number): number {
    return Math.round(value * 10) / 10;
  }

  /** 主计算入口。 */
  static calc(input: FitInput): FitCalc {
    const sex: FitSex = input.sex;
    const grade: FitGrade = input.grade;
    const rows: FitRow[] = [];

    // 1) BMI（15%）
    const h: number | undefined = FitScoring.valid('h', FitScoring.num(input.h));
    const w: number | undefined = FitScoring.valid('w', FitScoring.num(input.w));
    let bmi: number | undefined = undefined;
    let bmiScore: number | undefined = undefined;
    let bmiCategory: string = '';
    if (h !== undefined && w !== undefined && h > 0 && w > 0) {
      const rawBmi: number = w / ((h / 100) * (h / 100));
      bmi = FitScoring.round10(rawBmi);
      const normalStart: number = FitTables.bmiNormalStart(sex);
      if (bmi < normalStart) {
        bmiScore = 80;
        bmiCategory = '低体重';
      } else if (bmi <= FitTables.BMI_NORMAL_END) {
        bmiScore = 100;
        bmiCategory = '正常';
      } else if (bmi <= FitTables.BMI_OBESE) {
        bmiScore = 80;
        bmiCategory = '超重';
      } else {
        bmiScore = 60;
        bmiCategory = '肥胖';
      }
    }
    const bmiRow: FitRow = new FitRow('体重指数', bmiCategory.length > 0 ? 'BMI · ' + bmiCategory : 'BMI',
      15, bmi !== undefined ? bmi.toFixed(1) : '—', bmiScore);
    rows.push(bmiRow);

    // 2) 肺活量（15%）/ 50m（20%）/ 坐位体前屈（10%）/ 立定跳远（10%）
    FitScoring.pushItem(rows, '肺活量', 'mL', 15, input.vc, FitScoring.num(input.vc), FitTables.VC,
      undefined, undefined, 'vc', sex, grade);
    FitScoring.pushItem(rows, '50 米跑', '秒', 20, input.r50, FitScoring.num(input.r50), FitTables.R50,
      undefined, undefined, 'r50', sex, grade);
    FitScoring.pushItem(rows, '坐位体前屈', 'cm', 10, input.sit, FitScoring.num(input.sit), FitTables.SIT,
      undefined, undefined, 'sit', sex, grade);
    FitScoring.pushItem(rows, '立定跳远', 'cm', 10, input.jump, FitScoring.num(input.jump), FitTables.JUMP,
      undefined, undefined, 'jump', sex, grade);

    // 3) 引体向上（男）/ 仰卧起坐（女）（10%，有加分）
    if (sex === FitSex.MALE) {
      const column: number[] = FitTables.PULL.column(sex, grade);
      FitScoring.pushItem(rows, '引体向上', '次', 10, input.pull, FitScoring.num(input.pull), FitTables.PULL,
        FitTables.PULL_PLUS, column[0], 'pull', sex, grade);
    } else {
      const column: number[] = FitTables.SUP.column(sex, grade);
      FitScoring.pushItem(rows, '1 分钟仰卧起坐', '次', 10, input.pull, FitScoring.num(input.pull), FitTables.SUP,
        FitTables.SUP_PLUS, column[0], 'pull', sex, grade);
    }

    // 4) 1000m（男）/ 800m（女）（20%，有加分）
    const durSeconds: number | undefined = FitScoring.valid('dur', FitScoring.sec(input.durM, input.durS));
    const hasDurInput: boolean = FitScoring.num(input.durM) !== undefined || FitScoring.num(input.durS) !== undefined;
    const durRaw: string = hasDurInput ? FitScoring.ms(FitScoring.sec(input.durM, input.durS)) : '';
    const durColumn: number[] = FitTables.DUR.column(sex, grade);
    if (sex === FitSex.MALE) {
      FitScoring.pushItem(rows, '1000 米跑', '分·秒', 20, durRaw, durSeconds, FitTables.DUR,
        FitTables.DUR_MALE_PLUS, durColumn[0], 'dur', sex, grade);
    } else {
      FitScoring.pushItem(rows, '800 米跑', '分·秒', 20, durRaw, durSeconds, FitTables.DUR,
        FitTables.DUR_FEMALE_PLUS, durColumn[0], 'dur', sex, grade);
    }

    // 汇总（由 finalize 统一按 rows 计算，避免重复累计）
    const calc: FitCalc = new FitCalc();
    calc.rows = rows;
    calc.sex = sex;
    calc.gradeBucket = grade;
    calc.h = h;
    calc.w = w;
    calc.bmi = bmi;
    calc.bmiCategory = bmiCategory.length > 0 ? bmiCategory : '';
    return FitScoring.finalize(calc);
  }

  /** BMI 行已单独累计；为保持与安卓一致，这里统一按 rows 重算并写回。 */
  private static finalize(calc: FitCalc): FitCalc {
    let std: number = 0;
    let plus: number = 0;
    let miss: number = 0;
    let wtDone: number = 0;
    for (let i = 0; i < calc.rows.length; i++) {
      const row: FitRow = calc.rows[i];
      if (row.score === undefined) {
        miss += 1;
      } else {
        std += row.score * row.weight / 100;
        plus += row.plus;
        wtDone += row.weight;
      }
    }
    calc.std = FitScoring.round10(std);
    calc.plus = FitScoring.round10(plus);
    calc.total = FitScoring.round10(calc.std + calc.plus);
    calc.totalText = calc.total.toFixed(1);
    calc.miss = miss;
    calc.wtDone = wtDone;
    if (calc.total >= 90) {
      calc.grade = '优秀';
    } else if (calc.total >= 80) {
      calc.grade = '良好';
    } else if (calc.total >= 60) {
      calc.grade = '及格';
    } else {
      calc.grade = '不及格';
    }
    return calc;
  }

  /** 输入清洗：数字字段只保留数字/小数/负号（坐位体前屈允许负），按小数位截断。 */
  static sanitizeInput(text: string, spec: FitFieldSpec): string {
    let filtered: string = '';
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      const code: number = text.charCodeAt(i);
      if (code >= 48 && code <= 57) {
        filtered += ch;
      } else if (ch === '.' && filtered.indexOf('.') < 0) {
        filtered += ch;
      } else if (ch === '-' && spec.allowNegative && filtered.length === 0) {
        filtered += ch;
      }
    }
    if (spec.decimals === 0) {
      const dot: number = filtered.indexOf('.');
      return dot >= 0 ? filtered.substring(0, dot) : filtered;
    }
    const dot: number = filtered.indexOf('.');
    if (dot < 0) {
      return filtered;
    }
    const decimals: string = filtered.substring(dot + 1);
    return filtered.substring(0, dot + 1) + decimals.substring(0, spec.decimals);
  }

  private static pushItem(rows: FitRow[], name: string, unit: string, weight: number, raw: string,
    value: number | undefined, table: FitScoreTable, plusTable: FitPlusTable | undefined,
    topThreshold: number | undefined, key: string, sex: FitSex, grade: FitGrade): void {
    const validValue: number | undefined = FitScoring.valid(key, value);
    const score: number | undefined = FitScoring.scoreOf(table, validValue, sex, grade);
    let plusPoint: number = 0;
    if (score !== undefined && plusTable !== undefined && topThreshold !== undefined && validValue !== undefined) {
      const gap: number = table.hi ? validValue - topThreshold : topThreshold - validValue;
      plusPoint = FitScoring.plusOf(plusTable, gap);
    }
    rows.push(new FitRow(name, unit, weight, raw.trim().length > 0 ? raw : '—', score, plusPoint));
  }
}
