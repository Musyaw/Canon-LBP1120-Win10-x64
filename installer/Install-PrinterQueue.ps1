# Создаёт порт TCP 9100 и очередь Windows для captwin serve.

function Install-CaptWinPrinterQueue {
    param(
        [string]$PrinterName = "Canon LBP1120 (CAPT)",
        [string]$PortName = "CaptWin_127.0.0.1_9100",
        [string]$HostAddr = "127.0.0.1",
        [int]$PortNum = 9100
    )

    $messages = @()
    function Log([string]$m) { $messages += $m; Write-Host $m }

    try {
        $spooler = Get-Service Spooler -ErrorAction Stop
        if ($spooler.Status -ne 'Running') {
            Start-Service Spooler
            Start-Sleep -Seconds 2
        }
    } catch {
        Log "Spooler: $_"
    }

    if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
        try {
            Add-PrinterPort -Name $PortName -PrinterHostAddress $HostAddr -PortNumber $PortNum -ErrorAction Stop
            Log "Порт создан: $PortName"
        } catch {
            Log "Порт: $_"
        }
    }

    if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
        Log "Очередь уже есть: $PrinterName"
        return $true
    }

    $added = $false
    $driverInfs = @(
        @{ Inf = "$env:windir\INF\prnms005.inf"; Driver = "Microsoft PS Class Driver" },
        @{ Inf = "$env:windir\INF\prnge001.inf"; Driver = "MS Publisher Color Printer" }
    )
    foreach ($entry in $driverInfs) {
        if (-not (Test-Path $entry.Inf)) { continue }
        if (-not (Get-PrinterDriver -Name $entry.Driver -ErrorAction SilentlyContinue)) {
            pnputil /add-driver $entry.Inf /install 2>&1 | Out-Null
            Add-PrinterDriver -Name $entry.Driver -InfPath $entry.Inf -ErrorAction SilentlyContinue | Out-Null
        }
        if (Get-PrinterDriver -Name $entry.Driver -ErrorAction SilentlyContinue) {
            try {
                Add-Printer -Name $PrinterName -DriverName $entry.Driver -PortName $PortName -ErrorAction Stop
                $added = $true
                Log "Очередь создана (Add-Printer): $PrinterName"
                break
            } catch {
                Log "Add-Printer ($($entry.Driver)): $_"
            }
        }
    }

    if (-not $added) {
        foreach ($driver in @(
                "Microsoft PS Class Driver",
                "MS Publisher Color Printer",
                "Microsoft Publisher Color Printer"
            )) {
            if (Get-PrinterDriver -Name $driver -ErrorAction SilentlyContinue) {
                try {
                    Add-Printer -Name $PrinterName -DriverName $driver -PortName $PortName -ErrorAction Stop
                    $added = $true
                    Log "Очередь создана: $driver"
                    break
                } catch {
                    Log "Add-Printer ($driver): $_"
                }
            }
        }
    }

    if (-not $added -and (Test-Path "$env:windir\INF\prnms005.inf")) {
        pnputil /add-driver "$env:windir\INF\prnms005.inf" /install 2>&1 | Out-Null
        $printUiArgs = @(
            "/if", "/b", "`"$PrinterName`"",
            "/f", "`"$env:windir\INF\prnms005.inf`"",
            "/r", "`"$PortName`"",
            "/m", "`"Microsoft PS Class Driver`""
        )
        $argLine = "printui.dll,PrintUIEntry " + ($printUiArgs -join " ")
        Start-Process -FilePath "rundll32.exe" -ArgumentList $argLine -Wait -NoNewWindow
        $added = [bool](Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)
        if ($added) { Log "Очередь создана (printui)" } else { Log "printui не создал очередь" }
    }

    if (-not $added) {
        Log ($messages -join "`n")
    }
    return $added
}
