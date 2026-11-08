#Requires -RunAsAdministrator
# Починка очереди + Ghostscript (если установка прошла не полностью)

$InstallDir = "C:\Program Files\CanonLBP1120Capt"
if (-not (Test-Path "$InstallDir\captwin.exe")) {
    $InstallDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    if (-not (Test-Path "$InstallDir\captwin.exe")) {
        $InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "=== Настройка печати LBP-1120 ===" -ForegroundColor Cyan

if (Test-Path (Join-Path $scriptDir "Install-Ghostscript.ps1")) {
    . (Join-Path $scriptDir "Install-Ghostscript.ps1")
    Install-GhostscriptIfMissing | Out-Null
}

. (Join-Path $scriptDir "Install-PrinterQueue.ps1")
if (Install-CaptWinPrinterQueue) {
    Write-Host "Очередь принтера настроена." -ForegroundColor Green
} else {
    Write-Host "Очередь не создана — см. README." -ForegroundColor Yellow
}

Write-Host "`nЗапустите Launch-CaptWinServer.vbs или ярлык «Canon LBP1120 — печать»." -ForegroundColor Cyan
pause
