// 契约写探针（仅测试身份，幂等）：验证 userdata upsert 的请求体/Prefer/RLS 是否与鸿蒙数据层一致。
//
// 做法：GET 当前 blob → 原样 POST 回去（`resolution=merge-duplicates`）→ 再 GET 校验 v/键序未变。
// 不改变任何业务语义（blob 内容完全相同，只更新 ts）；不触碰真实账号。
//
// 用法：node scripts/contract_write_probe.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const gradleProps = join(here, '..', '..', 'android-class-tools', 'gradle.properties');
const REST = 'https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/';
const TEST_SID = '3260799999';
const TEST_NAME = '测试账号';

const keyLine = readFileSync(gradleProps, 'utf8')
  .split(/\r?\n/)
  .find((l) => l.startsWith('ct.publishableKey='));
if (!keyLine) throw new Error('publishableKey not found');
const KEY = keyLine.slice('ct.publishableKey='.length).trim();

function headers(token, prefer) {
  const h = {
    Authorization: 'Bearer ' + KEY,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'Cache-Control': 'no-store'
  };
  if (token) h['X-Class-Token'] = token;
  if (prefer) h.Prefer = prefer;
  return h;
}

async function call(method, path, body, token, prefer) {
  const res = await fetch(REST + path, {
    method,
    headers: headers(token, prefer),
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await res.text();
  return { status: res.status, text };
}

const verify = await call('POST', 'rpc/class_verify', { p_sid: TEST_SID, p_name: TEST_NAME });
const vBody = JSON.parse(verify.text);
const token = Array.isArray(vBody) ? vBody[0].token : vBody.token;
if (!token) throw new Error('no token');

const before = await call('GET', 'userdata?select=*&id=eq.' + encodeURIComponent(TEST_SID), undefined, token);
const rows = JSON.parse(before.text);
if (!Array.isArray(rows) || rows.length === 0) throw new Error('no userdata row to write back');
const blob = rows[0].blob;
const parsed = JSON.parse(blob);

const body = [{ id: TEST_SID, blob, ts: Date.now() }];
const write = await call('POST', 'userdata', body, token, 'return=representation,resolution=merge-duplicates');

const after = await call('GET', 'userdata?select=*&id=eq.' + encodeURIComponent(TEST_SID), undefined, token);
const afterRows = JSON.parse(after.text);
const afterBlob = Array.isArray(afterRows) && afterRows.length > 0 ? afterRows[0].blob : '';
let afterKeys = '';
let afterV = '';
try {
  const parsedAfter = JSON.parse(afterBlob);
  afterKeys = Object.keys(parsedAfter).join(',');
  afterV = String(parsedAfter.v);
} catch {
  afterKeys = '(parse failed)';
}

console.log('POST userdata status: ' + write.status);
console.log('POST userdata body_len: ' + write.text.length);
console.log('blob still v6: ' + (afterV === '6' ? 'yes' : 'NO'));
console.log('blob keys unchanged: ' + (afterKeys === Object.keys(parsed).join(',') ? 'yes' : 'NO'));
console.log('homeToolsAt unchanged: ' + (String(JSON.parse(afterBlob).homeToolsAt) === String(parsed.homeToolsAt) ? 'yes' : 'NO'));
