/**
 * 应用统一 Symbol 图标资源表。
 *
 * 全部取自 HarmonyOS Symbol 系统图标库（sys.symbol.*），
 * 保证与系统图标一致的 24vp 网格、1.5vp 线宽与圆角语言。
 */
export class AppSymbols {
  static readonly HOME: Resource = $r('sys.symbol.house');
  static readonly ALL: Resource = $r('sys.symbol.square_grid_2x2');
  static readonly ME: Resource = $r('sys.symbol.person');

  static readonly SETTINGS: Resource = $r('sys.symbol.gearshape');
  static readonly SETTINGS_FILL: Resource = $r('sys.symbol.gearshape_fill');
  static readonly PLUS: Resource = $r('sys.symbol.plus');
  static readonly XMARK: Resource = $r('sys.symbol.xmark');
  static readonly MINUS: Resource = $r('sys.symbol.minus');
  static readonly TRASH: Resource = $r('sys.symbol.trash');
  static readonly ARROW_UP: Resource = $r('sys.symbol.arrow_up');
  static readonly ARROW_DOWN: Resource = $r('sys.symbol.arrow_down');
  /** 半宽 ⇄ 整行（横向缩放）。 */
  static readonly RESIZE_WIDTH: Resource = $r('sys.symbol.arrow_left_arrow_right');
  static readonly RESET: Resource = $r('sys.symbol.arrow_counterclockwise');
  /** 时钟 / 天气（非学校工具卡片）。 */
  static readonly CLOCK: Resource = $r('sys.symbol.clock');
  static readonly WEATHER: Resource = $r('sys.symbol.cloud_sun_fill');
  static readonly THERMOMETER: Resource = $r('sys.symbol.thermometer');
  static readonly HUMIDITY: Resource = $r('sys.symbol.drop');

  static readonly ARROW_RIGHT: Resource = $r('sys.symbol.arrow_right');
  static readonly ARROW_LEFT: Resource = $r('sys.symbol.arrow_left');
  static readonly CHECKMARK: Resource = $r('sys.symbol.checkmark');
  static readonly BELL: Resource = $r('sys.symbol.bell');
  static readonly INFO: Resource = $r('sys.symbol.info_circle');

  static readonly DRAW: Resource = $r('sys.symbol.shuffle');
  static readonly GROUP: Resource = $r('sys.symbol.person_2');
  static readonly FIT: Resource = $r('sys.symbol.figure_run');
  static readonly HOMEWORK: Resource = $r('sys.symbol.doc_text_badge_checkmark');
  static readonly NOTICE: Resource = $r('sys.symbol.bell');
  static readonly VOTE: Resource = $r('sys.symbol.checkmark_square');
  static readonly TIMETABLE: Resource = $r('sys.symbol.calendar');
  static readonly POWER: Resource = $r('sys.symbol.bolt_1');
  static readonly PPT: Resource = $r('sys.symbol.play_circle');
  static readonly WATER: Resource = $r('sys.symbol.drop');
  static readonly ROSTER: Resource = $r('sys.symbol.list_bullet');
  static readonly ROLL: Resource = $r('sys.symbol.checkmark_clipboard');
  static readonly DIAG: Resource = $r('sys.symbol.stethoscope');
  static readonly JW: Resource = $r('sys.symbol.graduationcap');
  static readonly MAP: Resource = $r('sys.symbol.map');
  static readonly FILE: Resource = $r('sys.symbol.arrow_left_arrow_right');
  static readonly USAGE: Resource = $r('sys.symbol.reports');
  /** 访问统计（仅管理员；系统 Symbol，无需新增资源文件）。 */
  static readonly STATS: Resource = $r('sys.symbol.reports');

  static readonly IMAGE: Resource = $r('sys.symbol.ohos_photo');
  static readonly VIDEO: Resource = $r('sys.symbol.video');
  static readonly AUDIO: Resource = $r('sys.symbol.music');
  static readonly ARCHIVE: Resource = $r('sys.symbol.archivebox');
  static readonly DOCUMENT: Resource = $r('sys.symbol.doc_text');
  static readonly FILE_OTHER: Resource = $r('sys.symbol.doc');

  /** 工具 id → 图标。未知 id 回退到信息图标，避免空白。 */
  static tool(id: string): Resource {
    if (id === 'draw') {
      return AppSymbols.DRAW;
    }
    if (id === 'group') {
      return AppSymbols.GROUP;
    }
    if (id === 'fit') {
      return AppSymbols.FIT;
    }
    if (id === 'hw') {
      return AppSymbols.HOMEWORK;
    }
    if (id === 'nt') {
      return AppSymbols.NOTICE;
    }
    if (id === 'vote') {
      return AppSymbols.VOTE;
    }
    if (id === 'tt') {
      return AppSymbols.TIMETABLE;
    }
    if (id === 'power') {
      return AppSymbols.POWER;
    }
    if (id === 'ppt') {
      return AppSymbols.PPT;
    }
    if (id === 'water') {
      return AppSymbols.WATER;
    }
    if (id === 'roster') {
      return AppSymbols.ROSTER;
    }
    if (id === 'roll') {
      return AppSymbols.ROLL;
    }
    if (id === 'diag') {
      return AppSymbols.DIAG;
    }
    if (id === 'stats') {
      return AppSymbols.STATS;
    }
    if (id === 'jw') {
      return AppSymbols.JW;
    }
    if (id === 'map') {
      return AppSymbols.MAP;
    }
    if (id === 'file') {
      return AppSymbols.FILE;
    }
    if (id === 'usage') {
      return AppSymbols.USAGE;
    }
    return AppSymbols.INFO;
  }

  /** 使用统计卡片 id → 图标。 */
  static usage(id: string): Resource {
    if (id === 'id') {
      return $r('sys.symbol.checkmark_shield');
    }
    if (id === 'nav') {
      return $r('sys.symbol.compass');
    }
    if (id === 'ft') {
      return AppSymbols.FIT;
    }
    if (id === 'stats') {
      return AppSymbols.USAGE;
    }
    if (id === 'fb') {
      return $r('sys.symbol.envelope');
    }
    return AppSymbols.tool(id);
  }

  static tab(index: number): Resource {
    if (index === 1) {
      return AppSymbols.ALL;
    }
    if (index === 2) {
      return AppSymbols.ME;
    }
    return AppSymbols.HOME;
  }
}
