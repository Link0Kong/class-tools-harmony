/** 演示上传的分片/ID 规则（纯函数，便于单测）。 */
export class PptUploadPlanner {
  static readonly CHUNK_SIZE: number = 512 * 1024;
  static readonly MAX_SIZE: number = 200 * 1024 * 1024;
  static readonly SUFFIXES: string[] = ['.ppt', '.pptx'];

  static isSupported(name: string): boolean {
    const lower: string = name.toLowerCase();
    for (let i = 0; i < PptUploadPlanner.SUFFIXES.length; i++) {
      if (lower.endsWith(PptUploadPlanner.SUFFIXES[i])) {
        return true;
      }
    }
    return false;
  }

  static chunkCount(size: number): number {
    if (size <= 0) {
      return 0;
    }
    return Math.ceil(size / PptUploadPlanner.CHUNK_SIZE);
  }

  /** 第 index 片的 [offset, length]（最后一片可小）。 */
  static chunkRange(index: number, size: number): number[] {
    const offset: number = index * PptUploadPlanner.CHUNK_SIZE;
    const length: number = Math.max(0, Math.min(PptUploadPlanner.CHUNK_SIZE, size - offset));
    return [offset, length];
  }

  /** deck id：`d` + base36(ms) + 6 位小写字母数字（≤13 字符）。 */
  static deckId(nowMillis: number, seed: number): string {
    const alphabet: string = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let value: number = Math.abs(Math.floor(seed));
    let tail: string = '';
    for (let i = 0; i < 6; i++) {
      tail += alphabet.charAt(value % alphabet.length);
      value = Math.floor(value / alphabet.length) + 7;
    }
    const ts: string = nowMillis.toString(36);
    const shortTs: string = ts.length > 6 ? ts.substring(ts.length - 6) : ts;
    return 'd' + shortTs + tail;
  }

  static titleOf(name: string, max: number = 80): string {
    const dot: number = name.lastIndexOf('.');
    const base: string = dot > 0 ? name.substring(0, dot) : name;
    return base.length > max ? base.substring(0, max) : base;
  }

  static extOf(name: string): string {
    const dot: number = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  static validate(name: string, size: number): string {
    if (!PptUploadPlanner.isSupported(name)) {
      return '只支持 .ppt / .pptx';
    }
    if (size <= 0) {
      return '文件为空或无法读取';
    }
    if (size > PptUploadPlanner.MAX_SIZE) {
      return '文件超过 200 MB';
    }
    return '';
  }
}
