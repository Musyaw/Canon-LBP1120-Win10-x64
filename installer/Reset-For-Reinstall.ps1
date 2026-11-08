#Requires -RunAsAdministrator
<#
  Полная очистка: CAPT, очередь, USB-драйверы, Ghostscript.
  После — установка Canon-LBP1120-CAPT-Setup.exe «с нуля».
#>
param(
    [string]$PrinterName = "Canon LBP1120 (CAPT)",
    [string]$PortName = "CaptWin_127.0.0.1_9100",
    [string]$InstallDir = "${env:ProgramFiles}\CanonLBP1120Capt",
    [switch]$KeepGhostscript
)

$ErrorActionPreference = "Continue"
Write-Host "`n=== Полный сброс Canon LBP1120 CAPT ===" -ForegroundColor Cyan

Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$uninst = Join-Path $InstallDir "unins000.exe"
if (Test-Path $uninst) {
    Write-Host "Удаление программы Canon LBP1120 CAPT..." -ForegroundColor Yellow
    & $uninst /SILENT /NORESTART
    Start-Sleep -Seconds 4
}

$cleanScript = Join-Path $InstallDir "installer\Uninstall-CaptWin.ps1"
if (Test-Path $cleanScript) {
    & $cleanScript -PrinterName $PrinterName -PortName $PortName
} else {
    $devScript = Join-Path $PSScriptRoot "Uninstall-CaptWin.ps1"
    if (-not (Test-Path $devScript)) {
        $devScript = Join-Path (Split-Path $PSScriptRoot -Parent) "installer\Uninstall-CaptWin.ps1"
    }
    if (Test-Path $devScript) { & $devScript -PrinterName $PrinterName -PortName $PortName }
}

foreach ($name in @($PrinterName, "Canon LBP1120", "Canon Laser Shot LBP-1120")) {
    if (Get-Printer -Name $name -ErrorAction SilentlyContinue) {
        Write-Host "Удаление очереди: $name" -ForegroundColor Yellow
        Remove-Printer -Name $name -ErrorAction SilentlyContinue
    }
}

if (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) {
    Write-Host "Удаление порта: $PortName" -ForegroundColor Yellow
    Remove-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
}

$enum = pnputil /enum-drivers 2>&1 | Out-String
$toDelete = [System.Collections.Generic.List[string]]::new()
foreach ($block in ($enum -split '(?=Published Name:)')) {
    if ($block -match 'Published Name:\s+(\S+\.inf)' -and
        ($block -match 'canon_capt_usb|captwin_winusb|CAPT LBP1120 Community|VID_04A9&PID_262B')) {
        [void]$toDelete.Add($Matches[1])
    }
}
foreach ($oem in ($toDelete | Select-Object -Unique)) {
    Write-Host "Удаление USB-драйвера: $oem" -ForegroundColor Yellow
    pnputil /delete-driver $oem /uninstall /force 2>&1 | Out-String | Write-Host
}

if (-not $KeepGhostscript) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        foreach ($id in @("ArtifexSoftware.GhostScript", "GPL.Ghostscript", "ArtifexSoftware.GPLGhostscript")) {
            winget uninstall -e --id $id --accept-source-agreements 2>&1 | Out-String | Write-Host
        }
    }

    $gsKeys = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Ghostscript|Artifex.*Ghost' }

    foreach ($entry in $gsKeys) {
        Write-Host "Удаление: $($entry.DisplayName)" -ForegroundColor Yellow
        $cmd = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
        if ($cmd) {
            if ($cmd -match '^"(.+?)"\s*(.*)$') {
                $exe = $Matches[1]
                $args = $Matches[2]
                if ($exe -match 'uninstgs\.exe' -and $args -notmatch '/S') { $args = "/S $args" }
                Start-Process -FilePath $exe -ArgumentList $args.Trim() -Wait -NoNewWindow -ErrorAction SilentlyContinue
            } else {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($root in @("${env:ProgramFiles}\gs", "${env:ProgramFiles(x86)}\gs")) {
        if (Test-Path $root) {
            Write-Host "Удаление папки: $root" -ForegroundColor Yellow
            Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $gsCmd = Get-Command gswin64c.exe -ErrorAction SilentlyContinue
    if ($gsCmd) {
        Write-Host "Внимание: gswin64c всё ещё в PATH: $($gsCmd.Source)" -ForegroundColor Red
    } else {
        Write-Host "Ghostscript удалён (gswin64c не найден)." -ForegroundColor Green
    }
}

if (Test-Path $InstallDir) {
    Write-Host "Удаление остатков: $InstallDir" -ForegroundColor Yellow
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

$desktop = [Environment]::GetFolderPath("Desktop")
foreach ($lnk in @(
        "LBP-1120 — быстрый запуск.lnk",
        "Canon LBP1120 — печать.lnk"
    )) {
    $p = Join-Path $desktop $lnk
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}

$startMenu = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Canon LBP1120 CAPT"
if (Test-Path $startMenu) {
    Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue
}

$portable = Join-Path $env:USERPROFILE "Desktop\all\Canon-LBP1120-captwin-Win10-x64"
if (Test-Path $portable) {
    Write-Host "Портативная копия не трогаем: $portable" -ForegroundColor DarkGray
}

Write-Host @"

=== Готово к чистой установке ===
  1. Отключите USB принтера на 10 сек, подключите снова.
  2. Запустите: C:\Users\DELL\Desktop\all\Canon-LBP1120-CAPT-Setup.exe (v1.1.5, ~20 МБ)
  3. Дождитесь конца установки — Ghostscript уже внутри Setup (папка gs\).
  4. Ярлык «LBP-1120 — быстрый запуск» на рабочем столе.

"@ -ForegroundColor Green
