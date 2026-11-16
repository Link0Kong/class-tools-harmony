# Tap an on-screen element by its text (uses hdc uitest dumpLayout + uiInput click).
# Usage:
#   .\scripts\ui_tap.ps1 -Text "分组"
#   .\scripts\ui_tap.ps1 -Text "班级名单" -Contains
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [switch]$Contains,
    [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$Target = '127.0.0.1:5555'
)
$ErrorActionPreference = 'Stop'
$tmpJson = Join-Path $env:TEMP 'ct_layout.json'

& $Hdc -t $Target shell 'uitest dumpLayout -p /data/local/tmp/ct_layout.json' | Out-Null
& $Hdc -t $Target file recv /data/local/tmp/ct_layout.json $tmpJson | Out-Null
$root = Get-Content $tmpJson -Raw | ConvertFrom-Json

$script:found = $null
function Walk($node) {
    if ($null -eq $node -or $script:found) { return }
    $b = $node.attributes
    if ($b -and $b.text) {
        $hit = if ($Contains) { $b.text.Contains($Text) } else { $b.text -eq $Text }
        if ($hit) { $script:found = $b; return }
    }
    if ($node.children) { foreach ($c in $node.children) { Walk $c } }
}
Walk $root

if (-not $script:found) {
    throw "未找到文本为 '$Text' 的控件"
}
$bounds = $script:found.bounds
if ($bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
    throw "无法解析 bounds: $bounds"
}
$x1 = [int]$Matches[1]; $y1 = [int]$Matches[2]; $x2 = [int]$Matches[3]; $y2 = [int]$Matches[4]
$cx = [int](($x1 + $x2) / 2); $cy = [int](($y1 + $y2) / 2)
& $Hdc -t $Target shell "uitest uiInput click $cx $cy" | Out-Null
Write-Host ("tapped '" + $Text + "' at " + $cx + "," + $cy)
