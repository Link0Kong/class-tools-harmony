import { ExportCardSpec, ExportNaming, ExportParam } from '../export/ExportCard';
import { NoticeCard } from '../notices/NoticeCards';
import { HomeworkDueCalculator, HomeworkItem } from '../../data/homework/HomeworkModels';
import { PollDetail, PollOption, visibilityLabel } from '../../data/vote/VoteModels';
import { PptDeck, formatBytes, pptStatusLabel } from '../../data/ppt/PptModels';
import {
  DiagAnalysis,
  DiagCheck,
  DiagSummary,
  ServiceHealthRow,
  diagStatusLabel
} from '../../data/diag/DiagModels';
import { WaterMonthStats } from '../water/WaterModels';

/**
 * 统一分享卡数据工厂：所有业务内容都转成 ExportCardSpec，
 * 再由 ExportCardView 离屏渲染成 PNG 后交给系统分享面板。
 */
export class ShareSpecs {
  private static base(prefix: string, title: string, subtitle: string, fileNameHint: string,
    now: number): ExportCardSpec {
    const spec: ExportCardSpec = new ExportCardSpec();
    spec.title = title;
    spec.subtitle = subtitle;
    spec.recordId = ExportNaming.recordId(prefix, now, ExportNaming.randomSuffix());
    spec.fileName = ExportNaming.safeName(fileNameHint + '_' + ExportNaming.stamp(now) + '.png');
    spec.footer = '生成时间 ' + ExportNaming.timeText(now) + ' · 班级工具';
    spec.generatedAt = now;
    return spec;
  }

  private static shortTitle(title: string, fallback: string): string {
    const text: string = title.trim().length > 0 ? title.trim() : fallback;
    return text.length > 24 ? text.substring(0, 24) : text;
  }

  /** 分享卡高度受系统截图纹理限制，超长内容截断，避免生成失败。 */
  private static clamp(lines: string[], max: number): string[] {
    if (lines.length <= max) {
      return lines;
    }
    const out: string[] = lines.slice(0, max);
    out.push('… 内容较长，已截断');
    return out;
  }

  static notice(card: NoticeCard, now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base('NOTICE', card.title,
      card.cat + (card.timeText.length > 0 ? ' · ' + card.timeText : ''),
      '通知_' + ShareSpecs.shortTitle(card.title, '未命名'), now);
    spec.params = [
      new ExportParam('分类', card.cat.length > 0 ? card.cat : '通知'),
      new ExportParam('状态', card.statusLabel.length > 0 ? card.statusLabel : '—'),
      new ExportParam('发布', card.senderName.length > 0 ? card.senderName : '—'),
      new ExportParam('时间', card.timeText.length > 0 ? card.timeText : '—'),
      new ExportParam('截止', card.dueText.length > 0 ? card.dueText : '—')
    ];
    const lines: string[] = [];
    const body: string = card.summary.length > 0 ? card.summary
      : (card.entry !== undefined ? card.entry.summary() : '');
    if (body.length > 0) {
      lines.push(body);
    }
    for (let i = 0; i < card.points.length; i++) {
      lines.push('· ' + card.points[i]);
    }
    for (let i = 0; i < card.segments.length; i++) {
      const text: string = card.segments[i].text.trim();
      if (text.length > 0) {
        lines.push(text);
      }
    }
    for (let i = 0; i < card.items.length; i++) {
      const label: string = card.items[i].label.trim();
      const text: string = card.items[i].text.trim();
      if (label.length > 0 || text.length > 0) {
        lines.push(label.length > 0 ? label + '：' + text : text);
      }
    }
    spec.linesLabel = '通知内容';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static homework(item: HomeworkItem, now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base('HOMEWORK', item.title(),
      item.due !== undefined ? '截止 ' + HomeworkDueCalculator.dueText(item.due.atMillis) : '作业',
      '作业_' + ShareSpecs.shortTitle(item.title(), '未命名'), now);
    spec.params = [
      new ExportParam('截止', item.due !== undefined ? HomeworkDueCalculator.dueText(item.due.atMillis) : '—'),
      new ExportParam('状态', item.due !== undefined ? item.due.label : '—'),
      new ExportParam('发布', item.row.author.length > 0 ? item.row.author : '—'),
      new ExportParam('附件', item.attachments.length > 0 ? item.attachments.length + ' 个' : '无')
    ];
    const lines: string[] = [];
    const content: string = item.row.content.trim();
    if (content.length > 0) {
      lines.push(content);
    }
    if (item.attachments.length > 0) {
      lines.push('');
      lines.push('附件');
      for (let i = 0; i < item.attachments.length; i++) {
        lines.push('· ' + item.attachments[i].name);
      }
    }
    spec.linesLabel = '作业内容';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static vote(detail: PollDetail, showCounts: boolean, now: number): ExportCardSpec {
    const poll = detail.poll;
    const rule: string = (poll.settings.multi ? '多选 · 最多 ' + poll.settings.maxChoices + ' 项' : '单选')
      + ' · ' + (poll.settings.anonymous ? '匿名' : '实名')
      + ' · ' + visibilityLabel(poll.settings.resultVisibility);
    const spec: ExportCardSpec = ShareSpecs.base('VOTE', poll.title, poll.ownerName + ' · ' + rule,
      '投票_' + ShareSpecs.shortTitle(poll.title, '未命名'), now);
    spec.params = [
      new ExportParam('发起', poll.ownerName.length > 0 ? poll.ownerName : '—'),
      new ExportParam('规则', rule),
      new ExportParam('截止', poll.deadline > 0 ? new Date(poll.deadline).toLocaleString() : '不限'),
      new ExportParam('已投', showCounts ? detail.total + ' 人' : '结果暂不可见')
    ];
    const lines: string[] = [];
    if (poll.description.trim().length > 0) {
      lines.push(poll.description.trim());
      lines.push('');
    }
    for (let i = 0; i < poll.options.length; i++) {
      const option: PollOption = poll.options[i];
      const count: number = detail.counts.get(option.id) !== undefined
        ? detail.counts.get(option.id) as number : 0;
      lines.push((i + 1) + '. ' + option.text + (showCounts ? '（' + count + ' 票）' : ''));
      if (option.desc.trim().length > 0) {
        lines.push('   ' + option.desc.trim());
      }
    }
    spec.linesLabel = '投票选项';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static textCard(prefix: string, title: string, subtitle: string, fileNameHint: string,
    params: ExportParam[], lines: string[], linesLabel: string, now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base(prefix, title, subtitle, fileNameHint, now);
    spec.params = params;
    spec.linesLabel = linesLabel;
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static diag(summary: DiagSummary, health: ServiceHealthRow[], analyses: DiagAnalysis[],
    now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base('DIAG', '设备诊断报告',
      '通过 ' + summary.passCount() + ' · 注意 ' + summary.warnCount() + ' · 异常 ' + summary.failCount(),
      '设备诊断_' + ExportNaming.stamp(now), now);
    spec.params = [
      new ExportParam('通过', '' + summary.passCount()),
      new ExportParam('注意', '' + summary.warnCount()),
      new ExportParam('异常', '' + summary.failCount())
    ];
    const lines: string[] = [];
    lines.push('本机检查');
    for (let i = 0; i < summary.checks.length; i++) {
      const check: DiagCheck = summary.checks[i];
      lines.push('· ' + check.label + '：' + check.value + '（' + diagStatusLabel(check.status) + '）');
    }
    if (health.length > 0) {
      lines.push('');
      lines.push('服务健康');
      for (let i = 0; i < health.length; i++) {
        lines.push('· ' + health[i].name + '：' + (health[i].status.length > 0 ? health[i].status : '—'));
      }
    }
    if (analyses.length > 0) {
      lines.push('');
      lines.push('最近分析');
      for (let i = 0; i < analyses.length && i < 5; i++) {
        lines.push('· ' + (analyses[i].title.length > 0 ? analyses[i].title : analyses[i].id)
          + (analyses[i].cause.length > 0 ? '：' + analyses[i].cause : ''));
      }
    }
    spec.linesLabel = '检查明细';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static water(stats: WaterMonthStats, room: string, now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base('WATER', room.length > 0 ? room + ' 用水' : '宿舍用水',
      stats.month + ' · ' + stats.persons + ' 人间', '水量_' + stats.month, now);
    spec.params = [
      new ExportParam('月份', stats.month),
      new ExportParam('人数', stats.persons + ' 人'),
      new ExportParam('读数', stats.record !== undefined ? stats.record.reading.toFixed(2) + ' 吨' : '—'),
      new ExportParam('用量', stats.charge.hasUsage ? stats.charge.usage.toFixed(2) + ' 吨' : '待计算'),
      new ExportParam('水费', stats.charge.hasUsage ? stats.charge.fee.toFixed(2) + ' 元' : '—'),
      new ExportParam('折合扣电', stats.charge.hasUsage ? stats.charge.degree.toFixed(2) + ' 度' : '—'),
      new ExportParam('免费额度', stats.charge.free.toFixed(1) + ' 吨'),
      new ExportParam('日均', stats.hasDailyAverage ? stats.dailyAverage.toFixed(2) + ' 吨' : '—')
    ];
    const lines: string[] = [];
    if (stats.charge.hasUsage) {
      lines.push(stats.charge.within ? '本月用水在免费定额内'
        : '本月超出免费定额 ' + stats.charge.excess.toFixed(2) + ' 吨');
    } else {
      lines.push('录入下一条读数后自动计算用量、水费与折合扣电');
    }
    spec.linesLabel = '用水说明';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static power(label: string, quantityText: string, unit: string, updated: string,
    rangeTitle: string, drop: number, perDay: number, valid: boolean, estimateDays: number,
    low: number, isLow: boolean, now: number): ExportCardSpec {
    const spec: ExportCardSpec = ShareSpecs.base('POWER', label.length > 0 ? label + ' 电费' : '宿舍电费',
      '剩余 ' + quantityText + ' ' + unit, '电费_' + ExportNaming.stamp(now), now);
    spec.params = [
      new ExportParam('宿舍', label.length > 0 ? label : '—'),
      new ExportParam('剩余电量', quantityText + ' ' + unit),
      new ExportParam('状态', isLow ? '低电' : '正常'),
      new ExportParam('更新时间', updated.length > 0 ? updated : '—'),
      new ExportParam('报警阈值', low + ' ' + unit)
    ];
    const lines: string[] = [];
    if (valid) {
      lines.push(rangeTitle + '：下降 ' + drop.toFixed(2) + ' ' + unit
        + ' · 日均 ' + perDay.toFixed(2) + ' ' + unit);
    } else {
      lines.push('暂无足够趋势数据');
    }
    if (estimateDays > 0) {
      lines.push('按近 7 天速度，预计可用约 ' + estimateDays + ' 天');
    }
    spec.linesLabel = '趋势与预估';
    spec.lines = ShareSpecs.clamp(lines, 80);
    return spec;
  }

  static ppt(deck: PptDeck, now: number): ExportCardSpec {
    const formats: string[] = [];
    if (deck.hasCompat) {
      formats.push('兼容版 PPTX');
    }
    if (deck.hasPdf) {
      formats.push('PDF');
    }
    const spec: ExportCardSpec = ShareSpecs.base('PPT', deck.title.length > 0 ? deck.title : '演示文件',
      (deck.ownerName.length > 0 ? deck.ownerName + ' · ' : '') + pptStatusLabel(deck.status),
      '演示_' + ShareSpecs.shortTitle(deck.title, '未命名'), now);
    spec.params = [
      new ExportParam('状态', pptStatusLabel(deck.status)),
      new ExportParam('上传', deck.ownerName.length > 0 ? deck.ownerName : '—'),
      new ExportParam('页数', deck.slideCount > 0 ? deck.slideCount + ' 页' : '—'),
      new ExportParam('原文件', deck.sourceName.length > 0
        ? deck.sourceName + '（' + formatBytes(deck.sourceSize) + '）' : '—'),
      new ExportParam('可下载', formats.length > 0 ? formats.join(' / ') : '—')
    ];
    spec.linesLabel = '演示说明';
    spec.lines = ['在「班级工具 → 演示」中可下载兼容版 PPTX、PDF 或原始文件。'];
    return spec;
  }
}
