# 班级工具站 · HarmonyOS 客户端

面向班级日常事务的 HarmonyOS 原生客户端：用 ArkTS + ArkUI 编写，与网页、微信小程序、Android、Windows 四端共用同一套云端数据契约。

![version](https://img.shields.io/badge/version-1.0.13-4E9082)
![license](https://img.shields.io/badge/license-MIT-2EA44F)
![platform](https://img.shields.io/badge/platform-HarmonyOS-000000)
![stack](https://img.shields.io/badge/ArkTS-ArkUI-6E8CA8)

## 简介

- **客户端**：ArkTS + ArkUI，Stage 模型。任务首页在本机汇总个人待办与班级作业，完整编辑器和通知网页沿用当前登录身份。
- **零第三方运行依赖**：不引入第三方 UI 库、网络库或图标库，只使用系统 Kit。
- **多端同源**：与其余四端共用 CloudBase PostgreSQL + PostgREST 风格的数据契约
  （`userdata` v6、`marks`、`visits` 等），同一账号在任意端改动可互相同步。
- **自适应布局**：手机、平板、折叠屏与 2in1 使用同一套断点与内容宽度策略。

## 功能

| 工具 | 说明 |
|---|---|
| 抽签 `draw` | 支持范围、人数、排除与去重。云端存证后可分享核验链接或附二维码的结果图片，最近结果在本机留存 |
| 分组 `group` | 全班 / 最近抽签 / 手动名单，按组数或每组人数随机分组，复制与导出分享 |
| 课表 `tt` | 日/周视图、周次与单双周、下一节，个人课表优先 |
| 任务 `hw` | 可左右滑动切换五个智能分类和自定义分组，支持本机待办、作业截止与逾期、完成和提醒、作业及通知转任务、单任务链接分享和导入。个人任务和班级作业支持全屏详情，可查看截止、提醒、步骤与附件。完整编辑器支持分组、步骤和附件 |
| 通知 `nt` | 与网页共用五项统计、原始消息、附件预览、已处理标记和管理入口 |
| 体测 `fit` | 国标评分、BMI、历史记录与导出 |
| 名单 `roster` | 班委/团员/全班分类、搜索与职位标签（不展示学号） |
| 点名 `roll` | 全班/班委/团员、自定义名单、到/假、统计与导出 |
| 电费 `power` | 关注宿舍、24h/7d/30d 趋势、同期比较、低电提醒 |
| 水量 `water` | 按月抄表、用量统计、整段云端同步 |
| 投票 `vote` | 单选/多选、匿名/实名、可改票、范围与时长、选项配图 |
| 演示 `ppt` | PPT 兼容包/PDF/分步图/视频，分片上传与在线播放 |
| 文件传输 `file` | 同账号设备互传，分片上传、签名下载，文件保留 3 天 |
| 校园地图 `map` | 加载校园地图 H5，原生顶栏、刷新与浏览器降级 |
| 统计 `stats` | 班级使用情况与版本/设备分布（已脱敏） |
| 诊断 `diag` | 本机自检 + 服务健康 + 上报诊断报告 |

### 桌面卡片与通知

- 在「我的 → 桌面服务卡片」或桌面的系统服务卡片列表添加工作台、课表、通知或待办，任选 2×2、2×4 或 4×4。每张卡片可单独换色，点内容可进入对应工具或条目。
- 在「我的 → 通知」选择提醒种类和提前量，可发送即时通知或 20 秒定时测试。代理提醒的创建结果由系统返回，通知中心可点开任务等对应页面。系统拒绝代理排程时，可在单项作业或个人任务中点「添加到系统日历」，在日历编辑器确认保存。
- 开启通知后，鸿蒙会按网络和系统调度条件在后台刷新提醒。连堂课程按下一次实际上课铃计算。
- 课前倒计时与 PPT 上传使用鸿蒙实况窗。设备能力或场景权益不足时使用系统通知。限时投票的倒计时在通知中心展示。

## 服务地址

- **正式站**：`https://tool.furina.fun`（阿里云杭州 ECS + Caddy 自动 HTTPS）。Web 域名已于 2026-11-23 通过 ICP 备案
  （备案号 闽ICP备2026042939号-2，工信部入口 <https://beian.miit.gov.cn/>）；**应用内不展示「备案信息」行**。
- **同源路由**：`/v1/rdb/rest/`（正式数据面）、`/v1/rdb/rest-next/`（staging，**仅调试**）、`/drop`（文件传输 / 云空间）、
  `/pptfiles`（演示文件）、`/legal`（法律文本）、`/map`（校园地图）、`/account`、`/android/latest.json`。
- **明文（http）仅一处**：教务系统 `210.34.74.77`（学校系统无 HTTPS），在
  `entry/src/main/resources/base/profile/network_config.json` 里单独放行；其余端点一律 https。
- 备案期的 ECS 明文 IP `121.196.47.2` 只保留本机调试，**不进客户端常量**；本机联调确需临时放行时只改本地文件、不要提交。

## 下载

- Release 的 Assets 中提供 **未签名 HAP**（`entry-default-unsigned.hap`）。
- **模拟器**：接受未签名 HAP，可用 `hdc` / `bm install` 直接安装调试。
- **真机**：需要签名。用 DevEco Studio 登录华为账号后自动签名，或使用自有证书重新签名再安装。

## 开发与构建

环境：DevEco Studio 26.0+（含 HarmonyOS SDK API 26、hvigor、ohpm）。

```powershell
# 构建未签名 HAP（等价于 DevEco 的 assembleHap）
.\scripts\build.ps1

# 本地单元测试（hypium，无需设备）
.\scripts\test.ps1
```

脚本默认查找 `C:\Program Files\Huawei\DevEco Studio`；安装在其他位置时先设置：

```powershell
$env:DEVECO_HOME = '<DevEco Studio 安装目录>'
```

也可以直接调用 hvigor：

```powershell
$deveco = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
& (Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat') `
    --mode module -p product=default assembleHap --no-daemon
```

模拟器冒烟（需先启动模拟器并确保 `hdc list targets` 可见）：

```powershell
.\scripts\build.ps1
.\scripts\smoke_emulator.ps1
.\scripts\tool_smoke.ps1
```

产物路径：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

## 项目结构

```
AppScope/                     应用级配置（bundleName / 版本 / 图标）
entry/                        主模块
  src/main/ets/
    entryability/             入口 Ability
    pages/                    应用根页面（启动 → 身份门禁 → 外壳）
    app/                      Context 与数据层单例装配
    config/                   云端地址、超时与版本号
    data/                     网络、会话、同步、各业务数据仓库
    features/                 纯逻辑层（抽签/分组/体测/课表/地图等）
    ui/                       主题、组件、页面与 16 个工具界面
  src/main/resources/         资源与法律文本
  src/test/                   hypium 单元测试与跨端同步 fixture
scripts/                      构建、测试、模拟器冒烟、图标生成
docs/                         ROADMAP.md / ACCEPTANCE.md
```

## 技术栈

- **语言 / UI**：ArkTS + ArkUI（Stage 模型，声明式 UI）
- **SDK**：HarmonyOS SDK API 26，DevEco Studio 26.0
- **构建**：hvigor + ohpm
- **测试**：@ohos/hypium
- **数据**：CloudBase PostgreSQL + PostgREST 风格 REST 网关；本机 preferences 与文件分桶缓存

## 相关仓库

| 端 | 仓库 |
|---|---|
| 网页 / 站点 | https://github.com/Link0Kong/class-tools-site |
| 微信小程序 | https://github.com/Link0Kong/class-tools-mp |
| Android | https://github.com/Link0Kong/class-tools-android |
| HarmonyOS（本仓） | https://github.com/Link0Kong/class-tools-harmony |
| Windows | https://github.com/Link0Kong/class-tools-windows |

## 文档

- [路线图](docs/ROADMAP.md)
- [验收清单](docs/ACCEPTANCE.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [行为准则](CODE_OF_CONDUCT.md)
- [许可证](LICENSE)

## 隐私与数据

- 身份校验由班级服务完成，客户端只保存服务返回的会话凭证。
- 教务密码仅保存在本机 Asset Store，**不上传、不同步**。
- 日志、导出图与分享卡不包含 token、学号、姓名或宿舍号；关注宿舍仅在本机页面展示。
- 单元测试与示例数据只使用官方测试身份或临时 QA 身份，不包含真实学生信息。
- 仓库不包含服务端密钥、证书私钥或签名材料。

## 免责声明

- 本项目为个人/班级自建工具，**非学校官方项目**，与任何学校及教务系统无隶属或授权关系。
- 教务入口、校园地图等能力依赖第三方系统，其可用性与使用条款由相应提供方决定。
- 华为账号登录与 Push Kit 需要自行在 AppGallery Connect 创建应用并配置 client_id、证书与推送参数，仓库不提供这些凭据。
- 请遵守所在学校及相关服务的使用规定，使用风险自负。

## 许可证

[MIT](LICENSE)
