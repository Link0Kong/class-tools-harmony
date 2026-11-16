#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""枫丹工具箱 · 推送巡检（每分钟一次，pythonw 无窗口运行）

- 读 notices（publishable key，公开只读）；
- 读 push_tokens 里 provider=harmony 的 token（公开只读）；
- 有新通知时用 Push Kit 服务端 API 下发；
- 首次运行只记基线，不补发历史。

凭据从仓库外 `harmony-signing/push.env` 读取；日志不打印 token/secret。
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime

HOME = os.path.expanduser("~")
SIGN_DIR = os.path.join(HOME, ".openclaw", "workspace", "harmony-signing")
ENV_FILE = os.path.join(SIGN_DIR, "push.env")
STATE_FILE = os.path.join(SIGN_DIR, "push_state.json")
LAST_FILE = os.path.join(SIGN_DIR, "push_tick.last")
LOG_FILE = os.path.join(SIGN_DIR, "push_watch.log")
GRADLE = os.path.join(HOME, ".openclaw", "workspace", "android-class-tools", "gradle.properties")
REST = "https://tool-d4gosudok46e0e081.api.tcloudbasegateway.com/v1/rdb/rest/"
OAUTH = "https://oauth-login.cloud.huawei.com/oauth2/v3/token"


def log(msg):
    line = "[%s] %s\n" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def load_env():
    env = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r", encoding="utf-8-sig") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    try:
        with open(GRADLE, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("ct.publishableKey="):
                    env["TCB_PUBLISHABLE_KEY"] = line.split("=", 1)[1].strip()
                    break
    except Exception:
        pass
    return env


def class_token(env, pk):
    sid = env.get("CLASS_SID", "3260799999")
    name = env.get("CLASS_NAME", "测试账号")
    try:
        _, j = http_json(REST + "rpc/class_verify", "POST",
                         headers={"Authorization": "Bearer " + pk},
                         body={"p_sid": sid, "p_name": name})
        if isinstance(j, list) and j:
            j = j[0]
        tok = j.get("token") if isinstance(j, dict) else ""
        return tok or ""
    except Exception:
        return ""


def http_json(url, method="GET", headers=None, body=None, form=False):
    data = None
    h = dict(headers or {})
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            h["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.status, json.loads(resp.read().decode() or "null")


def read_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def write_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f)


def access_token(env):
    cache_file = os.path.join(SIGN_DIR, "push_token_cache.json")
    try:
        with open(cache_file, "r", encoding="utf-8") as f:
            c = json.load(f)
        if c.get("exp", 0) > time.time() + 120 and c.get("token"):
            return c["token"]
    except Exception:
        pass
    status, j = http_json(OAUTH, "POST", body={
        "grant_type": "client_credentials",
        "client_id": env.get("PUSH_CLIENT_ID", ""),
        "client_secret": env.get("PUSH_CLIENT_SECRET", ""),
    }, form=True)
    if status != 200 or not j.get("access_token"):
        raise RuntimeError("oauth failed %s" % status)
    token = j["access_token"]
    with open(cache_file, "w", encoding="utf-8") as f:
        json.dump({"token": token, "exp": time.time() + int(j.get("expires_in", 3600)) - 300}, f)
    return token


def main():
    try:
        with open(LAST_FILE, "w", encoding="utf-8") as f:
            f.write(str(int(time.time())))
    except Exception:
        pass
    env = load_env()
    pk = env.get("TCB_PUBLISHABLE_KEY", "")
    app_id = env.get("PUSH_APP_ID", "6917621853264955129")
    if not pk:
        log("缺少 publishable key，退出")
        return 0
    headers = {"Authorization": "Bearer " + pk}
    ct = class_token(env, pk)
    if ct:
        headers["X-Class-Token"] = ct
    try:
        _, notices = http_json(REST + "notices?select=id,title,ts&archived=eq.false&order=ts.desc&limit=20", headers=headers)
        if not isinstance(notices, list):
            log("notices 响应异常")
            return 0
        rows = [r for r in notices if r.get("id")]
        state = read_state()
        if state is None:
            write_state({"ids": [r["id"] for r in rows][:200]})
            log("首次运行，记录基线 %d 条" % len(rows))
            return 0
        seen = set(state.get("ids", []))
        fresh = [r for r in rows if r["id"] not in seen]
        state["ids"] = ([r["id"] for r in rows] + state.get("ids", []))[:200]
        write_state(state)
        if not fresh:
            return 0
        _, tokens = http_json(REST + "push_tokens?select=token&provider=eq.harmony&limit=1000", headers=headers)
        token_list = [t.get("token") for t in (tokens or []) if isinstance(t.get("token"), str) and len(t.get("token")) > 20]
        if not token_list:
            log("有新通知 %d 条，但无 harmony token" % len(fresh))
            return 0
        tok = access_token(env)
        latest = fresh[0]
        body = {
            "validate_only": False,
            "message": {
                "notification": {"title": "班级新通知", "body": (latest.get("title") or "有一条新通知")[:100]},
                "data": json.dumps({"page": "pages/nt/nt"}),
                "token": token_list[:1000],
            },
        }
        status, result = http_json("https://push-api.cloud.huawei.com/v1/%s/messages:send" % app_id,
                                   "POST", headers={"Authorization": "Bearer " + tok}, body=body)
        log("推送 %d 条新通知 → %d 个设备，HTTP %s %s" % (len(fresh), len(token_list), status,
              json.dumps(result, ensure_ascii=False)[:160]))
    except Exception as e:
        log("巡检失败：%s" % str(e)[:200])
    return 0


if __name__ == "__main__":
    sys.exit(main())
