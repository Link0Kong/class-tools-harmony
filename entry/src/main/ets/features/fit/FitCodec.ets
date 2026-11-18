import { Blob, JsonBlob, JsonValue } from '../../data/sync/JsonBlob';
import { FitFields, FitGrade, fitGradeFromWire, FitInput, FitRecord, FitSex, fitSexFromWire } from './FitModels';

/**
 * 体测数据编解码：
 * 1. `userdata.fit` section（11 键：sex/grade + 9 项成绩字符串）；
 * 2. `fitrecs.data` 行：`{id, ts, n, sex, gr, fields{h..durS}, total, grade}` 以 JSON **字符串** 存 `data` 列。
 */
export class FitCodec {
  /** 解析 `userdata.fit`（缺省 → 默认输入；未知字段忽略）。 */
  static inputFromJson(section: JsonValue | undefined): FitInput {
    const obj: Blob | undefined = JsonBlob.asBlob(section);
    const input: FitInput = new FitInput();
    if (obj === undefined) {
      return input;
    }
    input.sex = fitSexFromWire(JsonBlob.asString(JsonBlob.get(obj, 'sex'), 'm'));
    input.grade = fitGradeFromWire(JsonBlob.asString(JsonBlob.get(obj, 'grade'), '12'));
    input.h = JsonBlob.asString(JsonBlob.get(obj, 'h'), '').trim();
    input.w = JsonBlob.asString(JsonBlob.get(obj, 'w'), '').trim();
    input.vc = JsonBlob.asString(JsonBlob.get(obj, 'vc'), '').trim();
    input.r50 = JsonBlob.asString(JsonBlob.get(obj, 'r50'), '').trim();
    input.sit = JsonBlob.asString(JsonBlob.get(obj, 'sit'), '').trim();
    input.jump = JsonBlob.asString(JsonBlob.get(obj, 'jump'), '').trim();
    input.pull = JsonBlob.asString(JsonBlob.get(obj, 'pull'), '').trim();
    input.durM = JsonBlob.asString(JsonBlob.get(obj, 'durM'), '').trim();
    input.durS = JsonBlob.asString(JsonBlob.get(obj, 'durS'), '').trim();
    return input;
  }

  /** 输出 `userdata.fit`：固定键序 `sex, grade, h, w, vc, r50, sit, jump, pull, durM, durS`，保留未知字段。 */
  static toJson(input: FitInput, existing?: Blob): Blob {
    const out: Blob = {
      'sex': input.sex,
      'grade': input.grade,
      'h': input.h,
      'w': input.w,
      'vc': input.vc,
      'r50': input.r50,
      'sit': input.sit,
      'jump': input.jump,
      'pull': input.pull,
      'durM': input.durM,
      'durS': input.durS
    };
    if (existing !== undefined) {
      const keys: string[] = JsonBlob.keys(existing);
      for (let i = 0; i < keys.length; i++) {
        if (JsonBlob.get(out, keys[i]) === undefined) {
          out[keys[i]] = existing[keys[i]];
        }
      }
    }
    return out;
  }

  /** 记录 → `fitrecs.data` JSON 字符串（字段名与契约一致；不含 syncPending）。 */
  static recordToData(record: FitRecord): string {
    const fields: Blob = {
      'h': record.fields.h,
      'w': record.fields.w,
      'vc': record.fields.vc,
      'r50': record.fields.r50,
      'sit': record.fields.sit,
      'jump': record.fields.jump,
      'pull': record.fields.pull,
      'durM': record.fields.durM,
      'durS': record.fields.durS
    };
    const data: Blob = {
      'id': record.id,
      'ts': record.ts,
      'n': record.name,
      'sex': record.sex,
      'gr': record.gradeBucket,
      'fields': fields,
      'total': record.total !== undefined ? record.total : null,
      'grade': record.grade
    };
    return JSON.stringify(data);
  }

  /** 解析 `fitrecs.data` 字符串 → FitRecord；坏 JSON/缺 id → undefined。 */
  static recordFromData(data: string): FitRecord | undefined {
    const obj: Blob | undefined = JsonBlob.parse(data);
    if (obj === undefined) {
      return undefined;
    }
    const id: string = JsonBlob.asString(JsonBlob.get(obj, 'id'), '').trim();
    if (id.length === 0) {
      return undefined;
    }
    const record: FitRecord = new FitRecord();
    record.id = id;
    record.ts = JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0);
    record.name = JsonBlob.asString(JsonBlob.get(obj, 'n'), '');
    record.sex = fitSexFromWire(JsonBlob.asString(JsonBlob.get(obj, 'sex'), 'm'));
    record.gradeBucket = fitGradeFromWire(JsonBlob.asString(JsonBlob.get(obj, 'gr'), '12'));
    record.fields = FitCodec.fieldsFromJson(JsonBlob.get(obj, 'fields'));
    const total: JsonValue | undefined = JsonBlob.get(obj, 'total');
    record.total = typeof total === 'number' ? total as number : undefined;
    record.grade = JsonBlob.asString(JsonBlob.get(obj, 'grade'), '');
    return record;
  }

  static fieldsFromJson(value: JsonValue | undefined): FitFields {
    const obj: Blob | undefined = JsonBlob.asBlob(value);
    const fields: FitFields = new FitFields();
    if (obj === undefined) {
      return fields;
    }
    fields.h = JsonBlob.asString(JsonBlob.get(obj, 'h'), '');
    fields.w = JsonBlob.asString(JsonBlob.get(obj, 'w'), '');
    fields.vc = JsonBlob.asString(JsonBlob.get(obj, 'vc'), '');
    fields.r50 = JsonBlob.asString(JsonBlob.get(obj, 'r50'), '');
    fields.sit = JsonBlob.asString(JsonBlob.get(obj, 'sit'), '');
    fields.jump = JsonBlob.asString(JsonBlob.get(obj, 'jump'), '');
    fields.pull = JsonBlob.asString(JsonBlob.get(obj, 'pull'), '');
    fields.durM = JsonBlob.asString(JsonBlob.get(obj, 'durM'), '');
    fields.durS = JsonBlob.asString(JsonBlob.get(obj, 'durS'), '');
    return fields;
  }

  /** `fitrecs` 行（上传用）：`{id, acc, data, arch:false, ts}`。 */
  static rowForUpload(record: FitRecord, sid: string): Blob {
    const row: Blob = {
      'id': record.id,
      'acc': sid,
      'data': FitCodec.recordToData(record),
      'arch': false,
      'ts': record.ts
    };
    return row;
  }

  /** 记录里的性别/年级（便捷）。 */
  static sexOf(record: FitRecord): FitSex {
    return record.sexEnum();
  }

  static gradeOf(record: FitRecord): FitGrade {
    return record.gradeEnum();
  }
}
