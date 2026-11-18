# 班级工具站 · HarmonyOS 原生 App

> 目标：把班级工具站搬到 HarmonyOS（ArkTS / ArkUI，Stage 模型），**真原生**（非 WebView 套壳），
> 与网页、微信小程序、安卓端共用同一套 CloudBase 数据契约。

- 包名：`com.furina.classtools`
- 版本：**1.0.7**（HarmonyOS 独立版本线；通知中心细化 + 手表端）
- 目标 SDK：HarmonyOS SDK API 26（DevEco Studio 26.0.0.865，模拟器 HarmonyOS 7.0.0）
- 语言/UI：ArkTS + ArkUI（Stage 模型），**零第三方依赖**（不引 UI 库/网络库/图标库）
- 状态：**1.0.7**：最新整合包已产出（396 单测全绿），桌面已交付
- 已实现工具：全部 16 个 —— `draw`、`group`、`fit`、`hw`、`nt`、`tt`、`power`、`water`、`vote`、`ppt`、`roll`、`diag`、`roster`、`jw`、`map`、`file`
- 已删除工具（2026-11-16，用户要求）：`chsi` 学信网、`today` 今日校园（不再恢复入口；相关 `features/chsi/`、`data/todaycampus/`、`ui/tools/ChsiScreen.ets`、`ui/tools/TodayCampusScreen.ets` 与对应单测均已移除）

## 目录

```
AppScope/                         应用级配置与图标
entry/src/main/ets/
  entryability/EntryAbility.ets   入口 Ability（注入 UIAbilityContext）
  pages/Index.ets                 应用根：启动 → 身份门禁 → 外壳 → 工具页
  app/                            AppGlobal（Context）/ Services（数据层单例装配）
  common/Log.ets                  日志（脱敏约定：不打印 token/学号/姓名/宿舍号）
  config/CloudConfig.ets          REST 根 + 公开 Publishable Key + 超时/版本
  data/net/                       HttpClient（PostgREST 封装）/ ApiResult
  data/auth/AuthRepository.ets    rpc/class_verify（学号+姓名 → 班级 token）
  data/session/                   Session 模型 + preferences 持久化
  data/tool/ToolCatalog.ets       16 个工具目录（id 与 userdata.homeTools 契约一致）
  data/cloudspace/                文件传输（ECS drop v2.2）模型/纯逻辑/API/仓库
  data/jw/JwCredentialStore.ets   本机教务密码安全存储（Asset Store，不同步/不上传）
  features/map/                   校园地图 H5 地址与降级逻辑
  features/jw/JwCredentialLogic.ets 凭据别名/校验/文案纯逻辑
  ui/theme/Breakpoints.ets        手机/平板/折叠屏断点与内容宽度
  ui/theme/Tokens.ets             品牌色/字号/圆角/间距/动效令牌 + 深色 hero 中性色
  ui/components/                  BrandMark / ToolTile / SectionHeader
  ui/screens/                     Identity / Home / All / Me / Tool 占位
  ui/tools/                       16 个工具页（含 MapScreen / FileTransferScreen）
  ui/shell/AppShell.ets           工作台 / 全部 / 我的 三 Tab（浅色底栏无黑影）
docs/                             路线图与里程碑报告（含 PORTING_MATRIX_20261115.md）
scripts/build.ps1                 本机构建脚本（CLI，等价于 DevEco 的 assembleHap）
```

## 构建

本机已装 DevEco Studio 26.0（含 HarmonyOS SDK 26、hvigor 6.26.9、ohpm 26、node 24）。
CLI 构建（无需打开 IDE）：

```powershell
cd C:\Users\Ko_Li\.openclaw\workspace\harmony-class-tools
.\scripts\build.ps1                 # 等价于下方命令
```

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
    --mode module -p product=default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（**未签名**）。

## 测试（无需设备）

```powershell
.\scripts\test.ps1                 # 本地单测（hypium），打印汇总并以失败退出码结束
```

当前 **382 个用例全绿**，其中包含与跨端 oracle（`mp-class-tools-tests/_sync_fixtures/merge_ref.js`）
逐字段对比的 userdata v6 合并用例：mp 写/web 读、web 写/mp 读、v5 迁移三条真实 fixture。
结果明细：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`。

> 运维提示：**构建与测试分开执行**（各开一次命令）。同一条命令里连跑 `build` + `test` 偶发 hvigor worker 卡死
> （本机 DevEco Studio 同时打开时更明显）；卡住时杀掉 `hvigorw.js` 进程重跑即可，不是代码问题。

另有两条**真实云端契约探针**（官方测试身份，只读 + 幂等 upsert，不改业务数据）：

```powershell
node scripts\contract_probe.mjs         # 校验 class_verify/userdata/marks/class_members/class_league 响应形状
node scripts\contract_write_probe.mjs   # 校验 userdata upsert（Prefer: return=representation,resolution=merge-duplicates）
```

## 运行（模拟器已实测通过）

模拟器 **接受未签名 HAP**，不需要华为账号签名即可安装调试：

```powershell
# 1) 启动模拟器（DevEco Device Manager 里也可以）
& 'C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe' -start 'Mate 90 Pro'

# 2) 构建 + 安装 + 启动 + 截图
.\scripts\build.ps1
.\scripts\smoke_emulator.ps1
```

- 登录用官方测试身份 `3260799999 / 测试账号`（自动化输入可用 `hdc shell uitest uiInput`）。
- 装到真机才需要签名（DevEco 登录华为账号 → 自动签名）；模拟器不需要。
- 验收记录见 [docs/M4_模拟器验收_20261114.md](docs/M4_模拟器验收_20261114.md)。

## 约定（红线）

- **数据层唯一口径**：`android-class-tools/docs/BACKEND_CONTRACT.md`；不新增顶层键、不改合并语义。
- **身份门禁不可绕过**：无有效班级 token 只能停在身份页；任一请求 401/403 立即清会话回身份页。
- **测试只用测试身份**：官方测试身份 `3260799999 / 测试账号`，或用完即删的 9999 段临时 QA 身份；
  严禁登录真实同学/管理员账号、严禁注入真实 token。
- **隐私**：日志、导出、页面不出现手机号/学号/宿舍号（电费页仅本人关注宿舍为例外，且不导出）。
- **零依赖**：不引第三方 ArkUI 组件库/网络库；新增依赖需先说明理由。
- 密钥：`CloudConfig.PUBLISHABLE_KEY` 是 role=anon 的**公开** key（与网页/小程序/安卓同值）；
  任何高权限 key、证书私钥、`deploy/creds.env` 严禁进入本项目。

## 与其它端的关系

| 端 | 位置 | 说明 |
|---|---|---|
| 网页 | `web/tools/index.html` | 单文件零依赖，产品与设计真源 |
| 小程序 | `mp-class-tools/` | 微信端，待上传发布 |
| 安卓 | `android-class-tools/` | Kotlin + Compose，本项目的功能与结构参考 |
| 鸿蒙 | 本目录 | ArkTS 原生，M0 骨架已就绪 |

## 路线图

见 [docs/ROADMAP.md](docs/ROADMAP.md)；上一轮（M77，其中学信网/今日校园两个工具已于 1.0.7 按用户要求删除）报告见
[docs/M77_报告_鸿蒙移植_20261115.md](docs/M77_报告_鸿蒙移植_20261115.md)；历史移植矩阵见 [docs/PORTING_MATRIX_20261115.md](docs/PORTING_MATRIX_20261115.md)。

## 运行与验收（2026-11-16）

```powershell
cd C:\Users\Ko_Li\.openclaw\workspace\harmony-class-tools
.\scripts\test.ps1            # 382 条单测
.\scripts\build.ps1           # 产出 unsigned HAP
.\scripts\smoke_emulator.ps1  # 启动模拟器并安装
```
交付物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（1.0.7，模拟器可直装；真机需 DevEco 自动签名）。
