# Smoke-check all 16 tools: from 全部 page, open each tool, assert title text contains its name, close via header back.
$ErrorActionPreference = 'Stop'
$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$Target = '127.0.0.1:5555'
$Tmp = Join-Path $env:TEMP 'ct_smoke2.json'

$tools = @('抽签', '作业', '通知', '课表', '教务', '分组', '体测', '投票', '电费', '演示', '水量', '名单', '点名', '诊断', '地图', '文件传输')

function Dump-Texts {
  Remove-Item $Tmp -ErrorAction SilentlyContinue
  & $Hdc -t $Target shell 'uitest dumpLayout -p /data/local/tmp/ct_smoke2.json' | Out-Null
  & $Hdc -t $Target file recv /data/local/tmp/ct_smoke2.json $Tmp | Out-Null
  $root = Get-Content $Tmp -Raw | ConvertFrom-Json
  $script:texts = @()
  $script:bounds = @{}
  function Walk($n) {
    if ($null -eq $n) { return }
    $b = $n.attributes
    if ($b -and $b.text) {
      $script:texts += $b.text
      if ($b.bounds -and -not $script:bounds.ContainsKey($b.text)) { $script:bounds[$b.text] = $b.bounds }
    }
    if ($n.children) { foreach ($c in $n.children) { Walk $c } }
  }
  Walk $root
}

function Click-Text([string]$text) {
  Dump-Texts
  if (-not $script:bounds.ContainsKey($text)) { return $false }
  $nums = [regex]::Matches($script:bounds[$text], '\d+') | ForEach-Object { [int]$_.Value }
  if ($nums.Count -lt 4) { return $false }
  & $Hdc -t $Target shell ("uitest uiInput click " + [int](($nums[0] + $nums[2]) / 2) + " " + [int](($nums[1] + $nums[3]) / 2)) | Out-Null
  return $true
}

$pass = 0
$fail = @()
$first = $true
foreach ($name in $tools) {
  if (-not $first) {
    & $Hdc -t $Target shell 'uitest uiInput click 104 233' | Out-Null
    Start-Sleep -Milliseconds 700
  }
  $first = $false
  if (-not (Click-Text '全部')) { $fail += "${name}: 无法回到全部"; continue }
  Start-Sleep -Milliseconds 700
  if (-not (Click-Text $name)) {
    $found = $false
    for ($i = 0; $i -lt 3; $i++) {
      & $Hdc -t $Target shell 'uitest uiInput swipe 640 2200 640 600 300' | Out-Null
      Start-Sleep -Milliseconds 600
      if (Click-Text $name) { $found = $true; break }
    }
    if (-not $found) { $fail += "${name}: 未找到入口"; continue }
  }
  Start-Sleep -Seconds 3
  Dump-Texts
  $hit = $false
  foreach ($txt in $script:texts) { if ($txt.Contains($name)) { $hit = $true; break } }
  if ($hit) { $pass += 1 } else { $fail += "${name}: 未渲染" }
  Write-Output ("[" + $name + "] " + ($(if ($hit) { 'OK' } else { 'FAIL' })))
}
& $Hdc -t $Target shell 'uitest uiInput click 104 233' | Out-Null
Write-Output ("PASS=" + $pass + "/" + $tools.Count)
if ($fail.Count -gt 0) { Write-Output ("FAIL: " + ($fail -join '; ')) }
