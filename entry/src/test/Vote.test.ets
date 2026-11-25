import { describe, it, expect } from '@ohos/hypium';
import {
  PollAudience,
  PollDraft,
  PollOption,
  PollResultVisibility,
  PollSettings,
  PollSummary,
  PollDetail,
  PollDetailResult,
  PollListResult,
  VoteLimits,
  VoteResult
} from '../main/ets/data/vote/VoteModels';
import { VoteLogic, PollOptionRow } from '../main/ets/data/vote/VoteLogic';
import { VoteRpc } from '../main/ets/data/vote/VoteRpc';
import { VoteRepository } from '../main/ets/data/vote/VoteRepository';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';
import { FakeApi } from './support/FakeApi';

const POLL_JSON: string = '{"ok":true,"polls":['
  + '{"id":"poll_1","title":"班会时间","description":"选一个","mode":"quick","owner_name":"班长",'
  + '"settings":{"multi":false,"maxChoices":1,"anonymous":true,"allowChange":true,"resultVisibility":"afterVote"},'
  + '"deadline":1794675000000,"status":"open","created_at":1794600000000,'
  + '"audience":"committee","audience_count":0,"closed":false,"total":3,"has_voted":true,'
  + '"counts":{"o1":2,"o2":1}},'
  + '{"id":"poll_2","title":"已结束","mode":"long","deadline":0,"status":"closed","created_at":1794500000000}'
  + '],"now":1794670000000,"has_more":false}';

const DETAIL_JSON: string = '{"ok":true,"poll":{"id":"poll_1","title":"班会时间","mode":"quick",'
  + '"settings":{"multi":true,"maxChoices":2,"anonymous":false,"allowChange":true,"resultVisibility":"always"},'
  + '"options":[{"id":"o1","text":"周五"},{"id":"o2","text":"周六"}],"deadline":0,"status":"open",'
  + '"audience":"all","audience_count":0},'
  + '"closed":false,"total":3,"counts":{"o1":2,"o2":1},"has_voted":true,"my_choices":["o1"],'
  + '"results_hidden":false,"mine":true,"can_manage":true,'
  + '"voters":[{"name":"甲","choices":["o1"]},{"name":"乙","choices":["o1","o2"]}],"now":1794670000000}';

function settings(multi: boolean, max: number): PollSettings {
  const s: PollSettings = new PollSettings();
  s.multi = multi;
  s.maxChoices = max;
  s.anonymous = true;
  s.allowChange = true;
  s.resultVisibility = PollResultVisibility.AFTER_VOTE;
  return s;
}

function draftWith(title: string, options: string[]): PollDraft {
  const draft: PollDraft = new PollDraft();
  draft.id = 'pabc12345';
  draft.title = title;
  draft.mode = 'quick';
  draft.options = [];
  for (let i = 0; i < options.length; i++) {
    const option: PollOption = new PollOption();
    option.id = 'o' + i;
    option.text = options[i];
    draft.options.push(option);
  }
  draft.settings = settings(false, 1);
  draft.deadline = 1794675000000;
  draft.audience = PollAudience.ALL;
  return draft;
}

export default function voteTest() {
  describe('VoteRpcBodies', () => {
    it('create_body_shape', 0, () => {
      const draft: PollDraft = draftWith('班会', ['周五', '周六']);
      const body: Blob = JSON.parse(VoteRpc.createBody(draft)) as Blob;
      expect(JsonBlob.asString(JsonBlob.get(body, 'p_id'), '')).assertEqual('pabc12345');
      expect(JsonBlob.asString(JsonBlob.get(body, 'p_title'), '')).assertEqual('班会');
      expect(JsonBlob.asString(JsonBlob.get(body, 'p_mode'), '')).assertEqual('quick');
      const options: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(body, 'p_options'));
      expect(options !== undefined && options.length === 2).assertTrue();
      const settingsBlob: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(body, 'p_settings'));
      expect(JsonBlob.asBoolean(JsonBlob.get(settingsBlob, 'multi'), true)).assertFalse();
      expect(JsonBlob.asString(JsonBlob.get(body, 'p_audience'), '')).assertEqual('all');
      expect(JsonBlob.asNumber(JsonBlob.get(body, 'p_deadline'), 0)).assertEqual(1794675000000);
    });

    it('submit_dedupes_choices', 0, () => {
      const body: Blob = JSON.parse(VoteRpc.submitBody('poll_1', ['o1', 'o1', 'o2'])) as Blob;
      const choices: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(body, 'p_choices'));
      expect(choices !== undefined && choices.length === 2).assertTrue();
      expect(JsonBlob.asString(JsonBlob.get(body, 'p_id'), '')).assertEqual('poll_1');
    });

    it('manage_bodies', 0, () => {
      const close: Blob = JSON.parse(VoteRpc.manageBody('poll_1', 'close', 0, undefined)) as Blob;
      expect(JsonBlob.asString(JsonBlob.get(close, 'p_action'), '')).assertEqual('close');
      const extend: Blob = JSON.parse(VoteRpc.manageBody('poll_1', 'extend', 1794680000000, undefined)) as Blob;
      expect(JsonBlob.asNumber(JsonBlob.get(extend, 'p_deadline'), 0)).assertEqual(1794680000000);
    });
  });

  describe('VoteRpcParser', () => {
    it('parses_list', 0, () => {
      const list = VoteRpc.parseList(POLL_JSON);
      expect(list.polls.length).assertEqual(2);
      expect(list.serverNow).assertEqual(1794670000000);
      expect(list.polls[0].id).assertEqual('poll_1');
      expect(list.polls[0].settings.anonymous).assertTrue();
      expect(list.polls[0].audience).assertEqual(PollAudience.COMMITTEE);
      expect(list.polls[0].hasVoted).assertTrue();
      expect(list.polls[0].counts.get('o1')).assertEqual(2);
      expect(VoteRpc.parseList('bad').polls.length).assertEqual(0);
    });

    it('parses_detail', 0, () => {
      const detail = VoteRpc.parseDetail(DETAIL_JSON);
      expect(detail.poll.id).assertEqual('poll_1');
      expect(detail.poll.options.length).assertEqual(2);
      expect(detail.poll.settings.multi).assertTrue();
      expect(detail.poll.settings.maxChoices).assertEqual(2);
      expect(detail.total).assertEqual(3);
      expect(detail.hasVoted).assertTrue();
      expect(detail.myChoices.join(',')).assertEqual('o1');
      expect(detail.canManage).assertTrue();
      expect(detail.voters.length).assertEqual(2);
      expect(detail.voters[1].choices.length).assertEqual(2);
    });
  });

  describe('VoteLogic', () => {
    it('anchors_server_deadline_to_elapsed_time_across_wall_clock_changes', 0, () => {
      const detail = new PollDetail();
      expect(detail.currentTime(500, 20)).assertEqual(500);
      detail.serverNow = 400000;
      detail.receivedElapsed = 5000;
      expect(detail.currentTime(500, 6200)).assertEqual(401200);
      expect(detail.currentTime(500000000, 6200)).assertEqual(401200);
      expect(detail.currentTime(900, 120)).assertEqual(900);
    });
    it('closed_and_results_visibility', 0, () => {
      const summary: PollSummary = new PollSummary();
      summary.status = 'open';
      summary.deadline = 1000;
      expect(VoteLogic.effectiveClosed(summary, 500)).assertFalse();
      expect(VoteLogic.effectiveClosed(summary, 1000)).assertTrue();
      summary.status = 'closed';
      expect(VoteLogic.effectiveClosed(summary, 1)).assertTrue();

      const always: PollSettings = settings(false, 1);
      always.resultVisibility = PollResultVisibility.ALWAYS;
      expect(VoteLogic.resultsVisible(always, false, false)).assertTrue();
      const afterVote: PollSettings = settings(false, 1);
      expect(VoteLogic.resultsVisible(afterVote, false, false)).assertFalse();
      expect(VoteLogic.resultsVisible(afterVote, false, true)).assertTrue();
      const afterClose: PollSettings = settings(false, 1);
      afterClose.resultVisibility = PollResultVisibility.AFTER_CLOSE;
      expect(VoteLogic.resultsVisible(afterClose, true, true)).assertTrue();
      expect(VoteLogic.resultsVisible(afterClose, false, true)).assertFalse();
    });

    it('validates_choices', 0, () => {
      const single: PollSettings = settings(false, 1);
      expect(VoteLogic.validateChoices(single, [], ['o1', 'o2'])).assertEqual('请至少选择 1 项');
      expect(VoteLogic.validateChoices(single, ['o1', 'o2'], ['o1', 'o2'])).assertEqual('单选投票只能选 1 项');
      expect(VoteLogic.validateChoices(single, ['o1'], ['o1', 'o2'])).assertEqual('');
      expect(VoteLogic.validateChoices(single, ['x'], ['o1', 'o2'])).assertEqual('选项无效');
      const multi: PollSettings = settings(true, 2);
      expect(VoteLogic.validateChoices(multi, ['o1', 'o2', 'o3'], ['o1', 'o2', 'o3'])).assertEqual('最多选 2 项');
      expect(VoteLogic.validateChoices(multi, ['o1', 'o2'], ['o1', 'o2'])).assertEqual('');
    });

    it('countdown_and_format', 0, () => {
      expect(VoteLogic.formatRemaining(0)).assertEqual('已截止');
      expect(VoteLogic.formatRemaining(5 * 60 * 1000)).assertEqual('剩 05:00');
      expect(VoteLogic.formatRemaining(65 * 1000)).assertEqual('剩 01:05');
      expect(VoteLogic.formatRemaining(3 * 60 * 60 * 1000)).assertEqual('剩 3 小时');
      expect(VoteLogic.formatRemaining(2 * 24 * 60 * 60 * 1000)).assertEqual('剩 2 天');
      expect(VoteLogic.countdown(0, 100)).assertEqual(0);
      expect(VoteLogic.countdown(1000, 400)).assertEqual(600);
      expect(VoteLogic.deadlineText(0)).assertEqual('不限时');
    });

    it('sort_and_filter', 0, () => {
      const open: PollSummary = new PollSummary();
      open.id = 'open1';
      open.deadline = 0;
      open.createdAt = 10;
      const closed: PollSummary = new PollSummary();
      closed.id = 'closed1';
      closed.status = 'closed';
      closed.createdAt = 20;
      const sorted: PollSummary[] = VoteLogic.sortPolls([closed, open], 100);
      expect(sorted[0].id).assertEqual('open1');
      expect(VoteLogic.filterForTab([closed, open], false, 100).length).assertEqual(1);
      expect(VoteLogic.filterForTab([closed, open], true, 100)[0].id).assertEqual('closed1');
    });

    it('validates_draft', 0, () => {
      const now: number = 1794670000000;
      expect(VoteLogic.validateDraft(draftWith('', ['a', 'b']), now)).assertEqual('请填写标题');
      expect(VoteLogic.validateDraft(draftWith('标题', ['a']), now)).assertEqual('至少需要 2 个选项');
      expect(VoteLogic.validateDraft(draftWith('标题', ['a', 'a']), now)).assertEqual('选项不能重复');
      expect(VoteLogic.validateDraft(draftWith('标题', ['a', 'b']), now)).assertEqual('');
      const past: PollDraft = draftWith('标题', ['a', 'b']);
      past.deadline = now - 1;
      expect(VoteLogic.validateDraft(past, now)).assertEqual('截止时间需晚于现在');
      expect(VoteLogic.validateDraft(draftWith('x'.repeat(VoteLimits.MAX_TITLE + 1), ['a', 'b']), now).indexOf('标题不能超过') === 0).assertTrue();
    });

    it('poll_id_format', 0, () => {
      expect(VoteLogic.isPollIdValid('pabc12345')).assertTrue();
      expect(VoteLogic.isPollIdValid('poll_1')).assertFalse();
      const fresh: string = VoteLogic.newPollId(1794670000000);
      expect(VoteLogic.isPollIdValid(fresh)).assertTrue();
      expect(fresh.length <= 33).assertTrue();
      expect(VoteLogic.newOptionId(1794670000000, 0).length <= 24).assertTrue();
    });

    it('validates_option_images', 0, () => {
      const draft: PollDraft = new PollDraft();
      draft.title = '配图投票';
      draft.deadline = 0;
      const a: PollOption = new PollOption();
      a.id = 'a1';
      a.text = '甲';
      a.img = 'data:image/jpeg;base64,AAAA';
      const b: PollOption = new PollOption();
      b.id = 'b1';
      b.text = '乙';
      draft.options = [a, b];
      draft.audience = 'all';
      expect(VoteLogic.validateDraft(draft, Date.now())).assertEqual('');
      a.img = 'http://x/y.jpg';
      expect(VoteLogic.validateDraft(draft, Date.now())).assertEqual('选项配图格式不支持');
      a.img = 'data:image/jpeg;base64,' + 'A'.repeat(150001);
      expect(VoteLogic.validateDraft(draft, Date.now()).indexOf('单张配图过大') === 0).assertTrue();
    });

    it('normalizes_custom_seats', 0, () => {
      expect(VoteLogic.normalizeSeats([5, 3, 3, 0, 71]).join(',')).assertEqual('3,5');
      expect(VoteLogic.normalizeSeats([]).length).assertEqual(0);
      expect(VoteLogic.validateAudience('custom', [])).assertEqual('指定成员至少选 1 人');
      expect(VoteLogic.validateAudience('custom', [3])).assertEqual('');
      expect(VoteLogic.validateAudience('all', [])).assertEqual('');
    });

    it('percent_and_option_rows', 0, () => {
      expect(VoteLogic.percent(1, 3)).assertEqual(33.3);
      expect(VoteLogic.percent(1, 0)).assertEqual(0);
      expect(VoteLogic.formatPercent(33.3)).assertEqual('33.3%');
    });
  });

  describe('VoteRepository', () => {
    it('list_and_detail_ok', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.pollListBody = POLL_JSON;
      api.pollDetailBody = DETAIL_JSON;
      const repo: VoteRepository = new VoteRepository(api);
      const list: PollListResult = await repo.list();
      expect(list.ok).assertTrue();
      expect(list.list.polls.length).assertEqual(2);
      expect(api.postPaths[0]).assertEqual('rpc/poll_list');
      const detail: PollDetailResult = await repo.detail('poll_1');
      expect(detail.ok).assertTrue();
      expect(detail.detail.poll.title).assertEqual('班会时间');
      expect(api.postPaths[1]).assertEqual('rpc/poll_detail');
    });

    it('submit_and_create', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.pollActionResult = '{"ok":true,"poll_id":"poll_1"}';
      const repo: VoteRepository = new VoteRepository(api);
      const submit: VoteResult = await repo.submit('poll_1', ['o1']);
      expect(submit.ok).assertTrue();
      expect(api.postPaths[0]).assertEqual('rpc/poll_submit');
      const create: VoteResult = await repo.create(draftWith('班会', ['a', 'b']));
      expect(create.ok).assertTrue();
      expect(create.pollId).assertEqual('poll_1');
      expect(api.postPaths[1]).assertEqual('rpc/poll_create');
    });

    it('error_message_surfaced', 0, async () => {
      const api: FakeApi = new FakeApi();
      api.pollActionResult = '{"ok":false,"error":"不在可见范围内"}';
      const repo: VoteRepository = new VoteRepository(api);
      const result: VoteResult = await repo.submit('poll_1', ['o1']);
      expect(result.ok).assertFalse();
      expect(result.message).assertEqual('不在可见范围内');
      api.failPosts = true;
      const failed: PollListResult = await repo.list();
      expect(failed.ok).assertFalse();
    });
  });
}
