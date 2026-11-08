#Requires -RunAsAdministrator
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "Install-PrinterQueue.ps1")
if (Install-CaptWinPrinterQueue) {
    Write-Host "OK: Canon LBP1120 (CAPT)" -ForegroundColor Green
    exit 0
}
Write-Host "Не удалось добавить принтер." -ForegroundColor Red
exit 1
