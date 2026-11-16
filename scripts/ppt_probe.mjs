// 只读：查看真实 deck 的 manifest.files 结构（测试身份）。
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

const res = await fetch(REST + 'ppt_decks?select=id,title,manifest&deleted=eq.false&limit=5', {
  headers: { Authorization: 'Bearer ' + KEY, 'X-Class-Token': token, 'Cache-Control': 'no-store' }
});
const rows = await res.json();
console.log('status=' + res.status + ' rows=' + (Array.isArray(rows) ? rows.length : 'n/a'));
for (const row of Array.isArray(rows) ? rows : []) {
  const manifest = typeof row.manifest === 'string' ? JSON.parse(row.manifest) : row.manifest;
  console.log('id=' + row.id + ' title=' + row.title);
  console.log('  base=' + (manifest?.base || '(none)'));
  console.log('  files=' + JSON.stringify(manifest?.files));
  console.log('  slides=' + ((manifest?.slides||[]).length) + ' firstStep=' + JSON.stringify((manifest?.slides?.[0]?.steps?.[0])||null));
  console.log('  video=' + JSON.stringify(manifest?.video ? {s: manifest.video.s, chapters: (manifest.video.chapters||[]).length, first: (manifest.video.chapters||[])[0], second: (manifest.video.chapters||[])[1]} : null));
  console.log('  media_files=' + JSON.stringify((manifest?.media_files || []).slice(0, 2)));
}
