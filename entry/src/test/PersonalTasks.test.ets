import { ScanPayload } from '../main/ets/data/scan/ScanPayload';
import { describe, expect, it } from '@ohos/hypium';
import { HomeworkRow } from '../main/ets/data/homework/HomeworkModels';
import { Blob, JsonBlob } from '../main/ets/data/sync/JsonBlob';
import { TaskAi } from '../main/ets/data/tasks/TaskAi';
import { HomeworkBrief, PersonalTask, TaskDraftStep, TaskShare, TaskView, field, taskObjects } from '../main/ets/data/tasks/TaskModels';
import { completeTask, mergeTaskEdits, TaskWire } from '../main/ets/data/tasks/TaskMerge';

function document(raw: string): Blob { return JsonBlob.parse(raw) as Blob; }
function homework(id: string, time: string): HomeworkRow {
  const row = new HomeworkRow();
  row.id = id;
  row.date = '2026-11-25';
  row.time = time;
  return row;
}

export default function personalTaskTest() {
  describe('PersonalTasks', () => {
    it('details_keep_full_deadline_and_read_wire_attachment_metadata', 0, () => {
      const tasks = PersonalTask.list(document('{"items":[{"id":"qa","title":"报告","due":"2026-11-25","dueTime":"08:30","repeat":"weekly","attachments":[{"n":"题目.pdf","t":"application/pdf","s":128,"d":"data:application/pdf;base64,QQ=="}]}]}'));
      const t = tasks[0];
      expect(t.deadlineText()).assertEqual('2026-11-25 08:30');
      expect(t.statusLabel(new Date(2026, 10, 25, 9).getTime())).assertEqual('已逾期');
      t.done = true;
      expect(t.statusLabel(new Date(2026, 10, 26).getTime())).assertEqual('已完成');
      expect(t.repeatLabel).assertEqual('每周');
      expect(t.attachments[0].name).assertEqual('题目.pdf');
      t.done = false;
      t.dueTime = '';
      expect(t.statusLabel(new Date(2026, 10, 25, 23, 59, 30).getTime())).assertEqual('待完成');
    });
    it('pager_follows_cross_client_order_and_retains_empty_and_same_named_groups', 0, () => {
      const doc = document('{"prefs":{"sidebarOrder":["done","bad","all","done"]},"lists":[{"id":"g2","name":"课程","order":2},{"id":"inbox","name":"收件箱"},{"id":"g1","name":"课程","order":1}],"items":[]}');
      const tabs = TaskView.categories(doc);
      expect(tabs.map((v: TaskView) => v.key).join(',')).assertEqual('done,all,myday,important,planned,group-g1,group-g2');
      expect(TaskView.index(tabs, 'group-g2')).assertEqual(6);
      expect(TaskView.index(tabs, 'removed')).assertEqual(1);
      expect(TaskView.index(tabs, 'done')).assertEqual(0);
      expect(TaskView.categories({}).map((v: TaskView) => v.key).join(',')).assertEqual('myday,important,planned,all,done');
    });

    it('pager_filters_smart_views_group_ids_and_query_without_reordering_other_pages', 0, () => {
      const rows = PersonalTask.list(document('{"items":[{"id":"1","title":"A","starred":true,"list":"g1","due":"2026-11-26","myDay":"2026-11-25","tags":["班级作业"],"order":4},{"id":"2","title":"B","due":"2026-11-25","list":"g2","notes":"Geography","order":1},{"id":"3","title":"C","list":"g1","done":true,"starred":true,"doneAt":50},{"id":"4","title":"D","done":true,"doneAt":100}]}'));
      const ids = (key: string, query: string = ''): string => {
        return TaskView.filter(rows, key, '2026-11-25', query).map((t: PersonalTask) => t.id).join(',');
      };
      expect(ids('all')).assertEqual('2,1');
      expect(ids('group-g1')).assertEqual('1');
      expect(ids('important')).assertEqual('1');
      expect(ids('planned')).assertEqual('2,1');
      expect(ids('myday')).assertEqual('1');
      expect(ids('done')).assertEqual('4,3');
      expect(ids('all', 'geo')).assertEqual('2');
      expect(ids('group-g1', '班级')).assertEqual('1');
      expect(ids('important', 'missing')).assertEqual('');
    });

    it('homework_overview_excludes_imported_completed_hidden_and_pruned', 0, () => {
      const imported = new PersonalTask();
      imported.sourceHwId = 'a';
      imported.done = true;
      const old = homework('old', '10:00');
      old.date = '2026-11-18';
      const rows = [old, homework('a', '07:10'), homework('b', '08:00'), homework('c', '09:00'),
        homework('d', '14:00'), homework('e', '11:00')];
      const brief = HomeworkBrief.build(rows, new Set<string>(['e']), [imported], new Date(2026, 10, 25, 10).getTime());
      expect(brief.pending.length).assertEqual(3);
      expect(brief.overdue).assertEqual(2);
      expect(brief.soon).assertEqual(1);
      expect(brief.highlights.map((item) => item.row.id).join(',')).assertEqual('b,d');
    });

    it('scan_only_recognizes_complete_official_urls_and_known_payloads', 0, () => {
      const ticket = '0123456789abcdef0123456789abcdef';
      const url = 'https://tool.furina.fun/#qr=' + ticket;
      expect(ScanPayload.parse(url).ticket).assertEqual(ticket);
      expect(ScanPayload.parse(url + '&p=harmony').harmony).assertTrue();
      expect(ScanPayload.parse(url.replace('https', 'http')).kind).assertEqual('');
      expect(ScanPayload.parse(url.replace('.fun/', '.fun.example/')).kind).assertEqual('');
      expect(ScanPayload.parse(url + 'xxx').kind).assertEqual('');
      expect(ScanPayload.parse('https://tool.furina.fun/#verify=d12345678').recordId).assertEqual('d12345678');
      const task = new PersonalTask();
      task.title = '分享测试';
      expect(ScanPayload.parse(TaskShare.link(task)).kind).assertEqual('task');
      const drawLink = ScanPayload.parse('https://tool.furina.fun/l/draw/dABC123456');
      expect(drawLink.kind).assertEqual('draw');
      expect(drawLink.recordId).assertEqual('dabc123456');
      expect(ScanPayload.parse('https://example.com/l/draw/dabc123456').kind).assertEqual('');
    });

    it('validates_deadline_and_time_without_rollover', 0, () => {
      expect(PersonalTask.validDue('2028-02-29', '23:59')).assertTrue();
      expect(PersonalTask.validDue('2026-02-29', '18:30')).assertFalse();
      expect(PersonalTask.validDue('', '08:00')).assertFalse();
      expect(PersonalTask.validDue('2026-11-25', '24:05')).assertFalse();
    });

    it('ai_prefills_separate_drafts_with_editable_notes_and_step_text', 0, () => {
      const response = TaskAi.parseResponse(200, '{"drafts":[{"title":" 演讲 ","notes":"三分钟",' +
        '"due":"2026-11-27","dueTime":"17:00","steps":[{"text":"做提纲","note":"列三点"}],"suggestions":["计时试讲"]},' +
        '{"title":"读材料","due":"2026-02-29","dueTime":"12:30"},{"title":" "}]}');
      expect(response.error).assertEqual('');
      expect(response.drafts.length).assertEqual(2);
      expect(response.drafts[0].title).assertEqual('演讲');
      expect(response.drafts[0].notes).assertEqual('三分钟\n\n完成建议\n• 计时试讲');
      expect(response.drafts[0].due).assertEqual('2026-11-27');
      expect(response.drafts[0].dueTime).assertEqual('17:00');
      expect(response.drafts[1].due).assertEqual('');
      expect(response.drafts[1].dueTime).assertEqual('');
      const draft = response.drafts[0];
      draft.steps[0].text = '先做提纲';
      draft.steps.push(new TaskDraftStep(' ', '没有步骤标题'));
      const steps = draft.stepRows();
      expect(steps.length).assertEqual(1);
      expect(field(steps[0], 'text')).assertEqual('先做提纲');
      expect(field(steps[0], 'note')).assertEqual('列三点');
      expect(steps[0]['done']).assertFalse();
    });

    it('ai_distinguishes_empty_malformed_and_rejected_responses', 0, () => {
      expect(TaskAi.parseResponse(200, '{"drafts":[]}').error.includes('没有整理出任务')).assertTrue();
      expect(TaskAi.parseResponse(200, '<html>').error.includes('未能读取')).assertTrue();
      expect(TaskAi.parseResponse(401, '').error.includes('身份')).assertTrue();
      expect(TaskAi.parseResponse(429, '').error.includes('次数')).assertTrue();
      expect(TaskAi.parseResponse(503, '').drafts.length).assertEqual(0);
      const drafts = TaskAi.parseResponse(200, '{"drafts":[' + new Array<string>(9).fill('{"title":"阅读"}').join(',') + ']}');
      expect(drafts.drafts.length).assertEqual(8);
    });

    it('share_interoperable_and_omits_personal_metadata', 0, () => {
      const t = new PersonalTask();
      t.title = 'A+B · 课程';
      t.notes = 'private note';
      t.sourceHwId = 'source';
      t.group = '课程';
      t.steps = ['第 1 步', '第 2 步', '第 3 步', '第 4 步'];
      const link = TaskShare.link(t);
      expect(link.startsWith('https://tool.furina.fun/l/task-share#s=')).assertTrue();
      const parsed = TaskShare.parse(link) as TaskShare;
      expect(parsed.title).assertEqual(t.title);
      expect(parsed.group).assertEqual(t.group);
      expect(parsed.notes).assertEqual('');
      expect(parsed.steps.length).assertEqual(3);
      expect(link.includes(t.sourceHwId)).assertFalse();
      expect(TaskShare.parse(link.replace('tool.furina.fun', 'example.com')) === undefined).assertTrue();
      expect(TaskShare.parse(TaskShare.PREFIX + '%') === undefined).assertTrue();
      expect(TaskShare.parse(TaskShare.PREFIX + encodeURIComponent('{"t":4}')) === undefined).assertTrue();
      // 旧分享链接（#task-share=）继续可读，解码后同样是任务快照
      const legacyPayload = encodeURIComponent(JSON.stringify({ 't': '复习', 'd': '', 'l': '未分组', 'n': '', 's': [] }));
      const legacy = TaskShare.parse(TaskShare.PREFIX + legacyPayload) as TaskShare;
      expect(legacy.title).assertEqual('复习');
      expect(TaskShare.parse('https://tool.furina.fun/l/task-share#s=' + legacyPayload)?.title).assertEqual('复习');
      // 片段缺失或跨域都不认
      expect(TaskShare.parse('https://tool.furina.fun/l/task-share') === undefined).assertTrue();
    });

    it('reads_cleared_text_row_json_text_or_object_and_preserves_old_wrapper', 0, () => {
      const empty = TaskWire.read('') as TaskWire;
      expect(PersonalTask.list(empty.snapshot).length).assertEqual(0);
      const snapshot = document('{"items":[{"id":"t","title":"测试"}],"v":1}');
      const text = JSON.stringify(snapshot);
      expect(JsonBlob.deepEqual((TaskWire.read(text) as TaskWire).snapshot, snapshot)).assertTrue();
      expect(JsonBlob.deepEqual((TaskWire.read(snapshot) as TaskWire).snapshot, snapshot)).assertTrue();
      expect(typeof empty.write(snapshot)).assertEqual('string');
      const old = document('{"v":1,"data":{"extra":true,"task":{"items":[]}}}');
      const wrapped = TaskWire.read(old) as TaskWire;
      const out = JsonBlob.asBlob(wrapped.write(snapshot)) as Blob;
      expect(JsonBlob.deepEqual(JsonBlob.asBlob(out['data'])?.['task'], snapshot)).assertTrue();
      expect(JsonBlob.asBlob(out['data'])?.['extra']).assertTrue();
      expect(TaskWire.read('{"items":"invalid"}') === undefined).assertTrue();
      expect(TaskWire.read('broken') === undefined).assertTrue();
    });

    it('edit_merge_preserves_remote_fields_preferences_and_concurrent_imports', 0, () => {
      const base = document('{"items":[{"id":"a","title":"old","notes":"old"}],"lists":[]}');
      const local = document('{"items":[{"id":"a","title":"new","notes":"old"},{"id":"new","sourceHwId":"hw"}]}');
      const remote = document('{"items":[{"id":"a","title":"old","notes":"remote","future":12},{"id":"b","sourceHwId":"hw"}],"groupsV2":["future"],"prefs":{"sort":"due"}}');
      const result = mergeTaskEdits(base, local, remote);
      const rows = taskObjects(result, 'items');
      expect(rows.length).assertEqual(2);
      expect(field(rows[0], 'title')).assertEqual('new');
      expect(field(rows[0], 'notes')).assertEqual('remote');
      expect(rows[0]['future']).assertEqual(12);
      expect(JsonBlob.deepEqual(result['prefs'], remote['prefs'])).assertTrue();
      expect(JsonBlob.deepEqual(result['groupsV2'], remote['groupsV2'])).assertTrue();
    });

    it('edited_inflight_mutation_rebased_quietly_and_remote_deletion_respected', 0, () => {
      const before = document('{"items":[{"id":"a","title":"A"}]}');
      const after = document('{"items":[{"id":"a","title":"A","done":true},{"id":"b","title":"B"}]}');
      const remote = document('{"items":[]}');
      const rows = taskObjects(mergeTaskEdits(before, after, remote), 'items');
      expect(rows.length).assertEqual(1);
      expect(field(rows[0], 'id')).assertEqual('b');
    });

    it('weekday_repeat_resets_steps_and_undo_removes_unedited_child', 0, () => {
      const rows = taskObjects(document('{"items":[{"id":"a","title":"A","repeat":"weekday","due":"2026-11-27","remindMode":"30","dueTime":"09:00","steps":[{"text":"复习","done":true}]}]}'), 'items');
      const now = new Date(2026, 10, 27, 10).getTime();
      expect(completeTask(rows, 'a', true, now, 'child')).assertTrue();
      expect(rows.length).assertEqual(2);
      expect(field(rows[1], 'due')).assertEqual('2026-11-30');
      expect(rows[1]['remindAt']).assertEqual(new Date(2026, 10, 30, 8, 30).getTime());
      expect(taskObjects(rows[1], 'steps')[0]['done']).assertEqual(false);
      expect(completeTask(rows, 'a', true, now, 'unused')).assertFalse();
      expect(completeTask(rows, 'a', false, now + 1, 'unused')).assertTrue();
      expect(rows.length).assertEqual(1);
    });
  });
}
