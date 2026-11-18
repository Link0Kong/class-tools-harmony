import { AppSymbols } from '../../ui/theme/AppSymbols';

/** 工具分类（首页分组与「全部工具」排序）。 */
export enum ToolCategory {
  STUDY = '学习',
  CLASS = '班级事务',
  SYSTEM = '系统'
}

/** 一个工具的入口定义。`id` 与 userdata.homeTools 契约中的 id 一致。 */
export class ToolDef {
  id: string = '';
  name: string = '';
  /** HarmonyOS Symbol 图标资源（sys.symbol.*）。 */
  symbol: Resource = AppSymbols.INFO;
  subtitle: string = '';
  accent: string = '';
  category: ToolCategory = ToolCategory.CLASS;
  features: string[] = [];

  constructor(id: string, name: string, symbol: Resource, subtitle: string, accent: string,
    category: ToolCategory, features: string[]) {
    this.id = id;
    this.name = name;
    this.symbol = symbol;
    this.subtitle = subtitle;
    this.accent = accent;
    this.category = category;
    this.features = features;
  }
}

/**
 * 工具目录（与安卓 `ToolCatalog.kt`、网页 TOOLS、小程序 tools.js 对齐）。
 *
 * M0：目录 + 占位页；M1 起逐个替换为原生实现。
 */
export class ToolCatalog {
  static readonly TEAL: string = '#4E9082';
  static readonly BLUE: string = '#6E8CA8';
  static readonly SAND: string = '#B98F63';
  static readonly LEAF: string = '#5F8F5B';
  static readonly PLUM: string = '#8A6A92';
  static readonly CLAY: string = '#B06A55';
  static readonly AMBER: string = '#C29A3B';
  static readonly SKY: string = '#4A88A8';

  static readonly ALL: ToolDef[] = [
    new ToolDef('draw', '抽签', AppSymbols.DRAW, '公平随机 · 可导出', ToolCatalog.TEAL, ToolCategory.STUDY,
      ['STEP 1 配置范围与人数', 'STEP 2 预览名单', 'STEP 3 结果与导出卡片', '排除号 / 不重复 / 分组抽签']),
    new ToolDef('group', '分组', AppSymbols.GROUP, '随机分组 · 两列组卡', ToolCatalog.BLUE, ToolCategory.CLASS,
      ['按人数或组数分组', '名单选择与去重', '导出分组卡片']),
    new ToolDef('fit', '体测', AppSymbols.FIT, '录入 · 评分 · 历史', ToolCatalog.LEAF, ToolCategory.CLASS,
      ['项目成绩录入', '按性别/年级评分', '历史趋势与导出']),
    new ToolDef('hw', '作业', AppSymbols.HOMEWORK, '截止提醒 · 完成状态', ToolCatalog.SAND, ToolCategory.STUDY,
      ['作业列表与截止倒计时', '完成勾选（云端 marks 同步）', '本地截止提醒通知']),
    new ToolDef('nt', '通知', AppSymbols.NOTICE, '班委通知 · 附件', ToolCatalog.CLAY, ToolCategory.STUDY,
      ['通知列表与已处理标记', '置顶与筛选', '附件/图片查看']),
    new ToolDef('vote', '投票', AppSymbols.VOTE, '限时/长时 · 实时结果', ToolCatalog.PLUM, ToolCategory.CLASS,
      ['限时/截止/不限时', '单选/多选/匿名/可见范围', '实时结果与管理']),
    new ToolDef('tt', '课表', AppSymbols.TIMETABLE, '周/日视图 · 下一节', ToolCatalog.BLUE, ToolCategory.STUDY,
      ['周视图 / 日视图', '上一周 / 下一周', '今日课程与下一节课提醒']),
    new ToolDef('power', '电费', AppSymbols.POWER, '剩余电量 · 趋势', ToolCatalog.AMBER, ToolCategory.CLASS,
      ['关注宿舍剩余电量', '24h / 7d / 30d 趋势（点击查看采样点）', '低电量提醒']),
    new ToolDef('ppt', '演示', AppSymbols.PPT, 'PPT 自动转换 · 分步播放', ToolCatalog.BLUE, ToolCategory.CLASS,
      ['上传 .ppt/.pptx 自动转换（分步图片 + 视频）', '沉浸式全屏播放', '下载兼容版 / PDF / 视频']),
    new ToolDef('water', '水量', AppSymbols.WATER, '4/6 人间 · 月份记录', ToolCatalog.SKY, ToolCategory.CLASS,
      ['按月份查看抄表', '本机录入与云端同步', '月份选择器']),
    new ToolDef('roster', '名单', AppSymbols.ROSTER, '班委 · 团员 · 全班', ToolCatalog.PLUM, ToolCategory.CLASS,
      ['班级名单与座位号', '班委/团员/全班三类人群', '名单不导出、不外发']),
    new ToolDef('roll', '点名', AppSymbols.ROLL, '到 · 假 · 一键点名', ToolCatalog.CLAY, ToolCategory.CLASS,
      ['点名名单与到/假', '沿用抽签名单', '已处理沉底 / 重置本轮']),
    new ToolDef('diag', '诊断', AppSymbols.DIAG, '服务健康 · 设备 · AI 修复', ToolCatalog.TEAL, ToolCategory.SYSTEM,
      ['服务健康分组（脱敏展示）', '设备诊断（本机检查 + 重新检测）', 'AI 分析原因/建议与修复流程时间线']),
    new ToolDef('jw', '教务', AppSymbols.JW, '卡片速览 · 自动登录', ToolCatalog.BLUE, ToolCategory.STUDY,
      ['成绩 · 考试 · 选课 · 公告速览', '官方工具入口', '数据只在本机内存展示']),
    new ToolDef('map', '地图', AppSymbols.MAP, '2.5D · 楼层 · 道路导航', ToolCatalog.TEAL, ToolCategory.STUDY,
      ['校园 2.5D 地图与楼栋楼层', '按道路步行导航', '顶栏返回 / 刷新 / 浏览器降级']),
    new ToolDef('file', '文件传输', AppSymbols.FILE, '临时云空间 · 保留 3 天', ToolCatalog.TEAL, ToolCategory.CLASS,
      ['同账号跨设备临时空间（无需配对）', '任意大小 · 8 MiB 分片上传', '文件上传完成起保留 72 小时'])
  ];

  /** 默认「常用工具」：与网页首页前 4 个默认工具对齐（M1 起从 userdata.homeTools 读取）。 */
  static readonly DEFAULT_QUICK_IDS: string[] = ['draw', 'group', 'fit', 'hw'];

  static byId(id: string): ToolDef | undefined {
    for (let i = 0; i < ToolCatalog.ALL.length; i++) {
      if (ToolCatalog.ALL[i].id === id) {
        return ToolCatalog.ALL[i];
      }
    }
    return undefined;
  }

  static quickTools(): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < ToolCatalog.DEFAULT_QUICK_IDS.length; i++) {
      const t: ToolDef | undefined = ToolCatalog.byId(ToolCatalog.DEFAULT_QUICK_IDS[i]);
      if (t !== undefined && !ToolCatalog.isHidden(t.id)) {
        out.push(t);
      }
    }
    return out;
  }

  /** 仅出现在「我的」里的工具（不在首页/全部中展示）。 */
  static readonly HIDDEN_IDS: string[] = ['diag'];

  static isHidden(id: string): boolean {
    return ToolCatalog.HIDDEN_IDS.indexOf(id) >= 0;
  }

  /** 首页 / 全部可展示的工具。 */
  static visibleTools(): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < ToolCatalog.ALL.length; i++) {
      if (!ToolCatalog.isHidden(ToolCatalog.ALL[i].id)) {
        out.push(ToolCatalog.ALL[i]);
      }
    }
    return out;
  }

  static byCategory(category: ToolCategory): ToolDef[] {
    const out: ToolDef[] = [];
    for (let i = 0; i < ToolCatalog.ALL.length; i++) {
      if (ToolCatalog.ALL[i].category === category && !ToolCatalog.isHidden(ToolCatalog.ALL[i].id)) {
        out.push(ToolCatalog.ALL[i]);
      }
    }
    return out;
  }
}
