# Generate brand icon assets (three dots, same as web favicon / mini program / Android BrandMark).
# Usage: .\scripts\gen_icons.ps1   (run with pwsh, not Windows PowerShell 5.1)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$appMedia = Join-Path $root 'AppScope\resources\base\media'
$entryMedia = Join-Path $root 'entry\src\main\resources\base\media'

$teal = [System.Drawing.ColorTranslator]::FromHtml('#4E9082')
$blue = [System.Drawing.ColorTranslator]::FromHtml('#6E8CA8')
$sand = [System.Drawing.ColorTranslator]::FromHtml('#B98F63')
$paper = [System.Drawing.ColorTranslator]::FromHtml('#F2F6F4')

function New-IconBitmap([int]$size) {
    return [System.Drawing.Bitmap]::new($size, $size)
}

function Draw-Dots([System.Drawing.Graphics]$g, [int]$size, [double]$scale) {
    $d = [int]($size * 0.165 * $scale)
    $gap = [int]($size * 0.04 * $scale)
    $total = $d * 3 + $gap * 2
    $x = [int](($size - $total) / 2)
    $y = [int](($size - $d) / 2)
    $colors = @($teal, $blue, $sand)
    for ($i = 0; $i -lt 3; $i++) {
        $brush = [System.Drawing.SolidBrush]::new($colors[$i])
        $g.FillEllipse($brush, $x + $i * ($d + $gap), $y, $d, $d)
        $brush.Dispose()
    }
}

# 1) layered icon background: full-bleed light color
$bmp = New-IconBitmap 1024
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear($paper)
$g.Dispose()
$bmp.Save((Join-Path $appMedia 'background.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# 2) layered icon foreground: transparent + centered dots (content ~58% width, inside safe area)
$bmp = New-IconBitmap 1024
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
Draw-Dots $g 1024 1.0
$g.Dispose()
$bmp.Save((Join-Path $appMedia 'foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# 3) startWindowIcon (152, white + dots)
$bmp = New-IconBitmap 152
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::White)
Draw-Dots $g 152 0.8
$g.Dispose()
$bmp.Save((Join-Path $entryMedia 'startIcon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# 4) app_icon (1024, white + dots)
$bmp = New-IconBitmap 1024
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::White)
Draw-Dots $g 1024 0.85
$g.Dispose()
$bmp.Save((Join-Path $appMedia 'app_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host 'icons written'
Get-ChildItem $appMedia -Filter *.png | Select-Object Name, Length | Format-Table -AutoSize
Get-ChildItem $entryMedia -Filter startIcon.png | Select-Object Name, Length | Format-Table -AutoSize
