# 鸿蒙模拟器验收脚本（可复现）
#
# 前置：
#   1. DevEco Studio 的模拟器已启动（Emulator.exe -start "Mate 90 Pro"），
#      `hdc list targets` 能看到 127.0.0.1:5555；
#   2. 已构建：.\scripts\build.ps1
#
# 用法：
#   .\scripts\smoke_emulator.ps1              # 安装 + 启动 + 截一张图
#   .\scripts\smoke_emulator.ps1 -Fresh       # 先卸载再装（清数据，需要重新登录）
#
# 说明：模拟器接受**未签名** HAP（本次实测 bm install 成功），无需华为账号签名。
param(
    [switch]$Fresh,
    [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$Target = '127.0.0.1:5555'
)
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$hap = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not (Test-Path $hap)) {
    throw "未找到 HAP：$hap（先跑 .\scripts\build.ps1）"
}
if (-not (Test-Path $Hdc)) {
    throw "未找到 hdc：$Hdc"
}

$targets = & $Hdc list targets 2>&1
if ($targets -notmatch [regex]::Escape($Target)) {
    throw "模拟器未连接（hdc list targets 没有 $Target）。先在 DevEco 启动 Mate 90 Pro。"
}

if ($Fresh) {
    & $Hdc -t $Target shell 'bm uninstall -n com.furina.classtools' | Out-Null
}

& $Hdc -t $Target file send $hap /data/local/tmp/class-tools.hap | Out-Null
$install = & $Hdc -t $Target shell 'bm install -p /data/local/tmp/class-tools.hap' 2>&1
Write-Host $install
if ($install -notmatch 'successfully') {
    throw '安装失败'
}

& $Hdc -t $Target shell 'aa start -a EntryAbility -b com.furina.classtools' | Out-Null
Start-Sleep -Seconds 3
# 重装后首次 start 偶尔不置前，补一次并把应用拉回前台
& $Hdc -t $Target shell 'aa start -a EntryAbility -b com.furina.classtools' | Out-Null
Start-Sleep -Seconds 5

$artifacts = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
& $Hdc -t $Target shell 'snapshot_display -f /data/local/tmp/smoke.jpeg' | Out-Null
& $Hdc -t $Target file recv /data/local/tmp/smoke.jpeg (Join-Path $artifacts 'smoke.jpeg') | Out-Null
Write-Host ("截图：" + (Join-Path $artifacts 'smoke.jpeg')) -ForegroundColor Green
Write-Host '提示：登录用测试身份 3260799999 / 测试账号（uitest uiInput 可自动化输入）。'
