# 更新日志

## 2026-11-23

- Web 域名 `tool.furina.fun` 的 ICP 备案通过（备案号 闽ICP备2026042939号-2），鸿蒙端从备案期的 ECS 明文 IP 临时入口切回正式 HTTPS 域名 `https://tool.furina.fun`：
  - 文件传输 / 云空间 `CloudSpaceDefaults.BASE_URL` → `https://tool.furina.fun/drop`；
  - 校园地图 `MapConfig.ECS_BASE` → `https://tool.furina.fun`（数据源仍为 `/map/campus_final_25d.html?embed=1`；导航 allowlist 的 host 改由该基址推导，避免两处漂移）；
  - 在线法律文本 → `https://tool.furina.fun/legal/harmony/{terms,privacy}.html`。
- `network_config.json`：`base-config` 关闭明文（全站 https），仅保留教务系统 `210.34.74.77` 的明文放行；移除 `121.196.47.2` 的放行。原 ECS IP 入口只保留本机调试，不进客户端常量。
- 单测同步更新（`CloudSpace.test`、`Map.test`）：断言改为新域名与新 host。
- 应用内不展示「备案信息」行（用户要求）；设置/关于页确认无该占位。

## 2026-11-22

- 抽签与分组改为两个完全独立的工具：抽签结果页不再提供「去分组」入口，分组也不再依赖从抽签页跳转。
- 新增「最近抽签」本机持久化（按账号隔离，跨进程重启可用）：每次抽签成功（含重抽、剔除补抽、排序）保存序号、名称、候选池与参数快照；重置只清本轮结果，不删本机快照。
- 分组页成员来源改为「全班 / 最近抽签 / 手动选择」：显示人数与抽签时间，无结果时置灰并提示；结果摘要为「共 N 人 · M 组 · 每组 x–y 人」，新增复制，保留重新分组与导出图片。
- 抽签页保留配置/候选/结果三步与导出、剔除重抽、排序、名单姓名；不再向分组页传参。
