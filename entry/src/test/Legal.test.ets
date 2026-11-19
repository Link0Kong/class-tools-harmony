import { describe, it, expect } from '@ohos/hypium';
import { LegalDoc, LegalTexts } from '../main/ets/data/legal/LegalTexts';

/**
 * 法律文本端内副本：元信息必须与 `web/legal/manifest.json`（V1.0 / 2026-11-17）一致，
 * 解析器要能承载完整正文，资源缺失时必须回落到可读要点摘要。
 */
export default function legalTest() {
  describe('LegalTexts', () => {
    it('metadata_matches_official_v1', 0, () => {
      const info = LegalTexts.info(LegalTexts.PRIVACY);
      expect(info.version).assertEqual('V1.0');
      expect(info.effectiveDate).assertEqual('2026年11月17日');
      expect(info.lastUpdated).assertEqual('2026年11月17日');
      expect(info.operator).assertEqual('陈子麒（个人开发者）');
      expect(info.email).assertEqual('Ko_Link@outlook.com');
      expect(info.rawPath).assertEqual('legal/privacy.txt');
      expect(info.onlineUrl.indexOf('/legal/harmony/privacy.html') > 0).assertTrue();

      const terms = LegalTexts.info(LegalTexts.TERMS);
      expect(terms.title).assertEqual('用户协议');
      expect(terms.rawPath).assertEqual('legal/terms.txt');
      expect(terms.onlineUrl.indexOf('/legal/harmony/terms.html') > 0).assertTrue();
    });

    it('parse_title_meta_and_sections', 0, () => {
      const info = LegalTexts.info(LegalTexts.PRIVACY);
      const raw: string = '# 隐私政策\n\n文档版本：V1.0\n生效日期：2026年11月17日\n运营者：陈子麒（个人开发者）\n'
        + '---\n## 一、定义与适用范围\n正文 A\n继续 A\n### 1.1 小节\n正文 B\n';
      const doc: LegalDoc = LegalTexts.parse(raw, info);
      expect(doc.title).assertEqual('隐私政策');
      expect(doc.metaLines.length).assertEqual(3);
      expect(doc.sections.length).assertEqual(2);
      expect(doc.sections[0].heading).assertEqual('一、定义与适用范围');
      expect(doc.sections[0].level).assertEqual(1);
      expect(doc.sections[0].body).assertEqual('正文 A\n继续 A');
      expect(doc.sections[1].heading).assertEqual('1.1 小节');
      expect(doc.sections[1].level).assertEqual(2);
      expect(doc.sections[1].body).assertEqual('正文 B');
      expect(LegalTexts.metaValue(doc, '运营者')).assertEqual('陈子麒（个人开发者）');
      expect(LegalTexts.metaValue(doc, '不存在')).assertEqual('');
    });

    it('fallback_has_key_info_and_readable_summary', 0, () => {
      const info = LegalTexts.info(LegalTexts.PRIVACY);
      const doc: LegalDoc = LegalTexts.fallback(info);
      expect(doc.fallback).assertTrue();
      expect(doc.sections.length >= 5).assertTrue();
      expect(doc.sections[0].body.indexOf('陈子麒（个人开发者）') >= 0).assertTrue();
      expect(doc.sections[0].body.indexOf('15 个工作日') >= 0).assertTrue();
      expect(doc.sections[2].body.indexOf('香港') >= 0).assertTrue();
      expect(LegalTexts.metaValue(doc, '联系邮箱')).assertEqual('Ko_Link@outlook.com');
      expect(doc.usable()).assertFalse();
    });

    it('empty_or_short_resource_falls_back', 0, () => {
      const info = LegalTexts.info(LegalTexts.TERMS);
      const empty: LegalDoc = LegalTexts.loadOrFallback('', info);
      expect(empty.fallback).assertTrue();
      expect(empty.title).assertEqual('用户协议');

      const short: LegalDoc = LegalTexts.loadOrFallback('# 用户协议\n---\n## 一、只有一节\n太短\n', info);
      expect(short.fallback).assertTrue();
    });

    it('complete_resource_is_not_fallback', 0, () => {
      const info = LegalTexts.info(LegalTexts.PRIVACY);
      let body: string = '';
      for (let i = 0; i < 200; i++) {
        body += '这是一段用于校验正文长度的示例文本，覆盖个人信息处理与用户权利说明。';
      }
      let raw: string = '# 隐私政策\n文档版本：V1.0\n---\n';
      for (let i = 0; i < 6; i++) {
        raw += '## 第 ' + i + ' 节\n' + body + '\n';
      }
      const doc: LegalDoc = LegalTexts.loadOrFallback(raw, info);
      expect(doc.fallback).assertFalse();
      expect(doc.sections.length).assertEqual(6);
      expect(doc.usable()).assertTrue();
    });
  });
}
