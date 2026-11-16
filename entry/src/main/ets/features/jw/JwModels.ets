/** 教务系统官方入口（与网页 `TOOLS.jw.url` 一致）。 */
export const JW_URL: string = 'http://210.34.74.77/sso.jsp';

/** 教务速览卡片（网页/小程序口径：教务为链接型工具，卡内不抓取成绩）。 */
export class JwCardDef {
  id: string = '';
  name: string = '';
  hint: string = '';

  constructor(id: string, name: string, hint: string) {
    this.id = id;
    this.name = name;
    this.hint = hint;
  }
}

export class JwEntries {
  static readonly CARDS: JwCardDef[] = [
    new JwCardDef('grades', '成绩', '在教务系统「成绩查询」查看'),
    new JwCardDef('exams', '考试', '在教务系统「考试安排」查看'),
    new JwCardDef('enroll', '选课', '在教务系统「选课」查看轮次'),
    new JwCardDef('notices', '公告', '在教务系统「通知公告」查看')
  ];

  static url(): string {
    return JW_URL;
  }

  static cardNames(): string[] {
    const out: string[] = [];
    for (let i = 0; i < JwEntries.CARDS.length; i++) {
      out.push(JwEntries.CARDS[i].name);
    }
    return out;
  }
}

/** 教务页文案（纯函数，可单测）。 */
export class JwLogic {
  /** 周次文案：`第 13 周` / `学期未开始` / `—`。 */
  static weekText(week: number | undefined, hasData: boolean): string {
    if (week !== undefined && week > 0) {
      return '第 ' + week + ' 周';
    }
    return hasData ? '学期未开始' : '—';
  }

  /** 下一节课文案：`周一 11-23 08:10 思想道德与法治`。 */
  static nextText(dayText: string, dateText: string, startText: string, name: string): string {
    if (name.length === 0) {
      return '暂无后续课程';
    }
    const parts: string[] = [];
    if (dayText.length > 0) {
      parts.push(dayText);
    }
    if (dateText.length > 0) {
      parts.push(dateText);
    }
    if (startText.length > 0) {
      parts.push(startText);
    }
    parts.push(name);
    return parts.join(' ');
  }

  /** 今日课程汇总：`3 节 · 下一节 14:30 英语1`。 */
  static todayText(count: number, nextStart: string, nextName: string): string {
    if (count <= 0) {
      return '今天没有课';
    }
    if (nextName.length === 0) {
      return count + ' 节 · 今日已结束';
    }
    return count + ' 节 · 下一节 ' + nextStart + ' ' + nextName;
  }

  /** 入口说明（避免误导：不做账号密码登录）。 */
  static loginHint(): string {
    return '首次登录请在浏览器勾选「保存密码」，之后打开即自动填充';
  }
}
