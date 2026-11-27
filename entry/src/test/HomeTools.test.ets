import { HomeCards, HomeCardConfig } from '../main/ets/data/home/HomeCards';
import { ToolCatalog } from '../main/ets/data/tool/ToolCatalog';
import { UsageData } from '../main/ets/features/usage/UsageData';
import { ToolLaunch } from '../main/ets/app/ToolLaunch';
import { describe, it, expect } from '@ohos/hypium';
import { HomeTools, HomeToolsToggleResult } from '../main/ets/data/home/HomeTools';
import { NickLogic } from '../main/ets/features/home/NickLogic';
import { HomeDigest, HomeCardItem } from '../main/ets/features/home/HomeDigest';
import { HomeworkRow } from '../main/ets/data/homework/HomeworkModels';
import { HideData, HidePrefs } from '../main/ets/data/home/HidePrefs';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';

export default function homeToolsTest() {
  describe('NickLogic', () => {
    it('normalizes_nick', 0, () => {
      expect(NickLogic.normalize('  芙宁娜  ')).assertEqual('芙宁娜');
      expect(NickLogic.normalize('芙  宁  娜')).assertEqual('芙 宁 娜');
      expect(NickLogic.normalize('')).assertEqual('');
      expect(NickLogic.normalize('一二三四五六七八九十一二三四五六七').length).assertEqual(16);
      expect(NickLogic.display('', '未命名')).assertEqual('未命名');
      expect(NickLogic.display('芙宁娜', '未命名')).assertEqual('芙宁娜');
    });
  });

  describe('HidePrefs', () => {
    it('reads_and_writes_hide', 0, () => {
      const sections: Blob = JSON.parse('{"v":6,"hide":{"hwHide":{"a":true,"b":false},"ntHide":{"x":true},"foo":1}}') as Blob;
      const data: HideData = HidePrefs.read(sections);
      expect(data.hwHide.has('a')).assertTrue();
      expect(data.hwHide.has('b')).assertFalse();
      expect(data.ntHide.has('x')).assertTrue();
      data.hwHide.add('c');
      const next: Blob = HidePrefs.write(sections, data);
      const hide: Blob | undefined = next['hide'] as Blob;
      expect(hide !== undefined).assertTrue();
      expect(HidePrefs.isHwHidden(next, 'c')).assertTrue();
      expect(HidePrefs.isHwHidden(next, 'a')).assertTrue();
      expect(JsonBlob.asNumber(JsonBlob.get(hide, 'foo'), 0)).assertEqual(1);
    });
  });

  describe('HomeDigest', () => {
    it('greeting_and_date', 0, () => {
      expect(HomeDigest.hello(3)).assertEqual('夜深了');
      expect(HomeDigest.hello(8)).assertEqual('早上好');
      expect(HomeDigest.hello(12)).assertEqual('中午好');
      expect(HomeDigest.hello(16)).assertEqual('下午好');
      expect(HomeDigest.hello(21)).assertEqual('晚上好');
      expect(HomeDigest.dateText(new Date(2026, 10, 5))).assertEqual('2026-11-05');
      expect(HomeDigest.weekText(11)).assertEqual('第 11 周');
      expect(HomeDigest.weekText(undefined)).assertEqual('');
    });

    it('power_state_and_text', 0, () => {
      expect(HomeDigest.powerState(10, true, 30)).assertEqual('low');
      expect(HomeDigest.powerState(45, true, 30)).assertEqual('warn');
      expect(HomeDigest.powerState(90, true, 30)).assertEqual('ok');
      expect(HomeDigest.powerState(0, false, 30)).assertEqual('idle');
      expect(HomeDigest.powerStateText('low')).assertEqual('低电');
      expect(HomeDigest.powerStateText('warn')).assertEqual('偏低');
      expect(HomeDigest.powerStateText('ok')).assertEqual('充足');
      expect(HomeDigest.powerStateText('idle')).assertEqual('未选择');
      expect(HomeDigest.rotate(3, 2)).assertEqual(0);
      expect(HomeDigest.rotate(0, 0)).assertEqual(0);
    });

    it('tool_launch_limits_references_to_the_named_tool_and_official_links', 0, () => {
      const params: Record<string, Object> = { 'toolId': 'nt', 'noticeId': 'group@occ:12', 'taskId': 'other' };
      const wrapper: Record<string, Object> = { 'params': JSON.stringify(params) };
      expect(ToolLaunch.parse(wrapper)?.noticeId).assertEqual('group@occ:12');
      const invalid: Record<string, Object> = { 'params': 'broken' };
      expect(ToolLaunch.parse(invalid) === undefined).assertTrue();
      const route = ToolLaunch.parse(params);
      expect(route?.noticeId).assertEqual('group@occ:12');
      expect(route?.taskId).assertEqual('');
      expect(ToolLaunch.parse(undefined, 'https://example.com/#task-share=1') === undefined).assertTrue();
      expect(ToolLaunch.parse(undefined, 'https://tool.furina.fun/#task-share=1')?.toolId).assertEqual('hw');
      // 统一内容链接（App Linking）：只接管已声明的 /l/ 业务路径
      const draw = ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/draw/D1234ABCD?from=qr');
      expect(draw?.toolId).assertEqual('scan');
      expect(draw?.verifyLink).assertEqual('https://tool.furina.fun/l/draw/d1234abcd');
      const notice = ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/notice/group@occ:20261127');
      expect(notice?.toolId).assertEqual('nt');
      expect(notice?.noticeId).assertEqual('group@occ:20261127');
      const share = ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/task-share#s=%7B%22t%22%3A%22%E5%A4%8D%E4%B9%A0%22%7D');
      expect(share?.toolId).assertEqual('hw');
      expect(share?.taskShareUrl).assertEqual('https://tool.furina.fun/l/task-share#s=%7B%22t%22%3A%22%E5%A4%8D%E4%B9%A0%22%7D');
      expect(ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/notice/') === undefined).assertTrue();
      expect(ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/file/deck1') === undefined).assertTrue();
      expect(ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/course/2026-11-27/3-4') === undefined).assertTrue();
      expect(ToolLaunch.parse(undefined, 'https://www.tool.furina.fun/l/notice/abc') === undefined).assertTrue();
      expect(ToolLaunch.parse(undefined, 'https://tool.furina.fun/l/task-share') === undefined).assertTrue();
    });

    it('homework_open_and_items', 0, () => {
      const a: HomeworkRow = new HomeworkRow();
      a.id = 'a';
      a.subject = '晚交的作业';
      a.date = '2026-11-20';
      a.time = '18:00';
      const b: HomeworkRow = new HomeworkRow();
      b.id = 'b';
      b.subject = '高等数学';
      b.content = '完成第三章习题';
      b.date = '2026-11-16';
      b.time = '18:00';
      const c: HomeworkRow = new HomeworkRow();
      c.id = 'c';
      c.subject = '已完成';
      const open: HomeworkRow[] = HomeDigest.hwOpen([a, b, c], (id: string) => id === 'c');
      expect(open.length).assertEqual(2);
      expect(open[0].id).assertEqual('b');
      const items: HomeCardItem[] = HomeDigest.hwItems(open);
      expect(items.length).assertEqual(2);
      expect(items[0].title).assertEqual('完成第三章习题');
      expect(items[0].id).assertEqual('b');
      expect(items[0].sub.indexOf('截止') === 0).assertTrue();
    });
  });

  describe('HomeTools', () => {
    it('toggle_adds_until_max', 0, () => {
      let ids: string[] = [];
      const first: HomeToolsToggleResult = HomeTools.toggle(ids, 'draw');
      expect(first.changed).assertTrue();
      ids = first.ids;
      ids = HomeTools.toggle(ids, 'group').ids;
      ids = HomeTools.toggle(ids, 'fit').ids;
      ids = HomeTools.toggle(ids, 'hw').ids;
      expect(ids.length).assertEqual(4);

      const fifth: HomeToolsToggleResult = HomeTools.toggle(ids, 'nt');
      expect(fifth.changed).assertFalse();
      expect(fifth.rejected).assertEqual('full');
      expect(fifth.ids.length).assertEqual(4);
    });

    it('toggle_removes_existing', 0, () => {
      const ids: string[] = ['draw', 'group', 'fit'];
      const result: HomeToolsToggleResult = HomeTools.toggle(ids, 'group');
      expect(result.changed).assertTrue();
      expect(result.rejected).assertEqual('');
      expect(result.ids.length).assertEqual(2);
      expect(result.ids.indexOf('group') < 0).assertTrue();
      expect(HomeTools.contains(result.ids, 'draw')).assertTrue();
    });

    it('toggle_rejects_unknown_tool', 0, () => {
      const result: HomeToolsToggleResult = HomeTools.toggle([], 'not_a_tool');
      expect(result.changed).assertFalse();
      expect(result.rejected).assertEqual('unknown');
    });

    it('normalize_filters_unknown_and_dedupes', 0, () => {
      const ids: string[] = ['draw', 'draw', 'nope', '', 'group'];
      const normalized: string[] = HomeTools.normalize(ids);
      expect(normalized.length).assertEqual(2);
      expect(normalized[0]).assertEqual('draw');
      expect(normalized[1]).assertEqual('group');
    });

    it('merges_old_ppt_shortcuts_and_cards_into_file', 0, () => {
      expect(HomeTools.normalize(['ppt', 'draw', 'file']).join(',')).assertEqual('file,draw');
      const cards: HomeCardConfig[] = HomeCards.normalize([new HomeCardConfig('ppt', 1), new HomeCardConfig('file', 2)]);
      expect(cards.length).assertEqual(1);
      expect(cards[0].id).assertEqual('file');
      expect(cards[0].span).assertEqual(1);
      expect(ToolCatalog.visibleTools().some(tool => tool.id === 'ppt')).assertFalse();
      const help = UsageData.ofCategory('team');
      expect(help.some(card => card.id === 'ppt')).assertFalse();
      expect(help.filter(card => card.id === 'file' && card.steps.join('').includes('班级课件')).length).assertEqual(1);
    });

    it('normalize_truncates_to_max', 0, () => {
      const ids: string[] = ['draw', 'group', 'fit', 'hw', 'nt', 'vote'];
      expect(HomeTools.normalize(ids).length).assertEqual(4);
    });

    it('remove_is_noop_for_absent', 0, () => {
      const ids: string[] = ['draw'];
      const next: string[] = HomeTools.remove(ids, 'group');
      expect(next.length).assertEqual(1);
      expect(next[0]).assertEqual('draw');
    });
  });
}
