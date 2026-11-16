// 调试：直接调 rpc/poll_create（测试身份），打印服务端响应。
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

const now = Date.now();
const payload = {
  p_id: 'poll_' + now + '_probe',
  p_title: '排查用投票',
  p_description: '',
  p_mode: 'quick',
  p_options: [{ id: 'o0', text: '选项A' }, { id: 'o1', text: '选项B' }],
  p_settings: { multi: false, maxChoices: 1, anonymous: true, allowChange: true, resultVisibility: 'afterVote' },
  p_deadline: now + 30 * 60 * 1000,
  p_audience: 'all'
};
const res = await fetch(REST + 'rpc/poll_create', {
  method: 'POST',
  headers: {
    Authorization: 'Bearer ' + KEY,
    'Content-Type': 'application/json',
    'X-Class-Token': token
  },
  body: JSON.stringify(payload)
});
console.log('status: ' + res.status);
console.log((await res.text()).slice(0, 800));
