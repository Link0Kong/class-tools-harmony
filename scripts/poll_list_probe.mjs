// 调试/清理：poll_list 查看测试投票，poll_manage delete 清理。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const gradleProps = join(here, '..', '..', 'android-class-tools', 'gradle.properties');
const REST = 'https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/';
const TEST_SID = '3260799999';
const TEST_NAME = '测试账号';

const keyLine = readFileSync(gradleProps, 'utf8').split(/\r?\n/).find((l) => l.startsWith('ct.publishableKey='));
const KEY = keyLine.slice('ct.publishableKey='.length).trim();

const vRes = await fetch(REST + 'rpc/class_verify', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ p_sid: TEST_SID, p_name: TEST_NAME })
});
const vBody = await vRes.json();
const token = Array.isArray(vBody) ? vBody[0].token : vBody.token;

async function rpc(name, payload) {
  const res = await fetch(REST + 'rpc/' + name, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + KEY,
      'Content-Type': 'application/json',
      'X-Class-Token': token
    },
    body: JSON.stringify(payload)
  });
  return await res.json();
}

const list = await rpc('poll_list', {});
console.log('ok=' + list.ok + ' polls=' + (list.polls || []).length);
for (const poll of list.polls || []) {
  console.log('  id=' + poll.id + ' title=' + poll.title + ' total=' + poll.total +
    ' has_voted=' + poll.has_voted + ' deadline=' + poll.deadline + ' status=' + poll.status);
}

const mine = (list.polls || []).filter((p) => p.title === '班会时间投票');
for (const poll of mine) {
  const del = await rpc('poll_manage', { p_id: poll.id, p_action: 'delete' });
  console.log('delete ' + poll.id + ': ' + JSON.stringify(del).slice(0, 200));
}
