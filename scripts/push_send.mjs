#!/usr/bin/env node
/**
 * 枫丹工具箱 · Push Kit 发送脚本
 *
 * 凭据只从环境变量读取（不要写进仓库）：
 *   PUSH_APP_ID        应用 APP ID（6917621853264955129）
 *   PUSH_CLIENT_ID     AGC OAuth Client ID
 *   PUSH_CLIENT_SECRET AGC OAuth Client Secret
 *   PUSH_SERVICE_KEY   可选：CloudBase 服务端密钥（用于枚举所有 userdata.push.token）
 *
 * 用法：
 *   node scripts/push_send.mjs --to <pushToken> --title 标题 --body 内容
 *   node scripts/push_send.mjs --all --title 标题 --body 内容        # 需要 PUSH_SERVICE_KEY
 *   node scripts/push_send.mjs --watch --title 通知 --body 新通知    # 轮询 notices（需要 PUSH_SERVICE_KEY）
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const REST = 'https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/';
const APP_ID = process.env.PUSH_APP_ID || '6917621853264955129';
const CLIENT_ID = process.env.PUSH_CLIENT_ID || '';
const CLIENT_SECRET = process.env.PUSH_CLIENT_SECRET || '';
const SERVICE_KEY = process.env.PUSH_SERVICE_KEY || '';
const PUBLISHABLE_KEY = (() => {
  if (process.env.TCB_PUBLISHABLE_KEY) return process.env.TCB_PUBLISHABLE_KEY;
  try {
    const line = readFileSync('../android-class-tools/gradle.properties', 'utf8')
      .split(/\r?\n/).find((l) => l.startsWith('ct.publishableKey='));
    return line ? line.slice('ct.publishableKey='.length).trim() : '';
  } catch { return ''; }
})();

function arg(name, fallback = '') {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const has = (name) => process.argv.includes(name);

async function accessToken() {
  if (!CLIENT_ID || !CLIENT_SECRET) throw new Error('缺少 PUSH_CLIENT_ID / PUSH_CLIENT_SECRET');
  const body = new URLSearchParams({
    grant_type: 'client_credentials', client_id: CLIENT_ID, client_secret: CLIENT_SECRET
  });
  const res = await fetch('https://oauth-login.cloud.huawei.com/oauth2/v3/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body
  });
  const json = await res.json();
  if (!json.access_token) throw new Error('OAuth 失败：' + JSON.stringify(json).slice(0, 200));
  return json.access_token;
}

async function allTokens() {
  if (!PUBLISHABLE_KEY) throw new Error('缺少发布密钥（TCB_PUBLISHABLE_KEY）');
  const res = await fetch(REST + 'push_tokens?select=token&provider=eq.harmony', {
    headers: { Authorization: 'Bearer ' + PUBLISHABLE_KEY }
  });
  if (!res.ok) throw new Error('读取 push_tokens 失败：HTTP ' + res.status);
  const rows = await res.json();
  return rows.map((r) => r.token).filter((t) => typeof t === 'string' && t.length > 20);
}

async function send(tokens, title, body, data) {
  if (tokens.length === 0) throw new Error('没有可发送的 token');
  const token = await accessToken();
  const res = await fetch(`https://push-api.cloud.huawei.com/v1/${APP_ID}/messages:send`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      validate_only: false,
      message: {
        notification: { title, body },
        data: data ? JSON.stringify(data) : undefined,
        token: tokens.slice(0, 1000)
      }
    })
  });
  const text = await res.text();
  if (!res.ok) throw new Error('发送失败：HTTP ' + res.status + ' ' + text.slice(0, 300));
  console.log('已发送给 ' + Math.min(tokens.length, 1000) + ' 个 token：' + text.slice(0, 200));
}

async function pollOnce(stateFile) {
  const res = await fetch(REST + 'notices?select=id,title,ts&archived=eq.false&order=ts.desc&limit=5', {
    headers: { Authorization: 'Bearer ' + (PUBLISHABLE_KEY || SERVICE_KEY) }
  });
  if (!res.ok) throw new Error('读取 notices 失败：HTTP ' + res.status);
  const rows = await res.json();
  const state = existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : { seen: [] };
  const seen = new Set(state.seen);
  const fresh = rows.filter((r) => !seen.has(r.id));
  for (const r of fresh.slice().reverse()) {
    try {
      await send(await allTokens(), '班级新通知', r.title || '有一条新通知');
      seen.add(r.id);
      console.log('已推送：' + (r.title || r.id));
    } catch (e) {
      console.error('推送失败：' + e.message);
    }
  }
  writeFileSync(stateFile, JSON.stringify({ seen: [...seen].slice(-200) }));
}

const title = arg('--title', '班级新通知');
const body = arg('--body', '打开枫丹工具箱查看');
const data = arg('--data', '') ? JSON.parse(arg('--data', '')) : undefined;

try {
  if (has('--to')) {
    await send([arg('--to')], title, body, data);
  } else if (has('--all')) {
    await send(await allTokens(), title, body, data);
  } else if (has('--watch')) {
    const interval = Number(arg('--interval', '60')) * 1000;
    const stateFile = arg('--state', '.push_state.json');
    console.log('轮询 notices，每 ' + interval / 1000 + 's 一次；Ctrl+C 退出');
    for (;;) {
      try { await pollOnce(stateFile); } catch (e) { console.error(e.message); }
      await new Promise((r) => setTimeout(r, interval));
    }
  } else {
    console.log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0]);
  }
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
