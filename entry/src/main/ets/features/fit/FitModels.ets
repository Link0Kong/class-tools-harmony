/** 性别。 */
export enum FitSex {
  MALE = 'm',
  FEMALE = 'f'
}

export function fitSexFromWire(wire: string): FitSex {
  return wire.trim() === 'f' ? FitSex.FEMALE : FitSex.MALE;
}

export function fitSexLabel(sex: FitSex): string {
  return sex === FitSex.FEMALE ? '女' : '男';
}

/** 年级档（大学组：大一/大二、大三/大四）。 */
export enum FitGrade {
  G12 = '12',
  G34 = '34'
}

export function fitGradeFromWire(wire: string): FitGrade {
  return wire.trim() === '34' ? FitGrade.G34 : FitGrade.G12;
}

export function fitGradeLabel(grade: FitGrade): string {
  return grade === FitGrade.G34 ? '大三 / 大四' : '大一 / 大二';
}

/** 表单字段元数据（UI 渲染 + 输入清洗；durM/durS 单独成对展示）。 */
export class FitFieldSpec {
  key: string;
  label: string;
  unit: string;
  /** 小数位（0 = 整数）。 */
  decimals: number;
  /** 是否允许负数（坐位体前屈）。 */
  allowNegative: boolean;

  constructor(key: string, label: string, unit: string, decimals: number, allowNegative: boolean = false) {
    this.key = key;
    this.label = label;
    this.unit = unit;
    this.decimals = decimals;
    this.allowNegative = allowNegative;
  }
}

/** 单项字段（身高~引体/仰卧；长跑拆 durM/durS）。 */
export const FIT_INPUT_FIELDS: FitFieldSpec[] = [
  new FitFieldSpec('h', '身高', 'cm', 1),
  new FitFieldSpec('w', '体重', 'kg', 1),
  new FitFieldSpec('vc', '肺活量', 'mL', 0),
  new FitFieldSpec('r50', '50 米跑', '秒', 2),
  new FitFieldSpec('sit', '坐位体前屈', 'cm', 1, true),
  new FitFieldSpec('jump', '立定跳远', 'cm', 0),
  new FitFieldSpec('pull', '引体 / 仰卧起坐', '次', 0)
];

/** 表单输入（与 `userdata.fit` 的 11 个键一一对应，值保留字符串以便原样回填）。 */
export class FitInput {
  /** `userdata.fit` 的固定 9 个成绩键（sex/grade 另有）。 */
  static readonly KEYS: string[] = ['h', 'w', 'vc', 'r50', 'sit', 'jump', 'pull', 'durM', 'durS'];

  sex: FitSex = FitSex.MALE;
  grade: FitGrade = FitGrade.G12;
  h: string = '';
  w: string = '';
  vc: string = '';
  r50: string = '';
  sit: string = '';
  jump: string = '';
  pull: string = '';
  durM: string = '';
  durS: string = '';

  valueOf(key: string): string {
    if (key === 'h') {
      return this.h;
    }
    if (key === 'w') {
      return this.w;
    }
    if (key === 'vc') {
      return this.vc;
    }
    if (key === 'r50') {
      return this.r50;
    }
    if (key === 'sit') {
      return this.sit;
    }
    if (key === 'jump') {
      return this.jump;
    }
    if (key === 'pull') {
      return this.pull;
    }
    if (key === 'durM') {
      return this.durM;
    }
    if (key === 'durS') {
      return this.durS;
    }
    return '';
  }

  withValue(key: string, value: string): FitInput {
    const next: FitInput = this.copy();
    if (key === 'h') {
      next.h = value;
    } else if (key === 'w') {
      next.w = value;
    } else if (key === 'vc') {
      next.vc = value;
    } else if (key === 'r50') {
      next.r50 = value;
    } else if (key === 'sit') {
      next.sit = value;
    } else if (key === 'jump') {
      next.jump = value;
    } else if (key === 'pull') {
      next.pull = value;
    } else if (key === 'durM') {
      next.durM = value;
    } else if (key === 'durS') {
      next.durS = value;
    }
    return next;
  }

  hasAny(): boolean {
    for (let i = 0; i < FitInput.KEYS.length; i++) {
      if (this.valueOf(FitInput.KEYS[i]).trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  toFields(): FitFields {
    const fields: FitFields = new FitFields();
    fields.h = this.h;
    fields.w = this.w;
    fields.vc = this.vc;
    fields.r50 = this.r50;
    fields.sit = this.sit;
    fields.jump = this.jump;
    fields.pull = this.pull;
    fields.durM = this.durM;
    fields.durS = this.durS;
    return fields;
  }

  copy(): FitInput {
    const next: FitInput = new FitInput();
    next.sex = this.sex;
    next.grade = this.grade;
    next.h = this.h;
    next.w = this.w;
    next.vc = this.vc;
    next.r50 = this.r50;
    next.sit = this.sit;
    next.jump = this.jump;
    next.pull = this.pull;
    next.durM = this.durM;
    next.durS = this.durS;
    return next;
  }

  static fromFields(sex: FitSex, grade: FitGrade, fields: FitFields): FitInput {
    const input: FitInput = new FitInput();
    input.sex = sex;
    input.grade = grade;
    input.h = fields.h;
    input.w = fields.w;
    input.vc = fields.vc;
    input.r50 = fields.r50;
    input.sit = fields.sit;
    input.jump = fields.jump;
    input.pull = fields.pull;
    input.durM = fields.durM;
    input.durS = fields.durS;
    return input;
  }
}

/** 一项评分结果。 */
export class FitRow {
  name: string;
  /** 单位或备注（mL / 秒 / BMI · 正常…）。 */
  sub: string;
  /** 权重（百分比整数，总分 100）。 */
  weight: number;
  /** 原始输入展示（未填 `—`）。 */
  value: string;
  /** 等级分（undefined = 缺项或非法）。 */
  score: number | undefined;
  /** 加分（引体/仰卧/长跑）。 */
  plus: number;

  constructor(name: string, sub: string, weight: number, value: string, score: number | undefined,
    plus: number = 0) {
    this.name = name;
    this.sub = sub;
    this.weight = weight;
    this.value = value;
    this.score = score;
    this.plus = plus;
  }
}

/** 一次完整计算。 */
export class FitCalc {
  rows: FitRow[] = [];
  /** 标准分（Σ 单项分×权重/100，1 位小数）。 */
  std: number = 0;
  plus: number = 0;
  total: number = 0;
  totalText: string = '';
  /** 等级：优秀/良好/及格/不及格。 */
  grade: string = '';
  miss: number = 0;
  /** 已填项权重合计。 */
  wtDone: number = 0;
  sex: FitSex = FitSex.MALE;
  gradeBucket: FitGrade = FitGrade.G12;
  h: number | undefined = undefined;
  w: number | undefined = undefined;
  bmi: number | undefined = undefined;
  bmiCategory: string = '';
}

/** 历史记录里的成绩字段（9 项字符串，与 fitrecs.data.fields 一致）。 */
export class FitFields {
  h: string = '';
  w: string = '';
  vc: string = '';
  r50: string = '';
  sit: string = '';
  jump: string = '';
  pull: string = '';
  durM: string = '';
  durS: string = '';

  isEmpty(): boolean {
    return this.h.trim().length === 0 && this.w.trim().length === 0 && this.vc.trim().length === 0
      && this.r50.trim().length === 0 && this.sit.trim().length === 0 && this.jump.trim().length === 0
      && this.pull.trim().length === 0 && this.durM.trim().length === 0 && this.durS.trim().length === 0;
  }

  valueOf(key: string): string {
    if (key === 'h') {
      return this.h;
    }
    if (key === 'w') {
      return this.w;
    }
    if (key === 'vc') {
      return this.vc;
    }
    if (key === 'r50') {
      return this.r50;
    }
    if (key === 'sit') {
      return this.sit;
    }
    if (key === 'jump') {
      return this.jump;
    }
    if (key === 'pull') {
      return this.pull;
    }
    if (key === 'durM') {
      return this.durM;
    }
    if (key === 'durS') {
      return this.durS;
    }
    return '';
  }
}

/**
 * 一条体测历史记录（= `fitrecs.data` JSON 解析后的结构；本机/云端最多 2 条）。
 * 序列化字段：`id, ts, n, sex, gr, fields, total, grade`。
 */
export class FitRecord {
  static readonly MAX_RECORDS: number = 2;

  id: string = '';
  ts: number = 0;
  name: string = '';
  sex: string = 'm';
  gradeBucket: string = '12';
  fields: FitFields = new FitFields();
  total: number | undefined = undefined;
  grade: string = '';
  syncPending: boolean = false;

  sexEnum(): FitSex {
    return fitSexFromWire(this.sex);
  }

  gradeEnum(): FitGrade {
    return fitGradeFromWire(this.gradeBucket);
  }

  displayName(): string {
    return this.name.trim().length > 0 ? this.name : '体测 ' + this.timeText();
  }

  /** `MM-dd HH:mm`（本地时区）。 */
  timeText(): string {
    if (this.ts <= 0) {
      return '—';
    }
    const d: Date = new Date(this.ts);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  totalText(): string {
    return this.total !== undefined ? this.total.toFixed(1) : '—';
  }

  /** 成绩明细（与小程序 recDetail 文案一致）。 */
  detailText(): string {
    const parts: string[] = [];
    const f: FitFields = this.fields;
    if (f.h.trim().length > 0) {
      parts.push('身高 ' + f.h + 'cm');
    }
    if (f.w.trim().length > 0) {
      parts.push('体重 ' + f.w + 'kg');
    }
    if (f.vc.trim().length > 0) {
      parts.push('肺活量 ' + f.vc + 'mL');
    }
    if (f.r50.trim().length > 0) {
      parts.push('50米 ' + f.r50 + 's');
    }
    if (f.sit.trim().length > 0) {
      parts.push('坐位 ' + f.sit + 'cm');
    }
    if (f.jump.trim().length > 0) {
      parts.push('跳远 ' + f.jump + 'cm');
    }
    if (f.pull.trim().length > 0) {
      parts.push((this.sexEnum() === FitSex.FEMALE ? '仰卧 ' : '引体 ') + f.pull + '次');
    }
    if (f.durM.trim().length > 0 || f.durS.trim().length > 0) {
      const m: string = f.durM.trim().length > 0 ? f.durM : '0';
      const s: string = pad2(Number(f.durS.trim().length > 0 ? f.durS : '0'));
      parts.push("长跑 " + m + "'" + s + '"');
    }
    return parts.length > 0 ? parts.join(' · ') : '（无成绩明细）';
  }
}

/** 历史保存结果。 */
export class SavedHistory {
  records: FitRecord[] = [];
  dropped: FitRecord[] = [];
  merged: boolean = false;
  record: FitRecord | undefined = undefined;
}

/** 体测历史逻辑（纯函数，对齐小程序 saveRec/findMergeIndex）。 */
export class FitHistory {
  /** 旧记录的非空项是否都是新记录同项的子集（且旧记录至少有一项非空）。 */
  static isSubset(oldFields: FitFields, newFields: FitFields): boolean {
    let any: boolean = false;
    for (let i = 0; i < FitInput.KEYS.length; i++) {
      const key: string = FitInput.KEYS[i];
      const oldValue: string = oldFields.valueOf(key).trim();
      const newValue: string = newFields.valueOf(key).trim();
      if (oldValue.length > 0) {
        any = true;
        if (oldValue !== newValue) {
          return false;
        }
      }
    }
    return any;
  }

  static findMergeIndex(records: FitRecord[], newFields: FitFields, sex: FitSex, grade: FitGrade): number {
    for (let i = 0; i < records.length; i++) {
      if (records[i].sexEnum() !== sex || records[i].gradeEnum() !== grade) {
        continue;
      }
      if (FitHistory.isSubset(records[i].fields, newFields)) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 保存一条记录：可合并则更新旧记录（移到最前）；否则新建；结果截断到 2 条（多出的进 dropped）。
   */
  static save(records: FitRecord[], input: FitInput, calc: FitCalc, id: string, now: number,
    name: string): SavedHistory {
    const fields: FitFields = input.toFields();
    const mergeAt: number = FitHistory.findMergeIndex(records, fields, input.sex, input.grade);
    const working: FitRecord[] = records.slice(0);
    const saved: SavedHistory = new SavedHistory();
    let mergedRecord: FitRecord;
    if (mergeAt >= 0) {
      const old: FitRecord = working[mergeAt];
      working.splice(mergeAt, 1);
      mergedRecord = old;
      mergedRecord.ts = now;
      if (old.name.trim().length === 0) {
        mergedRecord.name = name;
      }
      mergedRecord.sex = input.sex;
      mergedRecord.gradeBucket = input.grade;
      mergedRecord.fields = fields;
      mergedRecord.total = calc.total;
      mergedRecord.grade = calc.grade;
      mergedRecord.syncPending = true;
      saved.merged = true;
    } else {
      mergedRecord = new FitRecord();
      mergedRecord.id = id;
      mergedRecord.ts = now;
      mergedRecord.name = name;
      mergedRecord.sex = input.sex;
      mergedRecord.gradeBucket = input.grade;
      mergedRecord.fields = fields;
      mergedRecord.total = calc.total;
      mergedRecord.grade = calc.grade;
      mergedRecord.syncPending = true;
      saved.merged = false;
    }
    working.unshift(mergedRecord);
    saved.records = working.slice(0, FitRecord.MAX_RECORDS);
    saved.dropped = working.length > FitRecord.MAX_RECORDS ? working.slice(FitRecord.MAX_RECORDS) : [];
    saved.record = mergedRecord;
    return saved;
  }

  static deleteAt(records: FitRecord[], index: number): FitRecord[] {
    if (index < 0 || index >= records.length) {
      return records;
    }
    const out: FitRecord[] = records.slice(0);
    out.splice(index, 1);
    return out;
  }

  static renameAt(records: FitRecord[], index: number, newName: string): FitRecord[] {
    if (index < 0 || index >= records.length) {
      return records;
    }
    const name: string = newName.trim().substring(0, 24);
    if (name.length === 0) {
      return records;
    }
    const out: FitRecord[] = records.slice(0);
    out[index].name = name;
    return out;
  }

  static restoreAt(records: FitRecord[], index: number): FitInput | undefined {
    if (index < 0 || index >= records.length) {
      return undefined;
    }
    const record: FitRecord = records[index];
    return FitInput.fromFields(record.sexEnum(), record.gradeEnum(), record.fields);
  }
}

export function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
