# Удаляет очередь, порт и фоновые задачи (файлы программы снимает Inno Setup).

param(
    [string]$PrinterName = "Canon LBP1120 (CAPT)",
    [string]$PortName = "CaptWin_127.0.0.1_9100"
)

Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName "CanonLBP1120CaptServe" -Confirm:$false -ErrorAction SilentlyContinue

$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($printer) {
    Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
}

$port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if ($port) {
    Remove-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
}
