# Добавляет принтер Windows -> captwin serve (127.0.0.1:9100)
# Запуск от администратора. WinUSB + Ghostscript должны быть уже настроены.

$ErrorActionPreference = "Stop"
$PrinterName = "Canon LBP1120 (CAPT)"
$PortName = "CaptWin_127.0.0.1_9100"
$HostAddr = "127.0.0.1"
$PortNum = 9100

Write-Host "=== System printer for Ctrl+P ===" -ForegroundColor Cyan

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

$existing = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Printer already exists: $PrinterName"
} else {
    $port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $port) {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $HostAddr -PortNumber $PortNum
        Write-Host "Added port $PortName"
    }

    $driver = Get-PrinterDriver -Name "Microsoft PS Class Driver" -ErrorAction SilentlyContinue
    if (-not $driver) {
        Write-Host "Microsoft PS Class Driver not found. Add printer manually:" -ForegroundColor Yellow
        Write-Host "  Settings -> Printers -> Add -> IP $HostAddr port $PortNum"
        Write-Host "  Driver: Microsoft PS Class Driver / Publisher Color Printer"
        exit 1
    }

    Add-Printer -Name $PrinterName -DriverName "Microsoft PS Class Driver" -PortName $PortName
    Write-Host "Added printer: $PrinterName"
}

Write-Host @"

Next steps:
1. Start server (leave window open): start-print-server.bat
2. In browser: Ctrl+P -> printer "$PrinterName" -> Print
3. Install Ghostscript if serve says it is missing:
   https://ghostscript.com/releases/gsdnld.html

"@ -ForegroundColor Green
