# Fill the Nth text input on screen (0-based), then hide the keyboard.
# Usage: .\scripts\ui_fill.ps1 -Index 0 -Text "178"
param(
    [Parameter(Mandatory = $true)][int]$Index,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$Target = '127.0.0.1:5555'
)
$ErrorActionPreference = 'Stop'
$tmpJson = Join-Path $env:TEMP 'ct_fill_layout.json'

# 先收起键盘，避免布局滚动导致坐标漂移
& $Hdc -t $Target shell 'uitest uiInput keyEvent Back' | Out-Null
Start-Sleep -Milliseconds 500
& $Hdc -t $Target shell 'uitest dumpLayout -p /data/local/tmp/ct_fill.json' | Out-Null
& $Hdc -t $Target file recv /data/local/tmp/ct_fill.json $tmpJson | Out-Null
$root = Get-Content $tmpJson -Raw | ConvertFrom-Json

$script:inputs = @()
function Walk($node) {
    if ($null -eq $node) { return }
    $b = $node.attributes
    if ($b -and $b.type -eq 'TextInput') { $script:inputs += $b }
    if ($node.children) { foreach ($c in $node.children) { Walk $c } }
}
Walk $root

if ($Index -lt 0 -or $Index -ge $script:inputs.Count) {
    throw "屏幕上只有 $($script:inputs.Count) 个输入框，索引 $Index 越界"
}
$bounds = $script:inputs[$Index].bounds
if ($bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
    throw "无法解析 bounds: $bounds"
}
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
& $Hdc -t $Target shell ("uitest uiInput inputText " + $cx + " " + $cy + " " + $Text) | Out-Null
Start-Sleep -Milliseconds 400
& $Hdc -t $Target shell 'uitest uiInput keyEvent Back' | Out-Null
Start-Sleep -Milliseconds 400
Write-Host ("filled #" + $Index + " with '" + $Text + "'")
