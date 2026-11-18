/** 使用说明文案（与网页端 __UG_CARDS_V1__ 一致）。 */
export class UsageCategory {
  key: string = '';
  label: string = '';
  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

export class UsageCard {
  id: string = '';
  cat: string = '';
  title: string = '';
  sub: string = '';
  tone: string = '';
  steps: string[] = [];
  tip: string = '';
}

export class UsageData {
  static readonly CATEGORIES: UsageCategory[] = [
    new UsageCategory("start", "开始使用"),
    new UsageCategory("study", "学习工具"),
    new UsageCategory("life", "生活服务"),
    new UsageCategory("team", "班级协作"),
    new UsageCategory("more", "更多"),
  ];

  static readonly CARDS: UsageCard[] = [
    buildCard(
      "id", "start", "身份与同步", "学号 + 姓名进门，数据跟着账号走", "blue", [
        "首次打开先填学号和姓名",
        "通过班级名单校验后进入",
        "换设备重新验证即可同步",
      ], "名单与身份 token 只存本机，退出身份即清除"),
    buildCard(
      "nav", "start", "工具栏与全部", "常用工具放上面，全部页可拖动排序", "mint", [
        "顶部切换条放 3–4 个常用工具",
        "进「全部」把卡片拖到顶部栏",
        "全部页内拖动可调整本机顺序",
      ], "工具栏顺序随账号同步，全部页卡片顺序只存本机"),
    buildCard(
      "draw", "study", "抽签工作流", "抽签 → 分组 → 结果单，三步都能导出", "sand", [
        "设范围、个数，可选允许重复与排除序号",
        "结果可点单个剔除，勾选后自动补抽",
        "分组按组数或每组人数分配",
      ], "点「重置」清空本轮抽签与分组结果，参数和参与名单保留"),
    buildCard(
      "roster", "study", "参与名单", "从班级名单选人，只从名单里抽", "mint", [
        "点「选择名单」打开班级名单",
        "顶部全班 / 班委 / 团员可快捷套用",
        "逐个点选或全选后点「确定」",
      ], "名单不支持自定义输入，只来自班级名单"),
    buildCard(
      "tt", "study", "课表", "周 / 日视图，点课程看详情", "blue", [
        "左右箭头切换周次",
        "周 / 日视图一键切换",
        "点任意课程看教室、时间与周次",
      ], "课表来自教务同步，只读不能改；全部课程默认收起"),
    buildCard(
      "hw", "study", "作业", "发布即同步，勾完成，看截止", "sand", [
        "进班级后可发布作业与截止时间",
        "勾「完成」按账号同步",
        "附件图片会自动压缩",
      ], "删除后所有人都看不到，隐藏只影响自己的视图"),
    buildCard(
      "nt", "study", "通知", "通知、附件与提醒，一处看完", "rose", [
        "通知按时间排列，点开看全文",
        "附件图片与 QQ 压缩包可在页内看",
        "右下「提醒」可开桌面通知",
      ], "置顶与已处理按账号同步，重复通知会自动合并"),
    buildCard(
      "ft", "study", "体测", "七项实时算分，可存历史导出", "sand", [
        "选性别与年级，填一项就出单科分",
        "全部填完显示总分与等级",
        "可保存两条历史并回填查看",
      ], "长跑按「分 : 秒」填写，导出图自带参数与水印"),
    buildCard(
      "roll", "study", "点名", "叫到一个勾一个，到 / 假可撤销", "violet", [
        "选名单或沿用抽签名单",
        "点「到 / 假」记录",
        "已处理的会沉底，再点一次撤销",
      ], "名单与到 / 假记录按账号同步"),
    buildCard(
      "stats", "study", "统计", "按姓名看访问，仅管理员可见", "violet", [
        "管理员进「全部 → 统计」",
        "看每人访问次数与最近时间",
        "只显示姓名，不显示学号",
      ], "普通成员看不到本页，数据不做导出"),
    buildCard(
      "power", "life", "宿舍电费", "关注宿舍，看余额与用电趋势", "blue", [
        "点「关注宿舍」按楼栋选房间",
        "看剩余电量、估算可用与区间趋势",
        "点或按住趋势曲线看采样点",
      ], "13 / 16 号楼日更，不提供 24h，估算标「参考」"),
    buildCard(
      "water", "life", "水量", "每月抄表，自动算用量与水费", "blue", [
        "选月份填水表读数",
        "自动和上次对比算用量",
        "超出定额部分按 3.03 元 / 吨算",
      ], "水费从电费账户扣，会折算成扣减电量；同宿舍共用记录"),
    buildCard(
      "vote", "team", "投票", "限时快投或跨天投票，实时结果", "mint", [
        "选限时、指定截止或不限时",
        "标题与 2–20 个选项可加说明和配图",
        "单选 / 多选、匿名与可见范围",
      ], "一人一票按账号去重；发起人与管理员可提前结束或删除"),
    buildCard(
      "ppt", "team", "演示", "PPT 转兼容包与分步图，随处可放", "blue", [
        "上传 .ppt / .pptx 自动转换",
        "下载兼容版、PDF 或原始文件",
        "旧课件可在线预览或单下视频",
      ], "兼容包只做兼容处理，不改变 PPT 本身内容"),
    buildCard(
      "file", "team", "文件传输", "同账号设备互传，文件保留 3 天", "mint", [
        "打开本页即可看到同账号文件",
        "上传自动分片，可看进度、可取消",
        "下载走签名链接，可删除或清空",
      ], "单文件不限大小，文件自上传起保留 3 天"),
    buildCard(
      "diag", "more", "诊断", "服务状态、设备自检与 AI 修复建议", "mint", [
        "看依赖服务是否正常",
        "设备自检网络、时钟与存储",
        "异常项按 AI 建议处理",
      ], "全班成员都可查看，详情已脱敏"),
    buildCard(
      "fb", "more", "反馈建议", "问题和建议直接发给管理员", "sand", [
        "写下问题或建议并提交",
        "可留联系方式便于回复",
        "管理员会看到并标记已处理",
      ], "反馈不会公开你的学号"),
    buildCard(
      "jw", "study", "教务入口", "点卡片直接打开教务系统", "blue", [
        "点『教务』卡片直接打开教务系统",
        "首次登录时勾选浏览器『保存密码』",
        "之后打开即自动填充账号密码",
      ], "自动填充由浏览器完成；校外打不开时先连学校 VPN"),
    buildCard(
      "chsi", "study", "学信网入口", "学信档案、学历学位查询官方入口", "blue", [
        "工具栏或「全部」页打开学信网",
        "点工具卡在新窗口打开官方页面",
        "学信档案/照片校对需先登录学信网账号",
      ], "本站不保存学信网账号；查询与报告以官方页面为准"),
  ];

  static ofCategory(key: string): UsageCard[] {
    const out: UsageCard[] = [];
    for (let i = 0; i < UsageData.CARDS.length; i++) {
      if (UsageData.CARDS[i].cat === key) {
        out.push(UsageData.CARDS[i]);
      }
    }
    return out;
  }

  static labelOf(key: string): string {
    for (let i = 0; i < UsageData.CATEGORIES.length; i++) {
      if (UsageData.CATEGORIES[i].key === key) {
        return UsageData.CATEGORIES[i].label;
      }
    }
    return '';
  }
}

function buildCard(id: string, cat: string, title: string, sub: string, tone: string,
  steps: string[], tip: string): UsageCard {
  const card: UsageCard = new UsageCard();
  card.id = id;
  card.cat = cat;
  card.title = title;
  card.sub = sub;
  card.tone = tone;
  card.steps = steps;
  card.tip = tip;
  return card;
}
