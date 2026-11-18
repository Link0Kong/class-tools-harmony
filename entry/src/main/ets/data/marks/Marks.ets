import { Blob, JsonBlob } from '../sync/JsonBlob';

/** marks 三种 kind（契约 §5）：作业完成 / 通知置顶 / 通知已处理。 */
export enum MarkKind {
  HW = 'hw',
  NT = 'nt',
  NT_DONE = 'ntdone'
}

export function markKindFromWire(wire: string): MarkKind | undefined {
  if (wire === 'hw') {
    return MarkKind.HW;
  }
  if (wire === 'nt') {
    return MarkKind.NT;
  }
  if (wire === 'ntdone') {
    return MarkKind.NT_DONE;
  }
  return undefined;
}

/**
 * `public.marks` 一行。
 *
 * `id = "<sid>|<kind>|<ref>"`；`seat` = 学号（服务端 RLS 校验本人）；取消只写 `val=false`，绝不 DELETE。
 * 注意：`value` 的 JSON 字段名是 **`val`**（SQL 保留字规避），不要改。
 */
export class MarkRow {
  id: string = '';
  seat: string = '';
  kind: string = '';
  ref: string = '';
  value: boolean = false;
  ts: number = 0;

  constructor(id: string = '', seat: string = '', kind: string = '', ref: string = '',
    value: boolean = false, ts: number = 0) {
    this.id = id;
    this.seat = seat;
    this.kind = kind;
    this.ref = ref;
    this.value = value;
    this.ts = ts;
  }

  static idOf(sid: string, kind: MarkKind, ref: string): string {
    return sid + '|' + kind + '|' + ref;
  }

  toJson(): Blob {
    const out: Blob = {
      'id': this.id,
      'seat': this.seat,
      'kind': this.kind,
      'ref': this.ref,
      'val': this.value,
      'ts': this.ts
    };
    return out;
  }

  static fromJson(obj: Blob): MarkRow | undefined {
    const id: string = JsonBlob.asString(JsonBlob.get(obj, 'id'), '');
    const ref: string = JsonBlob.asString(JsonBlob.get(obj, 'ref'), '');
    if (id.length === 0 || ref.length === 0) {
      return undefined;
    }
    const row: MarkRow = new MarkRow(
      id,
      JsonBlob.asString(JsonBlob.get(obj, 'seat'), ''),
      JsonBlob.asString(JsonBlob.get(obj, 'kind'), ''),
      ref,
      JsonBlob.asBoolean(JsonBlob.get(obj, 'val'), false),
      JsonBlob.asNumber(JsonBlob.get(obj, 'ts'), 0)
    );
    return row;
  }
}

/** 本机 marks 视图（只保留 true 的项，等价 web `HW.marks` / `NT.marks` / `NT.done`）。 */
export class MarksSnapshot {
  hwDone: Set<string> = new Set<string>();
  ntPin: Set<string> = new Set<string>();
  ntDone: Set<string> = new Set<string>();

  isDone(kind: MarkKind, ref: string): boolean {
    if (kind === MarkKind.HW) {
      return this.hwDone.has(ref);
    }
    if (kind === MarkKind.NT) {
      return this.ntPin.has(ref);
    }
    return this.ntDone.has(ref);
  }

  with(kind: MarkKind, ref: string, value: boolean): MarksSnapshot {
    const next: MarksSnapshot = new MarksSnapshot();
    next.hwDone = copySet(this.hwDone);
    next.ntPin = copySet(this.ntPin);
    next.ntDone = copySet(this.ntDone);
    const target: Set<string> = kind === MarkKind.HW ? next.hwDone : (kind === MarkKind.NT ? next.ntPin : next.ntDone);
    if (value) {
      target.add(ref);
    } else {
      target.delete(ref);
    }
    return next;
  }

  /** 整表覆盖（服务端下发）；只收 true，缺少即未做。 */
  replaceRows(rows: MarkRow[]): MarksSnapshot {
    let snapshot: MarksSnapshot = this;
    for (let i = 0; i < rows.length; i++) {
      const row: MarkRow = rows[i];
      if (row.ref.length === 0) {
        continue;
      }
      const kind: MarkKind | undefined = markKindFromWire(row.kind);
      if (kind === undefined) {
        continue;
      }
      snapshot = snapshot.with(kind, row.ref, row.value);
    }
    return snapshot;
  }

  /** 待补发覆盖云端旧值（契约 §5 需求 16：刚点的状态不被回滚）。 */
  applyPending(rows: MarkRow[]): MarksSnapshot {
    let snapshot: MarksSnapshot = this;
    for (let i = 0; i < rows.length; i++) {
      const row: MarkRow = rows[i];
      const kind: MarkKind | undefined = markKindFromWire(row.kind);
      if (kind === undefined) {
        continue;
      }
      snapshot = snapshot.with(kind, row.ref, row.value);
    }
    return snapshot;
  }

  counts(): number {
    return this.hwDone.size + this.ntPin.size + this.ntDone.size;
  }
}

export function copySet(source: Set<string>): Set<string> {
  const out: Set<string> = new Set<string>();
  source.forEach((value: string) => {
    out.add(value);
  });
  return out;
}
