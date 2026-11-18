/** 昵称规则（userdata.nick 字符串，跨端同步）。 */
export class NickLogic {
  static readonly MAX: number = 16;

  /** 去首尾空白、压缩连续空格、截断到 16 字符；空串 = 清除昵称。 */
  static normalize(raw: string): string {
    const trimmed: string = raw.trim();
    const parts: string[] = trimmed.split(' ');
    const words: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        words.push(parts[i]);
      }
    }
    let text: string = words.join(' ');
    if (text.length > NickLogic.MAX) {
      text = text.substring(0, NickLogic.MAX);
    }
    return text;
  }

  static display(nick: string, fallback: string): string {
    const value: string = NickLogic.normalize(nick);
    return value.length > 0 ? value : fallback;
  }
}
