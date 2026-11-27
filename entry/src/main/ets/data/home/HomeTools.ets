import { ToolCatalog } from '../tool/ToolCatalog';

/** 首页快捷编辑结果。 */
export class HomeToolsToggleResult {
  ids: string[];
  /** 是否发生变化。 */
  changed: boolean;
  /** 拒绝原因：'' = 接受；'full' = 已满 4 个。 */
  rejected: string;

  constructor(ids: string[], changed: boolean, rejected: string) {
    this.ids = ids;
    this.changed = changed;
    this.rejected = rejected;
  }
}

/**
 * 首页常用工具（`userdata.homeTools`，≤4，与网页/小程序/安卓同契约）。
 *
 * 纯函数：不做 IO，便于单测；顺序即用户选择顺序（web 端拖动排序语义一致）。
 */
export class HomeTools {
  static readonly MAX: number = 4;

  /** 只保留已知工具 id、去重并截断到 MAX（读云端脏数据时的兜底）。 */
  static normalize(ids: string[]): string[] {
    const out: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      const id: string = ToolCatalog.directoryId(ids[i].trim());
      if (id.length === 0 || out.indexOf(id) >= 0) {
        continue;
      }
      if (ToolCatalog.byId(id) === undefined) {
        continue;
      }
      out.push(id);
    }
    return out.length > HomeTools.MAX ? out.slice(0, HomeTools.MAX) : out;
  }

  /** 点按加入/移出：已存在则移除；未满则追加；已满则拒绝。 */
  static toggle(current: string[], toolId: string): HomeToolsToggleResult {
    const id: string = ToolCatalog.directoryId(toolId);
    const ids: string[] = HomeTools.normalize(current);
    const index: number = ids.indexOf(id);
    if (index >= 0) {
      const next: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        if (i !== index) {
          next.push(ids[i]);
        }
      }
      return new HomeToolsToggleResult(next, true, '');
    }
    if (ToolCatalog.byId(id) === undefined) {
      return new HomeToolsToggleResult(ids, false, 'unknown');
    }
    if (ids.length >= HomeTools.MAX) {
      return new HomeToolsToggleResult(ids, false, 'full');
    }
    ids.push(id);
    return new HomeToolsToggleResult(ids, true, '');
  }

  static remove(current: string[], toolId: string): string[] {
    const id: string = ToolCatalog.directoryId(toolId);
    const ids: string[] = HomeTools.normalize(current);
    const out: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== id) {
        out.push(ids[i]);
      }
    }
    return out;
  }

  static contains(current: string[], id: string): boolean {
    return HomeTools.normalize(current).indexOf(ToolCatalog.directoryId(id)) >= 0;
  }
}
