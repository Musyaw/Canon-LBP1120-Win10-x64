# Установка доступа USB для captwin (Canon LBP-1120)
#
# Windows держит принтер на драйвере usbprint — libusb не может открыть устройство.
# Нужен WinUSB через Zadig (один раз). После этого captwin печатает напрямую по CAPT.
#
# ВАЖНО: пока стоит WinUSB, стандартная очередь печати Windows для этого USB не работает.
# Печать — через captwin.exe (testpage / print) или будущий сервис порта 9100.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Zadig = Join-Path $Root "tools\zadig\zadig.exe"
if (-not (Test-Path $Zadig)) {
    $Zadig = Join-Path $Root "tools\zadig.exe"
}

Write-Host "=== Canon LBP-1120 / captwin — WinUSB ===" -ForegroundColor Cyan
Write-Host @"

Запуск (если PowerShell ругается на политику выполнения):

  powershell -ExecutionPolicy Bypass -File ".\install-winusb.ps1"

Или дважды щёлкните: install-winusb.bat

1. Подключите принтер по USB и включите его.
2. Сейчас откроется Zadig от имени администратора.
3. В Zadig: Options -> List All Devices
4. Выберите: Canon / Laser Shot / 04A9:262B (или 'USB Printing Support')
5. Справа выберите драйвер: WinUSB
6. Нажмите 'Replace Driver' или 'Install Driver'
7. Дождитесь Success, закройте Zadig.

"@

if (-not (Test-Path $Zadig)) {
    Write-Host "Zadig не найден: $Zadig" -ForegroundColor Red
    exit 1
}

Start-Process -FilePath $Zadig -Verb RunAs
Write-Host "После замены драйвера выполните:" -ForegroundColor Green
Write-Host "  .\build.ps1"
Write-Host "  .\build\captwin.exe list"
Write-Host "  .\build\captwin.exe testpage"
