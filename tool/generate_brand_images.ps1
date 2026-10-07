# Generates Android splash + launcher icon PNGs from assets/images/logo.jpg.
# Run from the repo root:  pwsh -File tool/generate_brand_images.ps1
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = Join-Path (Get-Location) 'assets\images\logo.jpg'
if (-not (Test-Path $src)) { throw "logo not found: $src" }

$icon = [System.Drawing.Image]::FromFile($src)
function Save-Clipboardless($bmp, $path) {
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

function New-CircleImage([int]$px) {
  $bmp = New-Object System.Drawing.Bitmap($px, $px)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
  $clip.AddEllipse(0, 0, $px - 1, $px - 1)
  $g.SetClip($clip)
  $g.DrawImage($icon, 0, 0, $px, $px)
  $g.Dispose()
  return $bmp
}

function New-RoundedImage([int]$px, [double]$frac) {
  $bmp = New-Object System.Drawing.Bitmap($px, $px)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $r = [int]($px * $frac)
  $d = $r * 2
  $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
  $clip.AddArc(0, 0, $d, $d, 180, 90)
  $clip.AddArc($px - $d, 0, $d, $d, 270, 90)
  $clip.AddArc($px - $d, $px - $d, $d, $d, 0, 90)
  $clip.AddArc(0, $px - $d, $d, $d, 90, 90)
  $clip.CloseFigure()
  $g.SetClip($clip)
  $g.DrawImage($icon, 0, 0, $px, $px)
  $g.Dispose()
  return $bmp
}

# Logo square centered on a transparent canvas (logo circle-cropped so the
# photo's dark corners never show inside the adaptive-icon mask).
function New-AdaptiveForeground([int]$canvas, [double]$logoFrac) {
  $bmp = New-Object System.Drawing.Bitmap($canvas, $canvas)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $lp = [int]($canvas * $logoFrac)
  $off = [int](($canvas - $lp) / 2)
  $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
  $clip.AddEllipse($off, $off, $lp - 1, $lp - 1)
  $g.SetClip($clip)
  $g.DrawImage($icon, $off, $off, $lp, $lp)
  $g.Dispose()
  return $bmp
}

# Density buckets: mdpi 1.0, hdpi 1.5, xhdpi 2.0, xxhdpi 3.0, xxxhdpi 4.0
$densities = @(
  @{ name = 'mdpi';    scale = 1.0 },
  @{ name = 'hdpi';    scale = 1.5 },
  @{ name = 'xhdpi';   scale = 2.0 },
  @{ name = 'xxhdpi';  scale = 3.0 },
  @{ name = 'xxxhdpi'; scale = 4.0 }
)

foreach ($d in $densities) {
  $s = [double]$d.scale
  # Splash: ~130dp circular logo, centered on a dark window background.
  $splashPx = [int](130 * $s)
  $splashPath = "android\app\src\main\res\drawable-$($d.name)\splash_logo.png"
  Save-Clipboardless (New-CircleImage $splashPx) $splashPath

  # Legacy launcher icon: rounded square (20% radius).
  $iconPx = [int](48 * $s)
  $iconPath = "android\app\src\main\res\mipmap-$($d.name)\ic_launcher.png"
  Save-Clipboardless (New-RoundedImage $iconPx 0.20) $iconPath

  # Adaptive-icon foreground: 108dp canvas, logo circle-cropped at 78%.
  $fgPx = [int](108 * $s)
  $fgPath = "android\app\src\main\res\mipmap-$($d.name)\ic_launcher_foreground.png"
  Save-Clipboardless (New-AdaptiveForeground $fgPx 0.78) $fgPath
}

$icon.Dispose()
Write-Host 'Generated splash_logo.png + ic_launcher.png + ic_launcher_foreground.png for all densities.'
