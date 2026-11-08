#Requires -RunAsAdministrator
# Перевод Canon LBP-1120 (04A9:262B) на WinUSB для captwin (без Zadig, если возможно).

function Test-CaptWinUsbPrint {
    param([string]$InstallDir)
    $exe = Join-Path $InstallDir "captwin.exe"
    if (-not (Test-Path $exe)) { return $false }
    Push-Location $InstallDir
    & $exe testpage 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    Pop-Location
    return $ok
}

function Invoke-UpdateDriverForHwId {
    param(
        [string]$InfPath,
        [string]$HardwareId
    )
    if (-not (Test-Path $InfPath)) { return $false }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CaptWinSetupApi {
    [DllImport("newdev.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool UpdateDriverForPlugAndPlayDevices(
        IntPtr hwndParent,
        string HardwareId,
        string FullInfPath,
        uint InstallFlags,
        out bool bRebootRequired);
}
"@ -ErrorAction SilentlyContinue

    $reboot = $false
    # INSTALLFLAG_FORCE | INSTALLFLAG_NONINTERACTIVE
    $flags = [uint32]5
    $fullInf = (Resolve-Path $InfPath).Path
    $ok = [CaptWinSetupApi]::UpdateDriverForPlugAndPlayDevices(
        [IntPtr]::Zero, $HardwareId, $fullInf, $flags, [ref]$reboot)
    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "UpdateDriver($HardwareId): Win32=$err" -ForegroundColor Yellow
    }
    return $ok
}

function Install-WinUsbForCapt {
    param([string]$InstallDir)

    if (Test-CaptWinUsbPrint -InstallDir $InstallDir) {
        Write-Host "USB / WinUSB: captwin уже печатает (testpage OK)." -ForegroundColor Green
        return $true
    }

    $infSrc = Join-Path $InstallDir "installer\captwin_winusb.inf"
    if (-not (Test-Path $infSrc)) {
        Write-Host "Не найден: $infSrc" -ForegroundColor Red
        return $false
    }

    $stageInf = Join-Path $env:TEMP "captwin_winusb.inf"
    Copy-Item $infSrc $stageInf -Force

    $wdi = Join-Path $InstallDir "tools\wdi-simple.exe"
    if (Test-Path $wdi) {
        Write-Host "WinUSB: wdi-simple (libwdi)..." -ForegroundColor Yellow
        $wdiArgs = @(
            '-t', '0',
            '-n', 'Canon LBP1120 CAPT USB',
            '-m', 'CAPT LBP1120 Community',
            '-v', '0x04A9',
            '-p', '0x262B',
            '-s',
            '--stealth-cert',
            '-o', '120000'
        )
        & $wdi @wdiArgs 2>&1 | ForEach-Object { Write-Host $_ }
        Start-Sleep -Seconds 3
        if (Test-CaptWinUsbPrint -InstallDir $InstallDir) {
            Write-Host "USB / WinUSB: OK (wdi-simple)." -ForegroundColor Green
            return $true
        }
    } else {
        Write-Host "tools\wdi-simple.exe не найден — упакуйте в Setup." -ForegroundColor Yellow
    }

    Write-Host "WinUSB: pnputil + UpdateDriver..." -ForegroundColor Yellow
    pnputil /add-driver $stageInf /install 2>&1 | ForEach-Object { Write-Host $_ }

    $hwIds = @(
        "USB\VID_04A9&PID_262B",
        "USB\VID_04A9&PID_262B&MI_00"
    )

    foreach ($hw in $hwIds) {
        if (Invoke-UpdateDriverForHwId -InfPath $stageInf -HardwareId $hw) {
            Write-Host "UpdateDriver OK: $hw" -ForegroundColor Green
        }
    }

    $dev = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -match 'VID_04A9&PID_262B'
    } | Select-Object -First 1

    if ($dev) {
        Write-Host "Перезапуск USB-устройства: $($dev.InstanceId)" -ForegroundColor Yellow
        Stop-Service Spooler -Force -ErrorAction SilentlyContinue
        pnputil /disable-device $dev.InstanceId 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        pnputil /enable-device $dev.InstanceId 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        pnputil /restart-device $dev.InstanceId 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Start-Service Spooler -ErrorAction SilentlyContinue

        foreach ($hw in $hwIds) {
            [void](Invoke-UpdateDriverForHwId -InfPath $stageInf -HardwareId $hw)
        }
    }

    Start-Sleep -Seconds 2
    if (Test-CaptWinUsbPrint -InstallDir $InstallDir) {
        Write-Host "USB / WinUSB: OK после UpdateDriver." -ForegroundColor Green
        return $true
    }

    $devcon = Join-Path $InstallDir "tools\devcon.exe"
    if (-not (Test-Path $devcon)) {
        $devcon = Join-Path (Split-Path $InstallDir -Parent) "tools\devcon.exe"
    }
    if (Test-Path $devcon) {
        Write-Host "WinUSB: devcon update..." -ForegroundColor Yellow
        & $devcon update $stageInf "USB\VID_04A9&PID_262B" 2>&1 | ForEach-Object { Write-Host $_ }
        Start-Sleep -Seconds 3
        & $devcon restart "*VID_04A9&PID_262B*" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        if (Test-CaptWinUsbPrint -InstallDir $InstallDir) {
            Write-Host "USB / WinUSB: OK (devcon)." -ForegroundColor Green
            return $true
        }
    }

    Write-Host "Повтор: снятие usbprint и повторная установка..." -ForegroundColor Yellow
    if ($dev) {
        pnputil /remove-device $dev.InstanceId 2>&1 | Out-Null
        Start-Sleep -Seconds 4
        pnputil /add-driver $stageInf /install 2>&1 | Out-Null
        pnputil /scan-devices 2>&1 | Out-Null
        Start-Sleep -Seconds 4
        foreach ($hw in $hwIds) {
            [void](Invoke-UpdateDriverForHwId -InfPath $stageInf -HardwareId $hw)
        }
    }

    Start-Sleep -Seconds 2
    if (Test-CaptWinUsbPrint -InstallDir $InstallDir) {
        Write-Host "USB / WinUSB: OK после повторной установки." -ForegroundColor Green
        return $true
    }

    Write-Host @"
WinUSB автоматически не применился.
Подключите принтер по USB, затем запустите: $InstallDir\installer\Setup-WinUsb.bat
"@ -ForegroundColor Red
    return $false
}

if ($MyInvocation.InvocationName -ne '.') {
    $dir = if ($args[0]) { $args[0] } else {
        if ($PSScriptRoot -match 'installer$') { Split-Path $PSScriptRoot -Parent } else { $PSScriptRoot }
    }
    if (-not (Install-WinUsbForCapt -InstallDir $dir)) { exit 1 }
}
