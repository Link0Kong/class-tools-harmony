export class ToolLaunch {
  toolId: string;
  homeworkId: string = '';
  taskId: string = '';
  noticeId: string = '';
  taskShareUrl: string = '';

  constructor(toolId: string) {
    this.toolId = toolId;
  }

  static parse(parameters: Record<string, Object> | undefined, uri: string = ''): ToolLaunch | undefined {
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
    if (['home', 'hw', 'nt', 'tt', 'vote', 'water', 'power', 'ppt'].indexOf(tool) < 0) return undefined;
    const launch = new ToolLaunch(tool);
    if (tool === 'hw') {
      launch.homeworkId = ToolLaunch.id(parameters['homeworkId']);
      launch.taskId = ToolLaunch.id(parameters['taskId']);
    } else if (tool === 'nt') {
      launch.noticeId = ToolLaunch.id(parameters['noticeId']);
    }
    return launch;
  }

  private static id(value: Object | undefined): string {
    return typeof value === 'string' && value.length <= 512 ? value : '';
  }
}
