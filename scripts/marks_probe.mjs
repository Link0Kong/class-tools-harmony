// 只读检查：云端 marks（hw / ntdone）是否写入（测试身份）。
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

const res = await fetch(REST + 'marks?select=kind,ref,val,ts&seat=eq.' + encodeURIComponent(TEST_SID) + '&order=ts.desc', {
  headers: { Authorization: 'Bearer ' + KEY, 'X-Class-Token': token, 'Cache-Control': 'no-store' }
});
const rows = await res.json();
console.log('marks status: ' + res.status + ' rows: ' + (Array.isArray(rows) ? rows.length : 'n/a'));
if (Array.isArray(rows)) {
  const byKind = {};
  for (const row of rows) {
    byKind[row.kind] = (byKind[row.kind] || 0) + 1;
    if (rows.length <= 10) {
      console.log('  kind=' + row.kind + ' ref=' + row.ref + ' val=' + row.val);
    }
  }
  console.log('by kind: ' + JSON.stringify(byKind));
}
