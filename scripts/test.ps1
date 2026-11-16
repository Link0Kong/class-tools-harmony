# 鸿蒙本地单元测试（无需设备/模拟器）
#
# 用法：.\scripts\test.ps1
# 结果：entry\.test\default\intermediates\test\coverage_data\test_result.txt
# 退出码：0 = 全绿；1 = 有失败或编译错误
$ErrorActionPreference = 'Stop'

$deveco = 'C:\Program Files\Huawei\DevEco Studio'
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$hvigorw = Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat'
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    & $hvigorw --mode module -p product=default -p module=entry@default test --no-daemon
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'TEST BUILD FAILED' -ForegroundColor Red
        exit 1
    }
    $resultFile = 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
    if (-not (Test-Path $resultFile)) {
        Write-Host "未找到测试结果文件：$resultFile" -ForegroundColor Red
        exit 1
    }
    $summary = (Get-Content $resultFile | Where-Object { $_ -match '^Tests run:' } | Select-Object -Last 1)
    if (-not $summary) {
        Write-Host '测试结果文件缺少汇总行' -ForegroundColor Red
        exit 1
    }
    $failed = Get-Content $resultFile | Select-String -Pattern '^result=(Failure|Error)' -Quiet
    Write-Host $summary -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
    if ($failed) { exit 1 }
} finally {
    Pop-Location
}
