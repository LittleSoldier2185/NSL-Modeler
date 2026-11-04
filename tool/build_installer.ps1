<#
.SYNOPSIS
  สร้างตัวติดตั้ง NSL Modeler (build\installer\NSL-Modeler-Setup-<รุ่น>.exe)

.DESCRIPTION
  1) flutter build windows --release (ข้ามได้ด้วย -SkipBuild ถ้า build ไว้แล้ว)
  2) คอมไพล์ installer\nsl_modeler.iss ด้วย Inno Setup (ISCC.exe) — ต้องติดตั้ง Inno Setup 6 ก่อน
     (https://jrsoftware.org/isdl.php หรือ winget install JRSoftware.InnoSetup)
  เลขรุ่นอ่านจาก pubspec.yaml

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
#>
param(
  [switch]$SkipBuild,
  [string]$Iscc
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$m = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
if (-not $m) { throw 'อ่านเลขรุ่นจาก pubspec.yaml ไม่ได้' }
$version = $m.Matches[0].Groups[1].Value

if (-not $SkipBuild) {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows ล้มเหลว' }
}
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'nsl_modeler.exe'))) {
  throw "ไม่พบ $release\nsl_modeler.exe — build ก่อน (ไม่ใส่ -SkipBuild)"
}

if (-not $Iscc) {
  $candidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }),
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  $Iscc = $candidates | Select-Object -First 1
}
if (-not $Iscc) {
  throw 'ไม่พบ Inno Setup (ISCC.exe) — ติดตั้งด้วย: winget install JRSoftware.InnoSetup แล้วรันใหม่ หรือระบุ -Iscc <path>'
}

& $Iscc "/DAppVersion=$version" 'installer\nsl_modeler.iss'
if ($LASTEXITCODE -ne 0) { throw 'คอมไพล์ตัวติดตั้งล้มเหลว' }
Write-Host "สร้างแล้ว: build\installer\NSL-Modeler-Setup-$version.exe"
