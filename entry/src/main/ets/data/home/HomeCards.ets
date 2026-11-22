import { preferences } from '@kit.ArkData';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';
import { AppSymbols } from '../../ui/theme/AppSymbols';

const TAG: string = 'HomeCards';
const STORE: string = 'class_tools_home_cards';

/** 卡片数据来源：真实数据 / 工具入口 / 本机非学校卡片。 */
export enum HomeCardKind {
  DATA = 'data',
  ENTRY = 'entry',
  LOCAL = 'local'
}

/** 一张可配置卡片的静态定义。 */
export class HomeCardDef {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  symbol: Resource = AppSymbols.INFO;
  accent: string = '';
  kind: HomeCardKind = HomeCardKind.ENTRY;
  /** 关联的工具 id（'' = 非工具卡片）。 */
  toolId: string = '';

  constructor(id: string, title: string, subtitle: string, symbol: Resource, accent: string,
    kind: HomeCardKind, toolId: string) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.symbol = symbol;
    this.accent = accent;
    this.kind = kind;
    this.toolId = toolId;
  }
}

/** 一张已放置到工作台的卡片（顺序即渲染顺序，span 1 = 半宽，2 = 整行）。 */
export class HomeCardConfig {
  id: string = '';
  span: number = 2;

  constructor(id: string, span: number) {
    this.id = id;
    this.span = span;
  }
}

/** 持久化结构（只存 id + 宽度，容错脏数据）。 */
interface HomeCardRaw {
  id?: string;
  span?: number;
}

/**
 * 工作台卡片目录与布局纯逻辑（可单测）。
 *
 * - 现有工具都可作为卡片放入工作台；
 * - 另提供「时钟」「天气」等非学校工具卡片；
 * - 一行最多两张：span=1 半宽、span=2 整行，由 Flex 自动换行保证。
 */
export class HomeCards {
  static readonly HALF: number = 1;
  static readonly FULL: number = 2;
  static readonly MAX: number = 24;
  /** 一行最多卡片数。 */
  static readonly PER_ROW: number = 2;

  static readonly CATALOG: HomeCardDef[] = [
    new HomeCardDef('quick', '常用工具', '首页快捷入口', AppSymbols.ALL, '#6E8CA8', HomeCardKind.LOCAL, ''),
    new HomeCardDef('tt', '今日课程', '周次 · 下一节课', AppSymbols.TIMETABLE, '#6E8CA8', HomeCardKind.DATA, 'tt'),
    new HomeCardDef('hw', '作业待交', '截止倒计时', AppSymbols.HOMEWORK, '#B98F63', HomeCardKind.DATA, 'hw'),
    new HomeCardDef('nt', '通知待处理', '班委通知', AppSymbols.NOTICE, '#B06A55', HomeCardKind.DATA, 'nt'),
    new HomeCardDef('power', '宿舍电费', '剩余电量', AppSymbols.POWER, '#C29A3B', HomeCardKind.DATA, 'power'),
    new HomeCardDef('fit', '体测', '录入 · 评分 · 历史', AppSymbols.FIT, '#5F8F5B', HomeCardKind.ENTRY, 'fit'),
    new HomeCardDef('vote', '投票', '限时/长时 · 实时结果', AppSymbols.VOTE, '#8A6A92', HomeCardKind.ENTRY, 'vote'),
    new HomeCardDef('water', '水量', '4/6 人间 · 月份记录', AppSymbols.WATER, '#4A88A8', HomeCardKind.ENTRY, 'water'),
    new HomeCardDef('draw', '抽签', '公平随机 · 可导出', AppSymbols.DRAW, '#4E9082', HomeCardKind.ENTRY, 'draw'),
    new HomeCardDef('group', '分组', '全班/最近抽签 · 分组', AppSymbols.GROUP, '#6E8CA8', HomeCardKind.ENTRY, 'group'),
    new HomeCardDef('roster', '名单', '班委 · 团员 · 全班', AppSymbols.ROSTER, '#8A6A92', HomeCardKind.ENTRY, 'roster'),
    new HomeCardDef('roll', '点名', '到 · 假 · 一键点名', AppSymbols.ROLL, '#B06A55', HomeCardKind.ENTRY, 'roll'),
    new HomeCardDef('jw', '教务', '卡片速览 · 自动登录', AppSymbols.JW, '#6E8CA8', HomeCardKind.ENTRY, 'jw'),
    new HomeCardDef('map', '地图', '2.5D · 楼层 · 道路导航', AppSymbols.MAP, '#4E9082', HomeCardKind.ENTRY, 'map'),
    new HomeCardDef('file', '文件传输', '临时云空间 · 保留 3 天', AppSymbols.FILE, '#4E9082', HomeCardKind.ENTRY, 'file'),
    new HomeCardDef('ppt', '演示', 'PPT 自动转换 · 分步播放', AppSymbols.PPT, '#6E8CA8', HomeCardKind.ENTRY, 'ppt'),
    new HomeCardDef('clock', '时钟', '当前时间与日期', AppSymbols.CLOCK, '#4E9082', HomeCardKind.LOCAL, ''),
    new HomeCardDef('weather', '天气', '系统天气服务', AppSymbols.WEATHER, '#4A88A8', HomeCardKind.LOCAL, '')
  ];

  /** 首次进入的默认布局：课程整行 + 作业/通知 + 电费/常用工具。 */
  static defaults(): HomeCardConfig[] {
    return [
      new HomeCardConfig('tt', HomeCards.FULL),
      new HomeCardConfig('hw', HomeCards.HALF),
      new HomeCardConfig('nt', HomeCards.HALF),
      new HomeCardConfig('power', HomeCards.HALF),
      new HomeCardConfig('quick', HomeCards.HALF)
    ];
  }

  static byId(id: string): HomeCardDef | undefined {
    for (let i = 0; i < HomeCards.CATALOG.length; i++) {
      if (HomeCards.CATALOG[i].id === id) {
        return HomeCards.CATALOG[i];
      }
    }
    return undefined;
  }

  /** 未知 id 的回退定义（正常运行不会走到，避免空引用）。 */
  static defOr(id: string): HomeCardDef {
    const def: HomeCardDef | undefined = HomeCards.byId(id);
    if (def !== undefined) {
      return def;
    }
    return new HomeCardDef(id, id, '', AppSymbols.INFO, '#4E9082', HomeCardKind.ENTRY, '');
  }

  /** 过滤未知/重复 id，宽度归一到 1/2，截断到 MAX（脏数据兜底）。 */
  static normalize(list: HomeCardConfig[]): HomeCardConfig[] {
    const out: HomeCardConfig[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < list.length && out.length < HomeCards.MAX; i++) {
      const cfg: HomeCardConfig = list[i];
      const id: string = cfg.id.trim();
      if (id.length === 0 || seen.has(id) || HomeCards.byId(id) === undefined) {
        continue;
      }
      seen.add(id);
      out.push(new HomeCardConfig(id, HomeCards.normalizeSpan(cfg.span)));
    }
    return out;
  }

  static normalizeSpan(span: number): number {
    return span === HomeCards.HALF ? HomeCards.HALF : HomeCards.FULL;
  }

  static spanLabel(span: number): string {
    return HomeCards.normalizeSpan(span) === HomeCards.HALF ? '半宽' : '整行';
  }

  static contains(list: HomeCardConfig[], id: string): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return true;
      }
    }
    return false;
  }

  /** 追加一张卡片（已存在/未知 id 不变）。 */
  static add(list: HomeCardConfig[], id: string): HomeCardConfig[] {
    const next: HomeCardConfig[] = HomeCards.normalize(list);
    if (HomeCards.contains(next, id) || HomeCards.byId(id) === undefined) {
      return next;
    }
    if (next.length >= HomeCards.MAX) {
      return next;
    }
    next.push(new HomeCardConfig(id, HomeCards.HALF));
    return next;
  }

  static remove(list: HomeCardConfig[], id: string): HomeCardConfig[] {
    const next: HomeCardConfig[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== id) {
        next.push(new HomeCardConfig(list[i].id, HomeCards.normalizeSpan(list[i].span)));
      }
    }
    return HomeCards.normalize(next);
  }

  /** 上移/下移一位（delta = -1 / 1）。 */
  static shift(list: HomeCardConfig[], id: string, delta: number): HomeCardConfig[] {
    const next: HomeCardConfig[] = HomeCards.normalize(list);
    let from: number = -1;
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        from = i;
        break;
      }
    }
    if (from < 0) {
      return next;
    }
    const to: number = from + delta;
    if (to < 0 || to >= next.length) {
      return next;
    }
    const moved: HomeCardConfig[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    return next;
  }

  /** 半宽 ⇄ 整行（带动画的状态切换由调用方用 animateTo 包裹）。 */
  static toggleSpan(list: HomeCardConfig[], id: string): HomeCardConfig[] {
    const next: HomeCardConfig[] = HomeCards.normalize(list);
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i].span = HomeCards.normalizeSpan(next[i].span) === HomeCards.HALF
          ? HomeCards.FULL : HomeCards.HALF;
        break;
      }
    }
    return next;
  }

  /** 指定宽度（角落拖动缩放落位时使用）。 */
  static withSpan(list: HomeCardConfig[], id: string, span: number): HomeCardConfig[] {
    const next: HomeCardConfig[] = HomeCards.normalize(list);
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i].span = HomeCards.normalizeSpan(span);
        break;
      }
    }
    return next;
  }

  /** 按下标移动（长按拖拽排序落位时使用）。 */
  static moveTo(list: HomeCardConfig[], from: number, to: number): HomeCardConfig[] {
    const next: HomeCardConfig[] = HomeCards.normalize(list);
    if (from < 0 || to < 0 || from >= next.length || to >= next.length || from === to) {
      return next;
    }
    const moved: HomeCardConfig[] = next.splice(from, 1);
    next.splice(to, 0, moved[0]);
    return next;
  }

  static unusedDefs(list: HomeCardConfig[]): HomeCardDef[] {
    const out: HomeCardDef[] = [];
    for (let i = 0; i < HomeCards.CATALOG.length; i++) {
      if (!HomeCards.contains(list, HomeCards.CATALOG[i].id)) {
        out.push(HomeCards.CATALOG[i]);
      }
    }
    return out;
  }

  static encode(list: HomeCardConfig[]): string {
    const raw: HomeCardRaw[] = [];
    for (let i = 0; i < list.length; i++) {
      raw.push({ id: list[i].id, span: HomeCards.normalizeSpan(list[i].span) });
    }
    return JSON.stringify(raw);
  }

  static decode(text: string): HomeCardConfig[] {
    if (text.length === 0) {
      return [];
    }
    try {
      const raw: HomeCardRaw[] = JSON.parse(text) as HomeCardRaw[];
      const list: HomeCardConfig[] = [];
      for (let i = 0; i < raw.length; i++) {
        const id: string = raw[i].id ?? '';
        const span: number = raw[i].span ?? HomeCards.HALF;
        if (id.length > 0) {
          list.push(new HomeCardConfig(id, span));
        }
      }
      return HomeCards.normalize(list);
    } catch (e) {
      Log.w(TAG, '解析首页卡片布局失败');
      return [];
    }
  }

  private static async store(): Promise<preferences.Preferences | undefined> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return undefined;
    }
    try {
      return await preferences.getPreferences(ctx, { name: STORE });
    } catch (e) {
      Log.w(TAG, '打开首页卡片存储失败');
      return undefined;
    }
  }

  private static key(sid: string): string {
    return 'layout_' + (sid.length > 0 ? sid : 'anon');
  }

  /** 读取本机布局；从未保存过返回 undefined（调用方用默认布局）。 */
  static async load(sid: string): Promise<HomeCardConfig[] | undefined> {
    const store: preferences.Preferences | undefined = await HomeCards.store();
    if (store === undefined) {
      return undefined;
    }
    try {
      const exists: boolean = await store.has(HomeCards.key(sid));
      if (!exists) {
        return undefined;
      }
      const text: string = await store.get(HomeCards.key(sid), '') as string;
      if (text.length === 0) {
        return undefined;
      }
      return HomeCards.decode(text);
    } catch (e) {
      return undefined;
    }
  }

  static async save(sid: string, list: HomeCardConfig[]): Promise<void> {
    const store: preferences.Preferences | undefined = await HomeCards.store();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(HomeCards.key(sid), HomeCards.encode(HomeCards.normalize(list)));
      await store.flush();
    } catch (e) {
      Log.w(TAG, '保存首页卡片布局失败');
    }
  }
}
