# 生成鸿蒙本地单测用的同步契约 fixture（来源：手机端测试仓的 _sync_fixtures/）
# 用法：powershell -File scripts\gen_sync_fixtures.ps1 [-Src <fixtures 目录>]
# 注意：提交前确认 fixture 已脱敏（真实姓名 / 教师名 / 宿舍号一律改为虚构值）。
param([string]$Src = '')
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $Src) {
    $Src = if ($env:MP_FIXTURES_DIR) { $env:MP_FIXTURES_DIR } else {
        Join-Path (Split-Path -Parent $root) 'mp-class-tools\tests\_sync_fixtures'
    }
}
if (-not (Test-Path $Src)) {
    throw "未找到 fixtures 目录：$Src（用 -Src 或 MP_FIXTURES_DIR 指定）"
}
$out = Join-Path $root 'entry\src\test\fixtures\SyncFixtures.ets'

function Esc([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($code -eq 10) { [void]$sb.Append('\n') }
        elseif ($code -eq 13) { [void]$sb.Append('\r') }
        elseif ($code -eq 9) { [void]$sb.Append('\t') }
        elseif ($code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
        else { [void]$sb.Append($ch) }
    }
    return '"' + $sb.ToString() + '"'
}

$names = @(
    @('USERDATA_V6_WEB', 'userdata_v6_web.json'),
    @('USERDATA_V6_MP', 'userdata_v6_mp.json'),
    @('EXPECTED_MERGE_WEB_MP', 'expected_merge_web_mp.json'),
    @('EXPECTED_MERGE_MP_WEB', 'expected_merge_mp_web.json'),
    @('LEGACY_V5', 'legacy_v5.json'),
    @('EXPECTED_V5_MIGRATE', 'expected_v5_migrate.json')
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('/**')
[void]$sb.AppendLine(' * 同步契约 fixture（来源：mp-class-tools-tests/_sync_fixtures/，oracle = merge_ref.js）。')
[void]$sb.AppendLine(' * 本文件由 scripts/gen_sync_fixtures.ps1 生成，请勿手改。')
[void]$sb.AppendLine(' */')
[void]$sb.AppendLine('')
foreach ($n in $names) {
    $raw = [System.IO.File]::ReadAllText((Join-Path $Src $n[1]))
    [void]$sb.AppendLine("export const $($n[0]): string = $(Esc $raw);")
    [void]$sb.AppendLine('')
}
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("fixtures -> " + $out + "  " + (Get-Item $out).Length + " B")
