/**
 * 法律文本（隐私政策 / 用户协议）的端内副本。
 *
 * 文本来源：`web/legal/harmony/{privacy,terms}.html`（2026-11-17 V1.0 正式文本），
 * 由构建时脚本提取正文并压缩为 `resources/rawfile/legal/*.txt`；端内只读本机资源，
 * 不请求网络。资源缺失/损坏时用 `fallback()` 的关键要点兜底，并保留在线正式文本入口。
 *
 * 关键信息（版本 / 生效日期 / 运营者 / 联系方式）必须与 `web/legal/manifest.json` 一致：
 * 修改协议时先更新法律文档与 manifest，再同步本文件与 rawfile 文本。
 */
export class LegalInfo {
  kind: string = '';
  title: string = '';
  scope: string = '';
  version: string = 'V1.0';
  effectiveDate: string = '2026年11月17日';
  lastUpdated: string = '2026年11月17日';
  operator: string = '陈子麒（个人开发者）';
  email: string = 'Ko_Link@outlook.com';
  /** rawfile 相对路径（不带前导斜杠）。 */
  rawPath: string = '';
  /** 当前已部署的在线正式文本（2026-11-23 备案通过，正式 HTTPS 域名）。 */
  onlineUrl: string = '';

  constructor(kind: string, title: string, scope: string, rawPath: string, onlineUrl: string) {
    this.kind = kind;
    this.title = title;
    this.scope = scope;
    this.rawPath = rawPath;
    this.onlineUrl = onlineUrl;
  }
}

export class LegalSection {
  heading: string = '';
  body: string = '';
  /** 1 = 章标题（##），2 = 小节标题（###），0 = 无标题前言。 */
  level: number = 0;

  constructor(heading: string, body: string, level: number) {
    this.heading = heading;
    this.body = body;
    this.level = level;
  }
}

export class LegalDoc {
  info: LegalInfo = LegalTexts.info(LegalTexts.PRIVACY);
  title: string = '';
  metaLines: string[] = [];
  sections: LegalSection[] = [];
  /** true = 使用了端内兜底摘要（正文资源不可用）。 */
  fallback: boolean = false;

  /** 正文是否达到可读标准（避免半截资源静默展示）。 */
  usable(): boolean {
    if (this.sections.length < 5) {
      return false;
    }
    let chars: number = 0;
    for (let i = 0; i < this.sections.length; i++) {
      chars += this.sections[i].body.length;
    }
    return chars > 1000;
  }
}

export class LegalTexts {
  static readonly PRIVACY: string = 'privacy';
  static readonly TERMS: string = 'terms';

  static info(kind: string): LegalInfo {
    if (kind === LegalTexts.TERMS) {
      return new LegalInfo(
        LegalTexts.TERMS,
        '用户协议',
        '鸿蒙端（HarmonyOS / HarmonyOS NEXT 原生 App，含手机、平板、2in1 和手表）',
        'legal/terms.txt',
        'https://tool.furina.fun/legal/harmony/terms.html'
      );
    }
    return new LegalInfo(
      LegalTexts.PRIVACY,
      '隐私政策',
      '鸿蒙端（HarmonyOS / HarmonyOS NEXT 原生 App，含手机、平板、2in1 和手表）',
      'legal/privacy.txt',
      'https://tool.furina.fun/legal/harmony/privacy.html'
    );
  }

  /** 解析资源文本；格式：`# 标题` + 元信息行 + `---` + `##/###` 分节正文。 */
  static parse(raw: string, info: LegalInfo): LegalDoc {
    const doc: LegalDoc = new LegalDoc();
    doc.info = info;
    doc.title = info.title;
    if (raw.length === 0) {
      return doc;
    }
    const lines: string[] = raw.split('\n');
    let inBody: boolean = false;
    let current: LegalSection = new LegalSection('', '', 0);
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line === '---') {
        inBody = true;
        continue;
      }
      if (!inBody) {
        if (line.startsWith('# ')) {
          doc.title = line.substring(2).trim();
        } else {
          doc.metaLines.push(line);
        }
        continue;
      }
      let heading: string = '';
      let level: number = 0;
      if (line.startsWith('### ')) {
        heading = line.substring(4).trim();
        level = 2;
      } else if (line.startsWith('## ')) {
        heading = line.substring(3).trim();
        level = 1;
      }
      if (level > 0) {
        if (current.heading.length > 0 || current.body.length > 0) {
          doc.sections.push(current);
        }
        current = new LegalSection(heading, '', level);
      } else {
        current.body = current.body.length > 0 ? current.body + '\n' + line : line;
      }
    }
    if (current.heading.length > 0 || current.body.length > 0) {
      doc.sections.push(current);
    }
    return doc;
  }

  /** 读取/解析失败或正文过短时回落到要点摘要。 */
  static loadOrFallback(raw: string, info: LegalInfo): LegalDoc {
    const doc: LegalDoc = LegalTexts.parse(raw, info);
    if (doc.usable()) {
      return doc;
    }
    return LegalTexts.fallback(info);
  }

  /** 兜底：关键信息 + 可读要点，保证断网/资源损坏时也不是空白页。 */
  static fallback(info: LegalInfo): LegalDoc {
    const doc: LegalDoc = new LegalDoc();
    doc.info = info;
    doc.title = info.title;
    doc.fallback = true;
    doc.metaLines = [
      '文档版本：' + info.version,
      '生效日期：' + info.effectiveDate,
      '最近更新：' + info.lastUpdated,
      '运营者：' + info.operator,
      '联系邮箱：' + info.email,
      '适用范围：' + info.scope
    ];
    doc.sections = [
      new LegalSection('适用范围与运营者', info.scope + '。本端是班级内部辅助工具，不是学校官方平台，不提供公开注册、'
        + '支付、广告或公共服务；仅面向班级官方名单内的成员。运营者：' + info.operator + '；联系邮箱：'
        + info.email + '；收到有效申请后 15 个工作日内处理。', 1),
      new LegalSection('我们处理哪些信息', '学号与姓名（仅用于和班级官方名单比对）、班级共享内容（名单/作业/通知/课表/电费水量/'
        + '投票/PPT/文件）、你的操作与偏好（作业完成、通知已处理、抽签/分组/体测、点名、昵称、关注宿舍、抄表）、'
        + '设备与诊断信息（系统/机型/屏幕/网络/时延，用于安全与适配）。不收集通讯录、精确位置、支付信息，'
        + '不做广告画像、不出售个人信息。', 1),
      new LegalSection('第三方与跨境', '云端使用腾讯云 CloudBase（上海）；PPT 源文件与转换产物存放于阿里云 OSS 香港'
        + '（公共读），属于跨境存储，首次使用前会单独告知并征得同意；华为账号/Push Kit 由华为提供。'
        + '体测健康数据、教务密码、华为账号标识按敏感个人信息规则处理。', 1),
      new LegalSection('保存期限与你的权利', '登录会话约 30 天（Windows 约 29 天）；通知等本机缓存有期限；'
        + '你可以查阅、更正、删除、撤回同意、注销或导出数据，也可退出登录并清除本机数据。'
        + '云端物理删除需邮件申请（15 个工作日内）。', 1),
      new LegalSection('完整文本', '端内正文资源读取失败，以上为要点摘要。请点击下方「在线查看全文」阅读正式文本（'
        + info.onlineUrl + '），或通过 ' + info.email + ' 索取。', 1)
    ];
    return doc;
  }

  /** 从元信息行中取 `键：值`（找不到返回空串）。 */
  static metaValue(doc: LegalDoc, key: string): string {
    const prefix: string = key + '：';
    for (let i = 0; i < doc.metaLines.length; i++) {
      const line: string = doc.metaLines[i];
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length).trim();
      }
    }
    return '';
  }
}
