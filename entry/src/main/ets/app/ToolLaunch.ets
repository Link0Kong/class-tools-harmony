import { TimetableFocus } from '../data/timetable/TimetableFocus';

/**
 * 一次启动要打开的工具与目标（内部 Want / 通知 / 桌面卡片 / App Linking 共用）。
 *
 * App Linking（契约 docs/app-links/CONTRACT.md）只解析 `https://tool.furina.fun/l/...`：
 * - `/l/draw/<recordId>`  → 扫一扫页直接核验（`verifyLink`）
 * - `/l/notice/<noticeId>` → 通知详情（`noticeId`）
 * - `/l/task-share#s=<payload>` → 任务预览后确认导入（`taskShareUrl`）
 * 其余业务路径（课程/文件）暂由浏览器网页承接，不在 module.json5 声明。
 */
export class ToolLaunch {
  owner: string = '';
  objectId: string = '';
  timetableFocus?: TimetableFocus;

  parameters(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['toolId'] = this.toolId;
    if (this.owner) out['owner'] = this.owner;
    if (this.objectId) out['objectId'] = this.objectId;
    if (this.timetableFocus) {
      const focus = this.timetableFocus;
      out['courseAt'] = focus.time;
      out['courseName'] = focus.name;
      out['room'] = focus.room;
      out['period'] = focus.period;
      out['start'] = focus.start;
      out['end'] = focus.end;
      out['teacher'] = focus.teacher;
    }
    return out;
  }

  toolId: string;
  homeworkId: string = '';
  taskId: string = '';
  noticeId: string = '';
  taskShareUrl: string = '';
  verifyLink: string = '';

  constructor(toolId: string) {
    this.toolId = toolId;
  }

  static parse(parameters: Record<string, Object> | undefined, uri: string = ''): ToolLaunch | undefined {
    const link = ToolLaunch.parseContentLink(uri);
    if (link) return link;
    if (uri.length <= 8192 && uri.startsWith('https://tool.furina.fun/#task-share=')) {
      const share = new ToolLaunch('hw');
      share.taskShareUrl = uri;
      return share;
    }
    if (!parameters) return undefined;
    const nested = parameters['params'];
    if (typeof parameters['toolId'] !== 'string' && nested) {
      try {
        const payload: Object = typeof nested === 'string' && nested.length <= 8192 ? JSON.parse(nested) : nested;
        if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
        parameters = payload as Record<string, Object>;
      } catch (_) { return undefined; }
    }
    if (typeof parameters['toolId'] !== 'string') return undefined;
    const tool = parameters['toolId'] as string;
    if (['home', 'hw', 'nt', 'tt', 'vote', 'water', 'power', 'ppt', 'file'].indexOf(tool) < 0) return undefined;
    const launch = new ToolLaunch(tool);
    launch.owner = ToolLaunch.id(parameters['owner']);
    launch.objectId = ToolLaunch.id(parameters['objectId']);
    const time = Number(parameters['courseAt']);
    if (tool === 'tt' && Number.isFinite(time) && time > 0 && time <= 8640000000000000) {
      launch.timetableFocus = new TimetableFocus(time, ToolLaunch.id(parameters['courseName']), ToolLaunch.id(parameters['room']),
        Number(parameters['period']) || 0, Number(parameters['start']) || 0, Number(parameters['end']) || 0,
        ToolLaunch.id(parameters['teacher']));
    }
    if (tool === 'hw') {
      launch.homeworkId = ToolLaunch.id(parameters['homeworkId']);
      launch.taskId = ToolLaunch.id(parameters['taskId']);
    } else if (tool === 'nt') {
      launch.noticeId = ToolLaunch.id(parameters['noticeId']);
    }
    return launch;
  }

  /** 统一内容链接解析（严格白名单：scheme/host/路径/ID 规则与四端用例一致）。 */
  private static parseContentLink(uri: string): ToolLaunch | undefined {
    if (uri.length > 2048 || !uri.startsWith('https://tool.furina.fun/l/')) return undefined;
    const hashAt: number = uri.indexOf('#');
    const beforeHash: string = hashAt >= 0 ? uri.substring(0, hashAt) : uri;
    const fragment: string = hashAt >= 0 ? uri.substring(hashAt + 1) : '';
    // 取 pathname（host 之后的第一个 '/' 起），不能把 scheme://host 一起交给路径正则
    const hostAt: number = beforeHash.indexOf('://');
    const afterHost: string = hostAt >= 0 ? beforeHash.substring(hostAt + 3) : beforeHash;
    const slashAt: number = afterHost.indexOf('/');
    const rawPath: string = slashAt >= 0 ? afterHost.substring(slashAt) : '/';
    const queryAt: number = rawPath.indexOf('?');
    const path: string = queryAt >= 0 ? rawPath.substring(0, queryAt) : rawPath;
    const draw = /^\/l\/draw\/(d[0-9a-z]{8,31})$/i.exec(path);
    if (draw) {
      const launch = new ToolLaunch('scan');
      launch.verifyLink = 'https://tool.furina.fun/l/draw/' + draw[1].toLowerCase();
      return launch;
    }
    const notice = /^\/l\/notice\/([A-Za-z0-9_-]{1,80}(?:@occ:[0-9]{8})?)$/.exec(path);
    if (notice) {
      const launch = new ToolLaunch('nt');
      launch.noticeId = notice[1];
      return launch;
    }
    if (path === '/l/task-share') {
      if (fragment.length < 3 || fragment.length > 8192 || fragment.substring(0, 2) !== 's=') return undefined;
      const launch = new ToolLaunch('hw');
      launch.taskShareUrl = 'https://tool.furina.fun/l/task-share#s=' + fragment.substring(2);
      return launch;
    }
    return undefined;
  }

  private static id(value: Object | undefined): string {
    return typeof value === 'string' && value.length <= 512 ? value : '';
  }
}
