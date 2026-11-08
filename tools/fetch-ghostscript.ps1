# Скачивает Ghostscript x64 и распаковывает 7-Zip (без запуска gs*.exe) в third_party\ghostscript\
$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
$OutRoot = Join-Path $Root "third_party\ghostscript"
$Cache = Join-Path $Root "tools\cache"

$7z = @(
    "${env:ProgramFiles}\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $7z) {
    throw "Нужен 7-Zip (7z.exe). Установите: winget install 7zip.7zip"
}

New-Item -ItemType Directory -Force -Path $Cache | Out-Null

if (Test-Path (Join-Path $OutRoot "bin\gswin64c.exe")) {
    Write-Host "Уже есть: $OutRoot\bin\gswin64c.exe" -ForegroundColor Green
    exit 0
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Релиз Ghostscript (GitHub)..." -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest" `
    -Headers @{ "User-Agent" = "CanonLBP1120Capt" }
$asset = $release.assets | Where-Object { $_.name -match '^gs\d+w64\.exe$' } | Select-Object -First 1
if (-not $asset) { throw "Не найден gs*w64.exe в релизе" }

$installer = Join-Path $Cache $asset.name
if (-not (Test-Path $installer)) {
    Write-Host "Скачивание $($asset.name)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing
}

$stage = Join-Path $env:TEMP ("gs-7z-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Write-Host "Распаковка 7-Zip (без установщика Ghostscript)..." -ForegroundColor Yellow
& $7z x $installer "-o$stage" -y | Out-Null

$gsExe = Join-Path $stage "bin\gswin64c.exe"
$libDir = Join-Path $stage "lib"
if (-not (Test-Path $gsExe)) {
    $gsExe = (Get-ChildItem -Path $stage -Recurse -Filter "gswin64c.exe" | Select-Object -First 1).FullName
}
if (-not $gsExe -or -not (Test-Path $gsExe)) { throw "gswin64c.exe not found after 7-Zip extract" }
if (-not (Test-Path $libDir)) {
    $libDir = (Get-Item $gsExe).Directory.Parent.FullName + "\lib"
}
if (-not (Test-Path $libDir)) { throw "lib folder not found" }

if (Test-Path $OutRoot) { Remove-Item $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $OutRoot "bin"), (Join-Path $OutRoot "lib") | Out-Null
Copy-Item (Join-Path (Split-Path $gsExe -Parent) "*") (Join-Path $OutRoot "bin") -Force
Copy-Item (Join-Path $libDir "*") (Join-Path $OutRoot "lib") -Recurse -Force

@(
    "Bundled for Canon LBP1120 CAPT Setup (no separate GS installer)."
    "Extracted from $($asset.name) via 7-Zip."
    "License: GPL — https://www.ghostscript.com/"
) | Set-Content -Path (Join-Path $OutRoot "VERSION.txt") -Encoding UTF8

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Готово: $OutRoot" -ForegroundColor Green
