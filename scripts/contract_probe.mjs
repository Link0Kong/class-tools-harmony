// 契约探针（只读）：用官方测试身份核对云端响应形状，验证鸿蒙数据层解析假设。
//
// 只做 GET/POST RPC（class_verify/class_members/class_league 是只读 RPC），**不写任何业务数据**。
// 输出不含 token/学号/姓名，只有字段名与计数。
//
// 用法：node scripts/contract_probe.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const gradleProps = join(here, '..', '..', 'android-class-tools', 'gradle.properties');
const REST = 'https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/';
const TEST_SID = '3260799999';
const TEST_NAME = '测试账号';

function publishableKey() {
  const text = readFileSync(gradleProps, 'utf8');
  const line = text.split(/\r?\n/).find((l) => l.startsWith('ct.publishableKey='));
  if (!line) throw new Error('publishableKey not found');
  return line.slice('ct.publishableKey='.length).trim();
}

const KEY = publishableKey();

function headers(token) {
  const h = {
    Authorization: 'Bearer ' + KEY,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'Cache-Control': 'no-store'
  };
  if (token) h['X-Class-Token'] = token;
  return h;
}

async function req(method, path, body, token) {
  const res = await fetch(REST + path, {
    method,
    headers: headers(token),
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await res.text();
  let json = null;
  try {
    json = text.length ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: res.status, json, text };
}

const out = [];
function line(label, value) {
  out.push(label + ': ' + value);
}

const verify = await req('POST', 'rpc/class_verify', { p_sid: TEST_SID, p_name: TEST_NAME });
line('class_verify status', verify.status);
const vBody = Array.isArray(verify.json) ? verify.json[0] : verify.json;
const token = vBody && typeof vBody.token === 'string' ? vBody.token : '';
line('class_verify keys', vBody ? Object.keys(vBody).sort().join(',') : '(none)');
line('class_verify ok', vBody ? String(vBody.ok) : '(none)');
line('class_verify token_len', token.length);
line('class_verify is_admin', vBody ? String(vBody.is_admin) : '(none)');
line('class_verify role', vBody && typeof vBody.role === 'string' ? (vBody.role.length ? '(present)' : '(empty)') : '(none)');

if (!token) {
  console.log(out.join('\n'));
  process.exit(1);
}

const userdata = await req('GET', 'userdata?select=*&id=eq.' + encodeURIComponent(TEST_SID), undefined, token);
line('userdata status', userdata.status);
const rows = Array.isArray(userdata.json) ? userdata.json : [];
line('userdata rows', rows.length);
if (rows.length > 0) {
  line('userdata row keys', Object.keys(rows[0]).sort().join(','));
  const blob = rows[0].blob;
  line('userdata blob type', typeof blob);
  if (typeof blob === 'string') {
    try {
      const parsed = JSON.parse(blob);
      line('userdata blob keys', Object.keys(parsed).join(','));
      line('userdata blob v', String(parsed.v));
      line('userdata blob at keys', parsed.at ? Object.keys(parsed.at).join(',') : '(none)');
    } catch {
      line('userdata blob parse', 'failed');
    }
  }
}

const marks = await req('GET', 'marks?select=*&seat=eq.' + encodeURIComponent(TEST_SID), undefined, token);
line('marks status', marks.status);
line('marks rows', Array.isArray(marks.json) ? marks.json.length : '(not array)');
if (Array.isArray(marks.json) && marks.json.length > 0) {
  line('marks row keys', Object.keys(marks.json[0]).sort().join(','));
}

const members = await req('POST', 'rpc/class_members', {}, token);
line('class_members status', members.status);
const memberRows = Array.isArray(members.json) ? members.json : [];
line('class_members count', memberRows.length);
if (memberRows.length > 0) {
  line('class_members row keys', Object.keys(memberRows[0]).sort().join(','));
  line('class_members is_test_absent', memberRows.every((m) => m.sid !== TEST_SID) ? 'yes' : 'NO');
}

const league = await req('POST', 'rpc/class_league', {}, token);
line('class_league status', league.status);
const leagueBody = Array.isArray(league.json) ? league.json[0] : league.json;
if (leagueBody) {
  line('class_league keys', Object.keys(leagueBody).sort().join(','));
  line('class_league count', String(leagueBody.count));
  const seats = Array.isArray(leagueBody.seats) ? leagueBody.seats : [];
  line('class_league seats', seats.length);
  if (seats.length > 0) line('class_league seat keys', Object.keys(seats[0]).sort().join(','));
}

console.log(out.join('\n'));
