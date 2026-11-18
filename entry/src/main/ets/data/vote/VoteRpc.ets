import { Blob, JsonBlob, JsonValue } from '../sync/JsonBlob';
import {
  Poll,
  PollAudience,
  PollDetail,
  PollDraft,
  PollList,
  PollMode,
  PollOption,
  PollSettings,
  PollSummary,
  PollVoter,
  PollResultVisibility,
  VoteLimits
} from './VoteModels';

/** 投票 RPC body 构造 + 响应解析（纯函数）。 */
export class VoteRpc {
  static listBody(): string {
    return '{}';
  }

  static detailBody(pollId: string): string {
    const body: Blob = {};
    body['p_id'] = pollId;
    return JSON.stringify(body);
  }

  static submitBody(pollId: string, choices: string[]): string {
    const body: Blob = {};
    body['p_id'] = pollId;
    const unique: string[] = [];
    for (let i = 0; i < choices.length; i++) {
      if (unique.indexOf(choices[i]) < 0) {
        unique.push(choices[i]);
      }
    }
    body['p_choices'] = unique;
    return JSON.stringify(body);
  }

  static createBody(draft: PollDraft): string {
    const body: Blob = {};
    body['p_id'] = draft.id;
    body['p_title'] = draft.title.trim();
    body['p_description'] = draft.description.trim();
    body['p_mode'] = draft.mode;
    body['p_options'] = optionsJson(draft.options);
    body['p_settings'] = settingsJson(draft.settings, draft.options.length);
    body['p_deadline'] = draft.deadline;
    body['p_audience'] = draft.audience;
    if (draft.audience === PollAudience.CUSTOM && draft.audienceSeats.length > 0) {
      body['p_audience_seats'] = draft.audienceSeats;
    }
    return JSON.stringify(body);
  }

  static manageBody(pollId: string, action: string, deadline: number, draft: PollDraft | undefined): string {
    const body: Blob = {};
    body['p_id'] = pollId;
    body['p_action'] = action;
    if (action === 'extend') {
      body['p_deadline'] = deadline;
    } else if (action === 'edit' && draft !== undefined) {
      body['p_title'] = draft.title.trim();
      body['p_description'] = draft.description.trim();
      body['p_options'] = optionsJson(draft.options);
      body['p_settings'] = settingsJson(draft.settings, draft.options.length);
      body['p_deadline'] = draft.deadline;
      body['p_audience'] = draft.audience;
      if (draft.audience === PollAudience.CUSTOM) {
        body['p_audience_seats'] = draft.audienceSeats;
      }
    }
    return JSON.stringify(body);
  }

  static parseList(raw: string): PollList {
    const list: PollList = new PollList();
    const body: Blob | undefined = JsonBlob.parse(raw);
    if (body === undefined) {
      return list;
    }
    const polls: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(body, 'polls'));
    if (polls !== undefined) {
      for (let i = 0; i < polls.length && list.polls.length < VoteLimits.MAX_LIST; i++) {
        const summary: PollSummary | undefined = VoteRpc.parseSummary(JsonBlob.asBlob(polls[i]));
        if (summary !== undefined) {
          list.polls.push(summary);
        }
      }
    }
    list.serverNow = JsonBlob.asNumber(JsonBlob.get(body, 'now'), 0);
    list.hasMore = JsonBlob.asBoolean(JsonBlob.get(body, 'has_more'), false);
    return list;
  }

  static parseDetail(raw: string): PollDetail {
    const detail: PollDetail = new PollDetail();
    const body: Blob | undefined = JsonBlob.parse(raw);
    if (body === undefined) {
      return detail;
    }
    detail.poll = VoteRpc.parsePoll(JsonBlob.asBlob(JsonBlob.get(body, 'poll')));
    detail.serverNow = JsonBlob.asNumber(JsonBlob.get(body, 'now'), 0);
    detail.closed = JsonBlob.asBoolean(JsonBlob.get(body, 'closed'), false);
    detail.total = Math.round(JsonBlob.asNumber(JsonBlob.get(body, 'total'), 0));
    detail.counts = VoteRpc.parseCounts(JsonBlob.get(body, 'counts'));
    detail.hasVoted = JsonBlob.asBoolean(JsonBlob.get(body, 'has_voted'), false);
    detail.myChoices = stringArray(JsonBlob.get(body, 'my_choices'));
    detail.resultsHidden = JsonBlob.asBoolean(JsonBlob.get(body, 'results_hidden'), false);
    detail.mine = JsonBlob.asBoolean(JsonBlob.get(body, 'mine'), false);
    detail.canManage = JsonBlob.asBoolean(JsonBlob.get(body, 'can_manage'), false);
    const voters: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(body, 'voters'));
    if (voters !== undefined) {
      for (let i = 0; i < voters.length; i++) {
        const voterBlob: Blob | undefined = JsonBlob.asBlob(voters[i]);
        if (voterBlob === undefined) {
          continue;
        }
        const voter: PollVoter = new PollVoter();
        voter.name = JsonBlob.asString(JsonBlob.get(voterBlob, 'name'), '');
        voter.choices = stringArray(JsonBlob.get(voterBlob, 'choices'));
        detail.voters.push(voter);
      }
    }
    return detail;
  }

  static parseSummary(obj: Blob | undefined): PollSummary | undefined {
    if (obj === undefined) {
      return undefined;
    }
    const id: string = JsonBlob.asString(JsonBlob.get(obj, 'id'), '').trim();
    if (id.length === 0) {
      return undefined;
    }
    const summary: PollSummary = new PollSummary();
    summary.id = id;
    summary.title = JsonBlob.asString(JsonBlob.get(obj, 'title'), '');
    summary.description = JsonBlob.asString(JsonBlob.get(obj, 'description'), '');
    summary.mode = normalizeMode(JsonBlob.asString(JsonBlob.get(obj, 'mode'), ''));
    summary.ownerName = JsonBlob.asString(JsonBlob.get(obj, 'owner_name'), '');
    summary.settings = VoteRpc.parseSettings(JsonBlob.asBlob(JsonBlob.get(obj, 'settings')));
    summary.deadline = JsonBlob.asNumber(JsonBlob.get(obj, 'deadline'), 0);
    summary.status = JsonBlob.asString(JsonBlob.get(obj, 'status'), 'open');
    summary.closedAt = JsonBlob.asNumber(JsonBlob.get(obj, 'closed_at'), 0);
    summary.createdAt = JsonBlob.asNumber(JsonBlob.get(obj, 'created_at'), 0);
    summary.updatedAt = JsonBlob.asNumber(JsonBlob.get(obj, 'updated_at'), 0);
    summary.audience = normalizeAudience(JsonBlob.asString(JsonBlob.get(obj, 'audience'), ''));
    summary.audienceCount = Math.round(JsonBlob.asNumber(JsonBlob.get(obj, 'audience_count'), 0));
    summary.closed = JsonBlob.asBoolean(JsonBlob.get(obj, 'closed'), false);
    summary.total = Math.round(JsonBlob.asNumber(JsonBlob.get(obj, 'total'), 0));
    summary.counts = VoteRpc.parseCounts(JsonBlob.get(obj, 'counts'));
    summary.hasVoted = JsonBlob.asBoolean(JsonBlob.get(obj, 'has_voted'), false);
    return summary;
  }

  static parsePoll(obj: Blob | undefined): Poll {
    const poll: Poll = new Poll();
    if (obj === undefined) {
      return poll;
    }
    const summary: PollSummary | undefined = VoteRpc.parseSummary(obj);
    if (summary !== undefined) {
      poll.id = summary.id;
      poll.title = summary.title;
      poll.description = summary.description;
      poll.mode = summary.mode;
      poll.ownerName = summary.ownerName;
      poll.settings = summary.settings;
      poll.deadline = summary.deadline;
      poll.status = summary.status;
      poll.closedAt = summary.closedAt;
      poll.createdAt = summary.createdAt;
      poll.updatedAt = summary.updatedAt;
      poll.audience = summary.audience;
      poll.audienceCount = summary.audienceCount;
      poll.closed = summary.closed;
      poll.total = summary.total;
      poll.counts = summary.counts;
      poll.hasVoted = summary.hasVoted;
    }
    const options: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'options'));
    if (options !== undefined) {
      for (let i = 0; i < options.length; i++) {
        const optionBlob: Blob | undefined = JsonBlob.asBlob(options[i]);
        if (optionBlob === undefined) {
          continue;
        }
        const option: PollOption = new PollOption();
        option.id = JsonBlob.asString(JsonBlob.get(optionBlob, 'id'), '');
        if (option.id.length === 0) {
          continue;
        }
        option.text = JsonBlob.asString(JsonBlob.get(optionBlob, 'text'), '');
        option.desc = JsonBlob.asString(JsonBlob.get(optionBlob, 'desc'), '');
        option.img = JsonBlob.asString(JsonBlob.get(optionBlob, 'img'), '');
        poll.options.push(option);
      }
    }
    const seats: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(obj, 'audience_seats'));
    if (seats !== undefined) {
      for (let i = 0; i < seats.length; i++) {
        const seat: number = JsonBlob.asNumber(seats[i], -1);
        if (seat > 0) {
          poll.audienceSeats.push(Math.round(seat));
        }
      }
    }
    return poll;
  }

  static parseSettings(obj: Blob | undefined): PollSettings {
    const settings: PollSettings = new PollSettings();
    if (obj === undefined) {
      return settings;
    }
    settings.multi = JsonBlob.asBoolean(JsonBlob.get(obj, 'multi'), false);
    settings.maxChoices = Math.round(JsonBlob.asNumber(JsonBlob.get(obj, 'maxChoices'), 1));
    settings.anonymous = JsonBlob.asBoolean(JsonBlob.get(obj, 'anonymous'), true);
    settings.allowChange = JsonBlob.asBoolean(JsonBlob.get(obj, 'allowChange'), true);
    const visibility: string = JsonBlob.asString(JsonBlob.get(obj, 'resultVisibility'), '');
    settings.resultVisibility = visibility.length > 0 ? visibility : PollResultVisibility.AFTER_VOTE;
    return settings;
  }

  static parseCounts(value: JsonValue | undefined): Map<string, number> {
    const counts: Map<string, number> = new Map<string, number>();
    const obj: Blob | undefined = JsonBlob.asBlob(value);
    if (obj === undefined) {
      return counts;
    }
    const keys: string[] = JsonBlob.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      counts.set(keys[i], Math.round(JsonBlob.asNumber(JsonBlob.get(obj, keys[i]), 0)));
    }
    return counts;
  }
}

function optionsJson(options: PollOption[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < options.length; i++) {
    const option: PollOption = options[i];
    const blob: Blob = {};
    blob['id'] = option.id;
    blob['text'] = option.text.trim();
    if (option.desc.trim().length > 0) {
      blob['desc'] = option.desc.trim();
    }
    if (option.img.length > 0) {
      blob['img'] = option.img;
    }
    out.push(blob);
  }
  return out;
}

function settingsJson(settings: PollSettings, optionCount: number): Blob {
  const normalized: PollSettings = settings.normalized(optionCount);
  const blob: Blob = {};
  blob['multi'] = normalized.multi;
  blob['maxChoices'] = normalized.maxChoices;
  blob['anonymous'] = normalized.anonymous;
  blob['allowChange'] = normalized.allowChange;
  blob['resultVisibility'] = normalized.resultVisibility;
  return blob;
}

function stringArray(value: JsonValue | undefined): string[] {
  const array: Object[] | undefined = JsonBlob.asArray(value);
  if (array === undefined) {
    return [];
  }
  const out: string[] = [];
  for (let i = 0; i < array.length; i++) {
    const text: string = JsonBlob.asString(array[i], '');
    if (text.length > 0) {
      out.push(text);
    }
  }
  return out;
}

function normalizeMode(raw: string): string {
  return raw.trim() === PollMode.QUICK ? PollMode.QUICK : PollMode.LONG;
}

function normalizeAudience(raw: string): string {
  const text: string = raw.trim();
  if (text === PollAudience.COMMITTEE || text === PollAudience.LEAGUE || text === PollAudience.CUSTOM) {
    return text;
  }
  return PollAudience.ALL;
}
