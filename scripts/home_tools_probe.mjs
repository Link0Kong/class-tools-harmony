// 只读检查：云端 userdata.homeTools 是否与鸿蒙端一致（测试身份）。
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

const verifyRes = await fetch(REST + 'rpc/class_verify', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ p_sid: TEST_SID, p_name: TEST_NAME })
});
const vBody = await verifyRes.json();
const token = Array.isArray(vBody) ? vBody[0].token : vBody.token;

const res = await fetch(REST + 'userdata?select=*&id=eq.' + encodeURIComponent(TEST_SID), {
  headers: { Authorization: 'Bearer ' + KEY, 'X-Class-Token': token, 'Cache-Control': 'no-store' }
});
const rows = await res.json();
if (!Array.isArray(rows) || rows.length === 0) {
  console.log('no userdata row');
  process.exit(1);
}
const blob = JSON.parse(rows[0].blob);
console.log('cloud homeTools: ' + JSON.stringify(blob.homeTools));
console.log('cloud at.homeTools: ' + blob.at.homeTools);
console.log('cloud homeToolsAt: ' + blob.homeToolsAt);
console.log('cloud draw: ' + JSON.stringify(blob.draw));
console.log('cloud at.draw: ' + blob.at.draw);
console.log('cloud group: ' + JSON.stringify(blob.group));
console.log('cloud at.group: ' + blob.at.group);
console.log('cloud fit: ' + JSON.stringify(blob.fit));
console.log('cloud power: ' + JSON.stringify(blob.power));
console.log('cloud water: ' + JSON.stringify(blob.water));
console.log('cloud roster: ' + JSON.stringify(blob.roster));
console.log('cloud at.fit: ' + blob.at.fit);
