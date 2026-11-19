import { FitFields, FitInput, FitRecord, FitRow } from '../fit/FitModels';
import { FitScoring } from '../fit/FitScoring';
import { WaterCharge, WaterMonthStats, WaterRoomState, WaterState } from '../water/WaterModels';
import { WaterCalculator } from '../water/WaterCalculator';
import { WaterMonth } from '../water/WaterMonth';
import { CloudSpaceFile, CloudSpaceSnapshot } from '../../data/cloudspace/CloudSpaceModels';
import { PowerRooms } from '../../data/power/PowerModels';
import { ToolCatalog, ToolDef } from '../../data/tool/ToolCatalog';

/** 入口卡片的一行补充信息（整行宽度时展示）。 */
export class ToolDigestLine {
  text: string = '';
  sub: string = '';

  constructor(text: string = '', sub: string = '') {
    this.text = text;
    this.sub = sub;
  }
}

/**
 * 工具入口卡片摘要：
 * - primary：半宽时展示的一行关键信息；
 * - lines：整行时额外展示的明细（最多 2 行）。
 */
export class ToolCardDigest {
  primary: string = '';
  lines: ToolDigestLine[] = [];

  constructor(primary: string = '', lines: ToolDigestLine[] = []) {
    this.primary = primary;
    this.lines = lines;
  }
}

/** 工作台工具卡片摘要（只读本机已加载数据，不额外发请求）。 */
export class HomeToolDigest {
  static fit(records: FitRecord[]): ToolCardDigest {
    if (records.length === 0) {
      return new ToolCardDigest('未录入体测', [
        new ToolDigestLine('录入一次即可生成总分与等级'),
        new ToolDigestLine('支持历史对比与导出')
      ]);
    }
    let latest: FitRecord = records[0];
    for (let i = 1; i < records.length; i++) {
      if (records[i].ts > latest.ts) {
        latest = records[i];
      }
    }
    const gradeText: string = latest.grade.trim();
    const primary: string = latest.totalText() + ' 分' + (gradeText.length > 0 ? ' · ' + gradeText : '');
    const lines: ToolDigestLine[] = [];
    lines.push(new ToolDigestLine(HomeToolDigest.filledText(latest.fields), latest.timeText() + ' 录入'));
    const weak: string = HomeToolDigest.weakText(latest);
    if (weak.length > 0) {
      lines.push(new ToolDigestLine('待提升', weak));
    }
    return new ToolCardDigest(primary, lines);
  }

  static water(state: WaterState, nowMillis: number): ToolCardDigest {
    let roomKey: string = '';
    state.rooms.forEach((room: WaterRoomState, key: string) => {
      if (roomKey.length === 0) {
        roomKey = key;
      }
    });
    if (roomKey.length === 0) {
      return new ToolCardDigest('未录入抄表', [
        new ToolDigestLine('按月份记录用水与水费'),
        new ToolDigestLine('与电费同一入口同步')
      ]);
    }
    const room: WaterRoomState = state.roomOrDefault(roomKey);
    const month: string = WaterMonth.current(nowMillis);
    const stats: WaterMonthStats = WaterCalculator.stats(room, month, nowMillis);
    const charge: WaterCharge = stats.charge;
    const lines: ToolDigestLine[] = [];
    const label: string = PowerRooms.labelOf(roomKey);
    if (!charge.hasUsage) {
      return new ToolCardDigest(label + ' · 本月未抄表', [
        new ToolDigestLine(room.persons + ' 人间', '日均按已过天数折算'),
        new ToolDigestLine('录入本月读数即可计算水费')
      ]);
    }
    const primary: string = charge.usage.toFixed(2) + ' 吨';
    lines.push(new ToolDigestLine('水费 ' + charge.fee.toFixed(2) + ' 元',
      charge.within ? '未超免费' : '超 ' + charge.excess.toFixed(2) + ' 吨'));
    if (stats.hasDailyAverage) {
      lines.push(new ToolDigestLine('日均 ' + stats.dailyAverage.toFixed(2) + ' 吨', WaterMonth.label(month)));
    } else {
      lines.push(new ToolDigestLine('本月 ' + WaterMonth.label(month), ''));
    }
    return new ToolCardDigest(primary, lines);
  }

  static cloud(snapshot: CloudSpaceSnapshot): ToolCardDigest {
    if (!snapshot.connected()) {
      return new ToolCardDigest('未连接临时空间', [
        new ToolDigestLine('同账号设备免配对互传'),
        new ToolDigestLine('文件保留 72 小时')
      ]);
    }
    const count: number = snapshot.count();
    if (count === 0) {
      return new ToolCardDigest('空间为空', [
        new ToolDigestLine('上传后 72 小时内可下载'),
        new ToolDigestLine('单文件任意大小 · 分片续传')
      ]);
    }
    const latest: CloudSpaceFile = snapshot.files[count - 1];
    return new ToolCardDigest(count + ' 个文件', [
      new ToolDigestLine('共 ' + HomeToolDigest.sizeText(snapshot.totalBytes()), '最新上传'),
      new ToolDigestLine(latest.name.length > 0 ? latest.name : '临时文件', '保留 72 小时')
    ]);
  }

  /** 没有本机数据来源的工具：半宽显示副标题，整行补充功能点。 */
  static fallback(id: string, subtitle: string): ToolCardDigest {
    const def: ToolDef | undefined = ToolCatalog.byId(id);
    const lines: ToolDigestLine[] = [];
    if (def !== undefined) {
      for (let i = 0; i < def.features.length && i < 2; i++) {
        lines.push(new ToolDigestLine(def.features[i], ''));
      }
    }
    if (lines.length === 0) {
      lines.push(new ToolDigestLine(subtitle, ''));
    }
    return new ToolCardDigest(subtitle, lines);
  }

  private static filledText(fields: FitFields): string {
    let filled: number = 0;
    for (let i = 0; i < FitInput.KEYS.length; i++) {
      if (fields.valueOf(FitInput.KEYS[i]).trim().length > 0) {
        filled += 1;
      }
    }
    return '已填 ' + filled + '/' + FitInput.KEYS.length + ' 项';
  }

  /** 取分数最低的 2 个已填项，作为“需提升科目”。 */
  private static weakText(record: FitRecord): string {
    if (record.fields.isEmpty()) {
      return '';
    }
    const input: FitInput = FitInput.fromFields(record.sexEnum(), record.gradeEnum(), record.fields);
    const rows: FitRow[] = FitScoring.calc(input).rows;
    const weak: FitRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      const score: number | undefined = rows[i].score;
      if (score !== undefined && score < 80) {
        weak.push(rows[i]);
      }
    }
    if (weak.length === 0) {
      return '各项均衡，继续保持';
    }
    weak.sort((a: FitRow, b: FitRow) => (a.score ?? 0) - (b.score ?? 0));
    const parts: string[] = [];
    for (let i = 0; i < weak.length && i < 2; i++) {
      parts.push(weak[i].name + ' ' + (weak[i].score ?? 0) + ' 分');
    }
    return parts.join(' · ');
  }

  private static sizeText(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    }
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return Math.round(bytes / 1024) + ' KB';
    }
    return bytes + ' B';
  }
}
