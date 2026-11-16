// 只读检查：云端 fitrecs 是否写入（测试身份）。
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

const res = await fetch(
  REST + 'fitrecs?select=id,acc,arch,ts,data&acc=eq.' + encodeURIComponent(TEST_SID) + '&arch=eq.false&order=ts.desc',
  { headers: { Authorization: 'Bearer ' + KEY, 'X-Class-Token': token, 'Cache-Control': 'no-store' } }
);
const rows = await res.json();
console.log('fitrecs status: ' + res.status + ' rows: ' + (Array.isArray(rows) ? rows.length : 'n/a'));
if (Array.isArray(rows)) {
  for (const row of rows) {
    let parsed = null;
    try {
      parsed = JSON.parse(row.data);
    } catch {
      parsed = null;
    }
    console.log('  id=' + row.id + ' arch=' + row.arch + ' name=' + (parsed ? parsed.name : '?') +
      ' total=' + (parsed ? parsed.total : '?') + ' grade=' + (parsed ? parsed.grade : '?') +
      ' h=' + (parsed && parsed.fields ? parsed.fields.h : '?'));
  }
}
