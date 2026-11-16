# 验收清单（HarmonyOS 班级工具站，2026-11-15）

> 环境：DevEco Studio 26.0.0.865 / SDK API 26 / 模拟器 Mate 90 Pro（HarmonyOS 7.0.0）
> 构建：`.\scripts\build.ps1` → `entry/build/default/outputs/default/entry-default-unsigned.hap`
> 测试：`.\scripts\test.ps1` → **415/415**（M77 起）
> 安装：`.\scripts\smoke_emulator.ps1`

## 0. 自动化巡检（2026-11-15）

- [x] scripts/tool_smoke.ps1：14 个工具逐个打开并校验标题，**PASS=14/14**

## 1. 全局

- [x] 底部三 tab（工作台/全部/我的）+ 液体指示条（拉长 + 弹性）
- [x] tab 切换内容横滑动画（260ms，`AnimationMode.CONTENT_FIRST`）
- [x] 工具页进/出场（淡入 + 右滑 + 0.985 缩放）
- [x] 弹层滑入（投票发起/详情、作业详情、演示详情、抽签导出）+ 遮罩淡入
- [x] 卡片/行按压反馈（缩放 0.97–0.99）
- [x] 列表/卡片入场、秒级倒计时、趋势游标
- [x] 身份：测试身份/访客、切换与退出
- [x] 昵称编辑（userdata.nick 跨端同步）
- [x] 工作台对齐小程序：问候、今日课程、宿舍电费、作业待交（5s 轮换）、通知待处理（5s 轮换/状态/新通知角标）、常用工具（≤4/空态）、下拉刷新、tab 回来自动刷新、骨架屏、卡片轻微浮动
- [x] 首页快捷编辑实测（3→4→3，最多 4 个，homeTools 云同步）
- [x] 首页工具隐藏/排序（homeTools）与恢复

## 2. 通知

- [x] 待处理/资料/已过期三区 + 已过期折叠
- [x] 长期安排（daily/weekly/monthly_day/monthly_weeks、until、24h 期次卡）
- [x] 附件：图片内联 + 全屏预览；URL 文件/链接「打开」
- [x] 标记已处理（跨端 marks）、未处理计数、刷新
- [x] 逐项错峰入场（index*30ms，≤8 项错峰）

## 3. 作业

- [x] 列表/筛选/下拉刷新、详情弹层（全文/来源/附件）
- [x] 完成状态（乐观更新 + 失败补发；实测勾选/取消 + marks 云同步）
- [x] 截止提醒：提前 10/30/60/120 分钟，`reminderAgentManager` + 通知降级 + 本机 id 持久化
- [x] 图片附件预览（data URI）
- [x] 隐藏作业（仅自己不可见，userdata.hide/hwHide 云同步）+ 已隐藏计数与一键恢复
- [x] 隐藏通知（ntHide，按通知条目隐藏、工作台同步排除）+ 恢复

## 4. 课表

- [x] 日视图（日期条、下一节、进行中标记）
- [x] 周视图 7×12 网格、跨节课程块、今天列高亮
- [x] 左右滑动切周（40vp 阈值）+ 切周滑入
- [x] 课程详情（节次/教师/周次/单双周）
- [x] 个人课表优先（`ttUseMine + ttLocal`）/班级课表
- [x] 教务登录：密码 → tt_login_enqueue（p_platform=android）→ 轮询 tt_login_status → 写 userdata.tt（ttUseMine/ttLocal），课表显示「我的课表」；后端实测 32 节课（UI 端到端截图待补）

## 5. 电费

- [x] 楼栋/房间选择、低电阈值
- [x] 24h/7d/30d 趋势 + 触摸游标/气泡
- [x] 同期比较（昨日/上周/上月同期）
- [x] 慢频估算（真实变化点分段 + 异常剔除 + 参考标记）
- [x] 充值/上调金色圆点
- [x] 低电本地通知（同电量 6h 去重）
- [x] 低电阈值修改实测（30→40→30，userdata.power.low 云同步）

## 6. 投票

- [x] 列表/详情、单选多选/匿名实名/可改票/结果可见性/范围/时长
- [x] 指定成员（座号多选，无学号）
- [x] 选项配图（相册 → ≤640 JPEG data URL，客户端校验）
- [x] 编辑（0 票）/延长/结束/删除
- [x] 秒级倒计时 + 15s 静默刷新
- [ ] 带图投票云端 E2E（避免遗留测试数据）

## 7. 演示

- [x] 列表/详情、文件下载（兼容版/PDF/原始）
- [x] 分步图全屏播放（左右点按翻页）
- [x] 原样视频播放（原生控件）
- [x] 单独媒体下载
- [x] 分片上传（512 KiB、排队、进度）
- [x] 上传请求契约单测（POST ppt_decks / ppt_upload_chunks / PATCH queued）
- [x] 演示软删除（本人，二次确认）
- [ ] 上传 E2E（模拟器无 /storage 用户目录，文件选择器不可见外部文件；需真机）
- [x] 视频章节跳转（章节条 + setCurrentTime）
- [x] 视频倍速尝试：AVPlayer + XComponent 可播但模拟器画面全黑 → 已回退原生 Video，倍速仍不可用（SDK VideoController 无 setSpeed）

## 8. 点名 / 抽签 / 分组 / 名单

- [x] 点名：全班/班委/团员、自定义名单、到/假、统计、导出、重置二次确认
- [x] 抽签：配置/候选/结果三步、左右滑动 + 步骤转场、结果 10 个不重复、排序、导出（实测）
- [x] 抽签→分组联动：上一步抽签序号 10 人 → 4 组 3/3/2/2（实测）
- [x] 分组：随机分组、两列组卡、导出（实测 70 人→4 组 18/18/17/17）
- [x] 分组来源提示（无抽签结果时明确引导）
- [x] 名单：成员列表、分类（班委 18/团员 50/全班 70）、搜索（实测「李」5 人）、职位标签

## 9. 诊断 / 打卡 / 体力 / 水费 / 教务

- [x] 诊断：本机 6 项、服务健康 18 项、上报 client_diag（含服务健康、10 分钟指纹限流）
- [x] 打卡/体力/水费：列表、录入、统计
- [x] 水量月份切换/空态/计费规则实测（2026-11 ↔ 2026-10）
- [x] 体测评分实测：总分 78.7 及格、单项权重 15/15/20/10/10… 合计 100%、参数持久化
- [x] 体测历史：回填 / 改名（写回 fitrecs.data.n，云端同步）/ 删除，改名后列表即时刷新
- [x] 教务：课表速览（第 11 周/今日/下一节）+ 4 个入口卡
- [x] 教务入口实测：打开系统浏览器 → 福建中医药大学 SSO 登录页（不登录，红线）
- [ ] 教务原生成绩/考试卡片（登录已通，成绩抓取待扩展）

## 10. 交付

- [x] 未签名 HAP：桌面 `班级工具站-harmony-unsigned.hap`（模拟器可直装）
- [ ] 真机签名（需华为账号自动签名）

## 已知限制汇总

1. 教务原生成绩/考试卡片：登录链路已通，成绩/考试抓取尚未实现。
2. 演示上传、带图投票：功能已实现，云端 E2E 未跑（会写入班级共享数据）。
3. 视频倍速：当前 SDK `VideoController` 无 `setSpeed`。
4. 签名：真机需 DevEco 自动签名（华为账号）。
5. 隐藏工具 UI：userdata.hide 字段存在，App 暂无入口。
6. 视频倍速：VideoController 无 setSpeed，需改 AVPlayer。

## 16. M77 新增能力（2026-11-15，1.0.6）

- [x] 地图：ArkUI Web 加载 ECS H5（campus_final_25d.html?embed=1），顶栏返回 / 刷新 / 浏览器降级，主文档失败错误条（重试 + 浏览器）
- [x] 学信网：默认卡片页 + 后台恢复登录；unJavaScript 只读提取 4 数据卡（学籍/学历/学位/在线验证报告）；10 个官方工具入口；未登录「去登录」→ 官方页手动登录；登录后自动回卡片；18 位身份证/11 位手机号掩码
- [x] 今日校园：12 个学工/门户服务入口 + 本机搜索；Web 打开融合门户（302 → CAS）；unJavaScript 自动填充学号 + 本机教务密码（Asset Store 安全存储）；同一会话只尝试 1 次，验证码/失败回退人工
- [x] 文件传输：临时云空间（ECS drop v2.2）——8 MiB 分片上传任意大小、列表（大小/时间/剩余 72h）、下载并打开、单文件删除、清空；DocumentViewPicker 选择文件；token 只在 X-Device-Id
- [x] 视觉/适配：工具描述两行（卡高 96vp）、浅色底栏无黑影、顶部呼吸区、深色 hero 中性色、平板/折叠屏网格 2→3→4 列、主内容最大宽度 880/960
- [x] 单测 **415/415**（新增 Map/Chsi/TodayCampus/CloudSpace/Breakpoints 共 63 项）；scripts/build.ps1 unsigned HAP **3,808,456 B**（1.0.6）
- [ ] 学信网 / 学校统一身份认证真实登录（红线：不用真实账号，无测试凭据）
- [ ] 地图真机 Web 渲染、文件传输真实 ECS 端到端（建议测试身份手工冒烟后 POST /close 清理）
- [ ] 模拟器/真机逐页 UI 冒烟（本轮未做；需 scripts/smoke_emulator.ps1 + scripts/tool_smoke.ps1）

## 17. 2026-11-16（1.0.7）：删除学信网 / 今日校园工具

用户要求删除「活动 / 今日校园 / 学信网」工具（不是隐藏）。鸿蒙端实际有 `chsi` 学信网、`today` 今日校园两个工具
（「活动」本端从未移植，无入口），本轮已按「删除」处理：

- [x] 删除 `entry/src/main/ets/features/chsi/`（ChsiModels / ChsiExtractLogic / ChsiNavigationLogic）
- [x] 删除 `entry/src/main/ets/data/todaycampus/`（TodayCampusCatalog / TodayCampusSearch / TodayCampusLoginLogic）
- [x] 删除 `entry/src/main/ets/ui/tools/ChsiScreen.ets`、`TodayCampusScreen.ets`
- [x] 删除 `entry/src/test/Chsi.test.ets`、`TodayCampus.test.ets`；`List.test.ets` 移除挂载
- [x] `ToolCatalog.ALL` 18 → **16**（移除 `chsi` / `today`）；`ToolScreen.ets` 移除这两条路由分支
- [x] `Breakpoints.test.ets` 工具数断言 18 → 16，移除 `chsi` / `today` 存在性断言
- [x] `scripts/tool_smoke.ps1` 冒烟工具清单 18 → 16（移除「学信网」「今日校园」）
- [x] 残留文案：`JwCredentialLogic` 的密码存储说明/注释不再提「今日校园」自动填充（教务登录仍需要本机密码，逻辑保留）
- [x] 版本：`AppScope/app.json5` → **1.0.7 (1000007)**；`CloudConfig.APP_VERSION = '1.0.7'`
- [x] 测试 `.\scripts\test.ps1` → **382/382**，Failure 0 / Error 0（删除的 Chsi/TodayCampus 共 33 项，415 − 33 = 382）
- [x] 构建 `.\scripts\build.ps1` → **BUILD SUCCESSFUL**，unsigned HAP **3,790,299 B**（pack.info version 1000007 / 1.0.7；未签名、未发布）
- 说明：`docs/M77_报告_鸿蒙移植_20261115.md`、`docs/PORTING_MATRIX_20261115.md` 是 2026-11-15 的历史快照，按原样保留（其中
  `chsi` / `today` 条目描述的是当时状态，不代表当前工具目录）。