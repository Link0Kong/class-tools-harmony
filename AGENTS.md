# AGENTS.md — 鸿蒙端仓库（class-tools-harmony）

本仓库是「班级工具站」的 HarmonyOS 原生客户端（ArkTS + ArkUI）。
五个端各一个仓库：**site（网页/部署）· android · mp · harmony（本仓）· windows**。
**不要再按功能拆新仓库**；功能改动落在所属端的仓库里。

## 提交规则（硬性，2026-11-18 用户要求）

任何改动完成后，在仓库根目录执行：

```cmd
sync-repos.cmd "feat: 说明本次改了什么"
```

- 它会做安全检查 → `git add -A` → 提交 → **同时推 GitHub `origin` + Gitee `gitee`** → 核对两端 SHA。
- 只推一个远端 / 不写说明 / 写「更新」「修改」「同步」这类笼统说明 = **未完成交付**。
- 两个远端都是**私有仓库**，不要改为公开。
- 本机计划任务 `ClassToolsRepoAutoSync` 每 10 分钟兜底：工作区有改动且空闲 ≥5 分钟时自动提交并推双端。
  但 agent 仍应在完成改动时**主动执行上面命令**，不要依赖兜底。
- 核对状态：`sync-repos.cmd --check`。

## 禁止

- 提交签名与密钥：`*.p12`、`*.cer`、`*.p7b`、`*.jks`、`*.keystore`、`*.pem`、`*.key`、`*.env`。
- 提交构建/依赖产物：`**/build/`、`oh_modules/`、`.hvigor/`、`.cache/`、`artifacts/`（`.gitignore` 已排除）。
- 改动其他端仓库；跨端契约改动先看 `web/AGENTS.md` 与对应 `CONTRACT.md`。

## 验证

按 `README.md` 与 `docs/` 里的 Hvigor 构建 / 单测命令执行；截图放在已有的过程目录，不要新增构建产物入库。
测试一律使用测试身份（学号 9999 段 / 3260799999 测试账号）。
