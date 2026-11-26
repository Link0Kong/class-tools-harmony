import { http } from '@kit.NetworkKit';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { field, PersonalTask, TaskCreateDraft, TaskDraftStep, taskDay, taskObjects } from './TaskModels';

const ENDPOINT: string = 'https://tool.furina.fun/task-ai/suggest';

export class TaskAiResult {
  drafts: TaskCreateDraft[] = [];
  error: string = '';
}

export class TaskAi {
  static readonly MAX_TEXT: number = 6000;

  static parseResponse(status: number, body: string): TaskAiResult {
    const result = new TaskAiResult();
    if (status !== 200) {
      if (status === 400) result.error = '请输入可整理的任务文字后重试';
      else if (status === 401 || status === 403) result.error = '请重新验证班级身份后重试';
      else if (status === 429) result.error = '整理次数过多，请稍后重试';
      else result.error = '云端 AI 暂时不可用，请稍后重试';
      return result;
    }
    const doc = JsonBlob.parse(body);
    if (!doc || !Array.isArray(doc['drafts'])) {
      result.error = '未能读取整理结果，请重试';
      return result;
    }
    for (const item of taskObjects(doc, 'drafts').slice(0, 8)) {
      const draft = new TaskCreateDraft();
      draft.title = field(item, 'title').trim().slice(0, 200);
      if (!draft.title) continue;
      const due = field(item, 'due').trim();
      const time = field(item, 'dueTime').trim();
      if (PersonalTask.validDue(due, '')) draft.due = due;
      if (draft.due && PersonalTask.validDue(draft.due, time)) draft.dueTime = time;
      const notes = field(item, 'notes').trim();
      const advice = (JsonBlob.asArray(item['suggestions']) || []).slice(0, 10)
        .map((value: Object) => JsonBlob.asString(value, '').trim().slice(0, 500))
        .filter((value: string) => !!value).map((value: string) => '• ' + value);
      draft.notes = (advice.length ? (notes ? notes + '\n\n' : '') + '完成建议\n' + advice.join('\n') : notes)
        .slice(0, 5000);
      draft.steps = taskObjects(item, 'steps').slice(0, 50)
        .map((step: Blob, index: number) => new TaskDraftStep(field(step, 'text').trim().slice(0, 120),
          field(step, 'note').trim().slice(0, 500), index))
        .filter((step: TaskDraftStep) => !!step.text);
      result.drafts.push(draft);
    }
    if (!result.drafts.length) result.error = '这段文字没有整理出任务，可以补充事项后重试';
    return result;
  }

  static async suggest(text: string, token: string): Promise<TaskAiResult> {
    const input = text.trim();
    if (!input || input.length > TaskAi.MAX_TEXT) return TaskAi.parseResponse(400, '');
    if (!token) return TaskAi.parseResponse(401, '');
    const request = http.createHttp();
    try {
      const body: Blob = { 'text': input, 'localDate': taskDay(new Date()) };
      const response = await request.request(ENDPOINT, { method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'X-Class-Token': token },
        extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 45000, maxRedirects: 0,
        usingCache: false, expectDataType: http.HttpDataType.STRING });
      return TaskAi.parseResponse(response.responseCode, typeof response.result === 'string' ? response.result : '');
    } catch (_) {
      const result = new TaskAiResult();
      result.error = '整理请求未完成，请检查网络后重试';
      return result;
    } finally { request.destroy(); }
  }
}
