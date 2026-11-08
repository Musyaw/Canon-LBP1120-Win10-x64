#Requires -RunAsAdministrator
<#
  Полная установка: Ghostscript, очередь Windows, ярлыки GUI. WinUSB — в мастере PostInstall-Wizard.ps1 (Zadig).
#>
param(
    [switch]$SkipGhostscript,
    [switch]$SkipWinUsb,
    [string]$InstallDir = "${env:ProgramFiles}\CanonLBP1120Capt"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Split-Path -Parent $ScriptDir
if (-not (Test-Path (Join-Path $Payload "captwin.exe"))) {
    $devRelease = Join-Path (Split-Path $ScriptDir -Parent) "release\Canon-LBP1120-captwin-Win10-x64"
    if (Test-Path (Join-Path $devRelease "captwin.exe")) {
        $Payload = $devRelease
    }
}

$ErrorActionPreference = "Stop"
$PrinterName = "Canon LBP1120 (CAPT)"

Write-Host "`n=== Canon LBP1120 CAPT — установка ===" -ForegroundColor Cyan
Write-Host "Каталог: $InstallDir`n"

New-Item -ItemType Directory -Force -Path $InstallDir, "$InstallDir\data", "$InstallDir\tools", "$InstallDir\installer" | Out-Null

$copyItems = @(
    "captwin.exe", "libwinpthread-1.dll", "README.ru.txt", "LICENSES.txt",
    "install-winusb.ps1", "install-winusb.bat", "print-testpage.bat",
    "Launch-CaptWinServer.vbs", "CaptWin-Server.bat", "CaptWin-Launcher.ps1", "CaptWin-Server-Gui.ps1",
    "Setup-PrinterQueue.bat", "captwin.ico"
)
foreach ($f in $copyItems) {
    $src = Join-Path $Payload $f
    if (-not (Test-Path $src)) { $src = Join-Path $ScriptDir $f }
    if (Test-Path $src) { Copy-Item $src $InstallDir -Force }
}
foreach ($f in @(
        "Install-Ghostscript.ps1", "Install-PrinterQueue.ps1",
        "Fix-PrintQueue.ps1", "Uninstall-CaptWin.ps1", "captwin_winusb.inf",
        "Setup-PrinterQueue.ps1", "Install-WinUsb-Capt.ps1", "Setup-WinUsb.bat",
        "PostInstall-Wizard.ps1", "Setup-Guide.ru.txt", "CaptWin-Logging.ps1"
    )) {
    $src = Join-Path $ScriptDir $f
    if (Test-Path $src) { Copy-Item $src "$InstallDir\installer\" -Force }
}
if (Test-Path (Join-Path $Payload "data\example-1.pbm")) {
    Copy-Item (Join-Path $Payload "data\example-1.pbm") "$InstallDir\data\" -Force
}
$pbmInstalled = Join-Path $InstallDir "data\example-1.pbm"
if (-not (Test-Path -LiteralPath $pbmInstalled)) {
    $pbmSrc = Join-Path $ScriptDir "example-1.pbm"
    if (Test-Path -LiteralPath $pbmSrc) {
        Copy-Item -LiteralPath $pbmSrc -Destination $pbmInstalled -Force
    }
}
if (-not (Test-Path -LiteralPath $pbmInstalled)) {
    Write-Host "ОШИБКА: нет data\example-1.pbm — тестовая страница не будет работать. Переустановите Setup 1.1.22+." -ForegroundColor Red
}
if (Test-Path (Join-Path $Payload "gs\bin\gswin64c.exe")) {
    Copy-Item (Join-Path $Payload "gs") "$InstallDir\gs" -Recurse -Force
}
foreach ($tool in @("zadig.exe", "wdi-simple.exe", "devcon.exe")) {
    $src = Join-Path $Payload "tools\$tool"
    if (Test-Path $src) { Copy-Item $src "$InstallDir\tools\" -Force }
}
if (-not (Test-Path "$InstallDir\tools\zadig.exe")) {
    Write-Host "ОШИБКА: не установлен tools\zadig.exe — переустановите Setup 1.1.20+ или положите zadig.exe в tools." -ForegroundColor Red
}

# Ghostscript (нужен для Ctrl+P)
if (-not $SkipGhostscript) {
    try {
        . (Join-Path $ScriptDir "Install-Ghostscript.ps1")
        if (-not (Install-GhostscriptIfMissing -AppRoot $InstallDir)) {
            Write-Host "Внимание: Ghostscript не найден — пересоберите Setup с third_party\ghostscript или проверьте папку gs." -ForegroundColor Red
        }
    } catch {
        Write-Host "Ghostscript: $_" -ForegroundColor Yellow
    }
}

# Очередь Windows (важно для Ctrl+P)
$printerOk = $false
try {
    Restart-Service Spooler -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    . (Join-Path $InstallDir "installer\Install-PrinterQueue.ps1")
    for ($try = 1; $try -le 5; $try++) {
        if (Install-CaptWinPrinterQueue) {
            $printerOk = $true
            break
        }
        Write-Host "Повтор создания принтера ($try/5)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Host "Принтер Windows: $_" -ForegroundColor Yellow
}
if ($printerOk) {
    Write-Host "Принтер Windows: $PrinterName" -ForegroundColor Green
} else {
    Write-Host "Принтер не создан — запустите installer\Setup-PrinterQueue.bat от администратора" -ForegroundColor Yellow
}

# WinUSB — вручную через Zadig (см. мастер PostInstall-Wizard.ps1)
if (-not $SkipWinUsb) {
    Write-Host "Драйвер USB (WinUSB): после установки откроется мастер — шаг с Zadig (tools\zadig.exe)." -ForegroundColor Cyan
}

# Убираем старый фоновый сервер (теперь GUI)
Unregister-ScheduledTask -TaskName "CanonLBP1120CaptServe" -Confirm:$false -ErrorAction SilentlyContinue
Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Ярлык быстрого запуска на рабочий стол
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "LBP-1120 — быстрый запуск.lnk"
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = Join-Path $InstallDir "CaptWin-Server.bat"
$lnk.WorkingDirectory = $InstallDir
$lnk.Description = "Сервер печати Canon LBP1120 (CAPT) для Ctrl+P"
$iconFile = Join-Path $InstallDir "captwin.ico"
if (Test-Path $iconFile) {
    $lnk.IconLocation = "$iconFile,0"
} elseif (Test-Path $Exe) {
    $lnk.IconLocation = "$Exe,0"
}
$lnk.Save()

# Устаревшее имя ярлыка — убрать дубликат
$oldLnk = Join-Path $desktop "Canon LBP1120 — печать.lnk"
if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force -ErrorAction SilentlyContinue }

$startMenu = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Canon LBP1120 CAPT"
if (Test-Path $startMenu) {
    $lnkSm = $shell.CreateShortcut((Join-Path $startMenu "Быстрый запуск сервера.lnk"))
    $lnkSm.TargetPath = $lnk.TargetPath
    $lnkSm.WorkingDirectory = $InstallDir
    $lnkSm.IconLocation = $lnk.IconLocation
    $lnkSm.Save()
}

Write-Host @"

=== Установка завершена ===
  Запустите ярлык «LBP-1120 — быстрый запуск» на рабочем столе:
  мастер настройки (Zadig, очередь) → окно сервера.

"@ -ForegroundColor Green
