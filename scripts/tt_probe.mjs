// 只读检查：云端 site_assets id=tt 课表结构（测试身份）。
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

const res = await fetch(REST + 'site_assets?select=*&id=eq.tt', {
  headers: { Authorization: 'Bearer ' + KEY, 'X-Class-Token': token, 'Cache-Control': 'no-store' }
});
const rows = await res.json();
console.log('site_assets status: ' + res.status + ' rows: ' + (Array.isArray(rows) ? rows.length : 'n/a'));
if (Array.isArray(rows) && rows.length > 0) {
  const body = typeof rows[0].body === 'string' ? JSON.parse(rows[0].body) : rows[0].body;
  console.log('t=' + body.t + ' meta=' + JSON.stringify(body.meta) + ' courses=' + (body.c || []).length);
  const byDay = {};
  for (const c of body.c || []) {
    byDay[c.day] = (byDay[c.day] || 0) + 1;
  }
  console.log('courses by day index: ' + JSON.stringify(byDay));
  for (const c of (body.c || []).slice(0, 8)) {
    console.log('  day=' + c.day + ' p=' + c.start + '-' + c.end + ' name=' + c.name + ' weeks=' + c.weeks + ' parity=' + c.parity);
  }
}
