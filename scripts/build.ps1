# 鸿蒙工程构建脚本（等价于 DevEco 的 assembleHap，不需要打开 IDE）
#
# 用法：
#   .\scripts\build.ps1                 # 默认 assembleHap（未签名）
#   .\scripts\build.ps1 -Task clean     # 清理
#   .\scripts\build.ps1 -Signed         # 需要 DevEco 已配置自动签名（build-profile.json5 里有 signingConfigs）
param(
    [string]$Task = 'assembleHap',
    [switch]$Signed
)
$ErrorActionPreference = 'Stop'

$deveco = 'C:\Program Files\Huawei\DevEco Studio'
if (-not (Test-Path $deveco)) {
    throw "未找到 DevEco Studio：$deveco"
}
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$hvigorw = Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat'
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    $args = @('--mode', 'module', '-p', 'product=default', $Task, '--no-daemon')
    if ($Signed) {
        $args = @('--mode', 'project', '-p', 'product=default', $Task, '--no-daemon')
    }
    & $hvigorw @args
    if ($LASTEXITCODE -ne 0) {
        throw "构建失败（exit $LASTEXITCODE）"
    }
    Get-ChildItem 'entry\build\default\outputs\default' -Filter *.hap -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host ("HAP: {0}  {1} B" -f $_.Name, $_.Length) -ForegroundColor Green }
} finally {
    Pop-Location
}
