import { HomeworkDueCalculator, HomeworkRow } from '../../data/homework/HomeworkModels';
import { NoticeCard } from '../notices/NoticeCards';
import { NoticeSection } from '../notices/NoticeRecurrence';
import { PowerStats } from '../../data/power/PowerModels';

/** 工作台卡片里的一条轮换项（作业 / 通知）。 */
export class HomeCardItem {
  title: string = '';
  sub: string = '';
}

/** 工作台数据整理（与小程序 pages/index 同口径的纯函数）。 */
export class HomeDigest {
  static hello(hour: number): string {
    if (hour < 6) {
      return '夜深了';
    }
    if (hour < 11) {
      return '早上好';
    }
    if (hour < 14) {
      return '中午好';
    }
    if (hour < 18) {
      return '下午好';
    }
    return '晚上好';
  }

  static pad2(value: number): string {
    return value < 10 ? '0' + value : '' + value;
  }

  static dateText(now: Date): string {
    return now.getFullYear() + '-' + HomeDigest.pad2(now.getMonth() + 1) + '-' + HomeDigest.pad2(now.getDate());
  }

  static weekText(week: number | undefined): string {
    return week !== undefined && week > 0 ? '第 ' + week + ' 周' : '';
  }

  /** 待交作业：未完成、未隐藏（本端无 hide 数据）、截止升序（无截止排最后）。 */
  static hwOpen(rows: HomeworkRow[], isDone: (id: string) => boolean,
    isHidden: (id: string) => boolean = (id: string) => false): HomeworkRow[] {
    const out: HomeworkRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      if (!isDone(rows[i].id) && !isHidden(rows[i].id)) {
        out.push(rows[i]);
      }
    }
    out.sort((a: HomeworkRow, b: HomeworkRow) => {
      const x: number | undefined = HomeworkDueCalculator.parseDue(a.date, a.time);
      const y: number | undefined = HomeworkDueCalculator.parseDue(b.date, b.time);
      if (x === undefined && y === undefined) {
        return 0;
      }
      if (x === undefined) {
        return 1;
      }
      if (y === undefined) {
        return -1;
      }
      return x - y;
    });
    return out;
  }

  /** 作业轮换项（≤5 条，标题截断 18 字，副标题为截止信息）。 */
  static hwItems(rows: HomeworkRow[], max: number = 5): HomeCardItem[] {
    const out: HomeCardItem[] = [];
    for (let i = 0; i < rows.length && i < max; i++) {
      const row: HomeworkRow = rows[i];
      const item: HomeCardItem = new HomeCardItem();
      item.title = HomeDigest.shortTitle(row.subject.length > 0 ? row.subject : row.content);
      const due: number | undefined = HomeworkDueCalculator.parseDue(row.date, row.time);
      item.sub = due !== undefined ? '截止 ' + HomeworkDueCalculator.dueText(due) : '';
      out.push(item);
    }
    return out;
  }

  static shortTitle(text: string, max: number = 18): string {
    const trimmed: string = text.trim();
    if (trimmed.length <= max) {
      return trimmed;
    }
    return trimmed.substring(0, max) + '…';
  }

  /** 待处理通知卡（未处理、非定义卡），按 sortAt 排序。 */
  static ntOpen(cards: NoticeCard[], isDone: (key: string) => boolean): NoticeCard[] {
    const out: NoticeCard[] = [];
    for (let i = 0; i < cards.length; i++) {
      const card: NoticeCard = cards[i];
      if (card.definition || card.section === NoticeSection.MATERIAL || card.section === NoticeSection.EXPIRED) {
        continue;
      }
      if (isDone(card.key)) {
        continue;
      }
      out.push(card);
    }
    out.sort((a: NoticeCard, b: NoticeCard) => a.sortAt - b.sortAt);
    return out;
  }

  static ntPending(cards: NoticeCard[], isDone: (key: string) => boolean): number {
    return HomeDigest.ntOpen(cards, isDone).length;
  }

  static ntItems(cards: NoticeCard[], isDone: (key: string) => boolean, max: number = 5): HomeCardItem[] {
    const open: NoticeCard[] = HomeDigest.ntOpen(cards, isDone);
    const out: HomeCardItem[] = [];
    for (let i = 0; i < open.length && i < max; i++) {
      const card: NoticeCard = open[i];
      const item: HomeCardItem = new HomeCardItem();
      item.title = HomeDigest.shortTitle(card.title.length > 0 ? card.title : '班级通知');
      item.sub = card.occurrence ? card.label : (card.dueText.length > 0 ? card.dueText : card.timeText);
      out.push(item);
    }
    return out;
  }

  /** 电费状态：q < low 低电；low ≤ q < 2*low 偏低；其余充足；无数据 idle。 */
  static powerState(q: number, hasValue: boolean, low: number): string {
    if (!hasValue) {
      return 'idle';
    }
    const threshold: number = low > 0 ? low : 30;
    if (q < threshold) {
      return 'low';
    }
    if (q < threshold * 2) {
      return 'warn';
    }
    return 'ok';
  }

  static powerStateText(state: string): string {
    if (state === 'low') {
      return '低电';
    }
    if (state === 'warn') {
      return '偏低';
    }
    if (state === 'ok') {
      return '充足';
    }
    return '未选择';
  }

  static powerQText(q: number, hasValue: boolean): string {
    return PowerStats.fmtMain(q, hasValue);
  }

  /** 更新时间显示：`MM-dd HH:mm`；无值返回空串。 */
  static updText(updatedAt: string): string {
    if (updatedAt.length === 0) {
      return '';
    }
    const parsed: number = Date.parse(updatedAt);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return '';
    }
    const d: Date = new Date(parsed);
    return HomeDigest.pad2(d.getMonth() + 1) + '-' + HomeDigest.pad2(d.getDate())
      + ' ' + HomeDigest.pad2(d.getHours()) + ':' + HomeDigest.pad2(d.getMinutes());
  }

  static rotate(count: number, index: number): number {
    if (count <= 0) {
      return 0;
    }
    return (index + 1) % count;
  }
}
