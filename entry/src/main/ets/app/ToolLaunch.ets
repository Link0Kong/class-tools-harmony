import { TimetableFocus } from '../data/timetable/TimetableFocus';

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

  private static id(value: Object | undefined): string {
    return typeof value === 'string' && value.length <= 512 ? value : '';
  }
}
