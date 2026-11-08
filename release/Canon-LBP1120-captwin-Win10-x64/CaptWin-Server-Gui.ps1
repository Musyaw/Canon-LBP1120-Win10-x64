# Окно сервера печати Canon LBP-1120 (CAPT). Запуск: CaptWin-Server.bat
param(
    [string]$InstallDir = ""
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$logScript = Join-Path $InstallDir "installer\CaptWin-Logging.ps1"
if (Test-Path -LiteralPath $logScript) { . $logScript; Initialize-CaptWinLog -InstallDir $InstallDir -Source "ServerGUI" }

$Exe = Join-Path $InstallDir "captwin.exe"
$PrinterName = "Canon LBP1120 (CAPT)"
$GsScript = Join-Path $InstallDir "installer\Install-Ghostscript.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Green = [Drawing.Color]::FromArgb(22, 128, 57)
$script:Red = [Drawing.Color]::FromArgb(200, 45, 45)
$script:ServerProcess = $null
$script:EventSubs = @()
$script:CachedUsbOk = $false
$script:UsbCheckRunning = $false
$script:UsbJob = $null
$script:ServerStartedOnce = $false
$script:CachedGsPath = $null
$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:SeenLogLines = New-Object 'System.Collections.Generic.HashSet[string]'

function Show-Err([string]$msg) {
    [void][System.Windows.Forms.MessageBox]::Show(
        $msg, "Canon LBP1120", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Resolve-GsPath {
    if ($script:CachedGsPath -and (Test-Path -LiteralPath $script:CachedGsPath)) {
        return $script:CachedGsPath
    }
    $candidates = @(
        (Join-Path $InstallDir "gs\bin\gswin64c.exe"),
        (Join-Path $InstallDir "gs\bin\gswin32c.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $script:CachedGsPath = $c
            return $c
        }
    }
    $cmd = Get-Command gswin64c.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        $script:CachedGsPath = $cmd.Source
        return $cmd.Source
    }
    foreach ($pattern in @(
            (Join-Path ${env:ProgramFiles} "gs\*\bin\gswin64c.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "gs\*\bin\gswin64c.exe")
        )) {
        $hit = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) {
            $script:CachedGsPath = $hit.FullName
            return $hit.FullName
        }
    }
    $script:CachedGsPath = $null
    return $null
}

function Get-GsPath {
    return (Resolve-GsPath)
}

function Test-UsbDevicePresent {
    $dev = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -match 'VID_04A9&PID_262B' -and $_.Status -eq 'OK'
    } | Select-Object -First 1
    return [bool]$dev
}

function Start-ServerOnce {
    if ($script:ServerStartedOnce) { return }
    if ($script:ServerProcess -and -not $script:ServerProcess.HasExited) {
        $script:ServerStartedOnce = $true
        return
    }
    Start-Server
    if ($script:ServerProcess -and -not $script:ServerProcess.HasExited) {
        $script:ServerStartedOnce = $true
    }
}

function Start-UsbCheckAsync {
    if ($script:UsbCheckRunning) { return }
    if (-not (Test-UsbDevicePresent)) {
        $script:CachedUsbOk = $false
        return
    }
    if ($script:UsbJob) {
        Remove-Job $script:UsbJob -Force -ErrorAction SilentlyContinue
        $script:UsbJob = $null
    }
    $script:UsbCheckRunning = $true
    $root = $InstallDir
    $script:UsbJob = Start-Job -ScriptBlock {
        param([string]$Root)
        $dev = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId -match 'VID_04A9&PID_262B' -and $_.Status -eq 'OK'
        } | Select-Object -First 1
        if (-not $dev) { return $false }
        $blob = pnputil /enum-devices /instanceid $dev.InstanceId /drivers 2>&1 | Out-String
        if ($blob -match 'Driver Name:\s+usbprint\.inf') { return $false }
        return $true
    } -ArgumentList $root

    if (-not $script:UsbPollTimer) {
        $script:UsbPollTimer = New-Object System.Windows.Forms.Timer
        $script:UsbPollTimer.Interval = 400
        $script:UsbPollTimer.Add_Tick({
            if (-not $script:UsbJob) { return }
            $st = $script:UsbJob.State
            if ($st -eq 'Running') { return }
            try {
                if ($st -eq 'Completed') {
                    $raw = Receive-Job $script:UsbJob -ErrorAction SilentlyContinue
                    if ($raw -is [Array] -and $raw.Count -gt 0) { $raw = $raw[-1] }
                    $script:CachedUsbOk = [bool]$raw
                } else {
                    $script:CachedUsbOk = $false
                }
            } catch {
                $script:CachedUsbOk = $false
            }
            Remove-Job $script:UsbJob -Force -ErrorAction SilentlyContinue
            $script:UsbJob = $null
            $script:UsbCheckRunning = $false
            $script:UsbPollTimer.Stop()
            Update-StatusPanel
        })
    }
    if (-not $script:UsbPollTimer.Enabled) {
        $script:UsbPollTimer.Start()
    }
}

function Test-PrinterActive {
    $p = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.WorkOffline) { return $false }
    if ($p.PrinterStatus -eq 7) { return $false }
    return $true
}

function Invoke-Ui([scriptblock]$action) {
    if ($null -eq $form -or $form.IsDisposed) { return }
    if ($form.InvokeRequired) {
        try { [void]$form.BeginInvoke($action) } catch { }
    } else {
        & $action
    }
}

function Add-LogLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    Invoke-Ui {
        if (-not $script:SeenLogLines.Add($line)) { return }
        [void]$script:LogLines.Add($line)
        while ($script:LogLines.Count -gt 80) {
            [void]$script:SeenLogLines.Remove($script:LogLines[0])
            $script:LogLines.RemoveAt(0)
        }
        $txtLog.Text = ($script:LogLines -join [Environment]::NewLine)
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    }
}

function Set-Indicator($dot, [bool]$ok) {
    $dot.ForeColor = if ($ok) { $script:Green } else { $script:Red }
}

function Update-StatusPanel {
    $serverOk = $script:ServerProcess -and -not $script:ServerProcess.HasExited
    $gsPath = Resolve-GsPath
    $gsOk = [bool]$gsPath
    $queueOk = Test-PrinterActive
    $usbPresent = Test-UsbDevicePresent
    $usbOk = if ($usbPresent) { $script:CachedUsbOk } else { $false }
    $printerOk = $queueOk -and (-not $usbPresent -or $usbOk)

    Set-Indicator $lblSrvDot $serverOk
    Set-Indicator $lblGsDot $gsOk
    Set-Indicator $lblPrDot $printerOk

    $lblSrvText.Text = if ($serverOk) { "Сервер работает (порт 9100)" } else { "Сервер не запущен" }
    $lblGsText.Text = if ($gsOk) { "Ghostscript найден" } else { "Ghostscript не найден (нужен для Ctrl+P)" }
    $lblPrText.Text = if ($printerOk) { "Canon LBP-1120 (виден, активен)" } else { "Canon LBP-1120 (проверьте USB и очередь)" }

    $allOk = $serverOk -and $gsOk -and $printerOk
    if ($allOk) {
        $lblReady.Text = "Готов к печати"
        $lblReady.ForeColor = $script:Green
    } else {
        $lblReady.Text = "Не готов к печати"
        $lblReady.ForeColor = $script:Red
    }

    if ($serverOk) {
        $btnToggle.Text = "Остановить"
        $btnToggle.BackColor = [Drawing.Color]::FromArgb(255, 235, 235)
    } else {
        $btnToggle.Text = "Запустить"
        $btnToggle.BackColor = [Drawing.Color]::FromArgb(230, 245, 230)
    }
}

function Unregister-ServerEvents {
    $script:EventSubs = @()
}

function Stop-Server {
    Unregister-ServerEvents
    if ($script:ServerProcess) {
        try {
            if (-not $script:ServerProcess.HasExited) {
                $script:ServerProcess.Kill()
                $script:ServerProcess.WaitForExit(2000)
            }
        } catch { }
        try { $script:ServerProcess.Dispose() } catch { }
        $script:ServerProcess = $null
    }
    if (-not $script:TestRunning) {
        Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $form -and -not $form.IsDisposed) {
        if ($form.InvokeRequired) {
            try { [void]$form.BeginInvoke([Action] { Update-StatusPanel }) } catch { }
        } else {
            Update-StatusPanel
        }
    }
}

function Start-Server {
    Stop-Server
    if (-not (Test-Path $Exe)) {
        Show-Err "Не найден captwin.exe"
        Update-StatusPanel
        return
    }
    if (-not (Get-GsPath)) {
        Add-LogLine "Ghostscript не найден — переустановите Setup или положите gs в папку программы."
        Update-StatusPanel
        return
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = "serve --port 9100"
        $psi.WorkingDirectory = $InstallDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $script:ServerProcess = [System.Diagnostics.Process]::Start($psi)
        if (-not $script:ServerProcess) {
            Update-StatusPanel
            return
        }
        Add-LogLine "Сервер captwin запущен (порт 9100)."
        Update-StatusPanel
    } catch {
        Show-Err $_.Exception.Message
        Stop-Server
    }
}

function Invoke-CaptWinCommand([string]$arguments, [switch]$ShowError) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $InstallDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit(120000)
    foreach ($line in ($out + $err) -split "`n") {
        $t = $line.Trim()
        if ($t) { Add-LogLine $t }
    }
    if ($p.ExitCode -ne 0 -and $ShowError) {
        Show-TestPageError $err
    }
    return $p.ExitCode
}

function Show-TestPageError([string]$err) {
    $hint = "Печать на USB не удалась."
    if ($err -match 'NOT_SUPPORTED|failed to open device|usbprint') {
        $hint += "`n`nНужен WinUSB (не «Поддержка USB принтера»).`nОткройте: $InstallDir\tools\zadig.exe"
    }
    Show-Err $hint
}

function Test-HasCaptWinResult {
    param($Item)
    if ($null -eq $Item) { return $false }
    if ($Item -is [System.Collections.IDictionary]) {
        return $Item.Contains('Code') -or $Item.Contains('Out')
    }
    return ($Item.PSObject.Properties.Name -contains 'Code')
}

function Get-TestJobResult {
    param($Raw)
    if ($null -eq $Raw) {
        return @{ Code = 1; Out = ""; Err = "Нет ответа от задачи печати" }
    }
    if ($Raw -is [Array]) {
        $picked = $null
        for ($i = $Raw.Count - 1; $i -ge 0; $i--) {
            if (Test-HasCaptWinResult $Raw[$i]) {
                $picked = $Raw[$i]
                break
            }
        }
        if ($null -eq $picked -and $Raw.Count -gt 0) { $picked = $Raw[-1] }
        $Raw = $picked
    }
    if ($Raw -is [System.Collections.IDictionary]) {
        return @{
            Code = [int]$Raw['Code']
            Out  = [string]$Raw['Out']
            Err  = [string]$Raw['Err']
        }
    }
    if ($Raw -is [pscustomobject]) {
        return @{
            Code = [int]$Raw.Code
            Out  = [string]$Raw.Out
            Err  = [string]$Raw.Err
        }
    }
    return @{ Code = 1; Out = ""; Err = [string]$Raw }
}

function Complete-TestPageJob {
    param($Result)
    $r = Get-TestJobResult -Raw $Result
    try {
        if ($r.Out) {
            foreach ($line in ($r.Out -split "`n")) {
                $t = $line.Trim()
                if ($t) { Add-LogLine $t }
            }
        }
        if ($r.Err) {
            foreach ($line in ($r.Err -split "`n")) {
                $t = $line.Trim()
                if ($t) { Add-LogLine $t }
            }
        }
        if ($r.Code -eq 0) {
            Add-LogLine "Тестовая страница отправлена."
        } else {
            Show-TestPageError $r.Err
        }
    } catch {
        Show-Err $_.Exception.Message
    } finally {
        $script:TestRunning = $false
        $btnTest.Enabled = $true
        $btnTest.Text = "Тестовая страница"
        $script:ServerStartedOnce = $false
        Start-Server
        Update-StatusPanel
    }
}

function Start-TestPageAsync {
    if ($script:TestRunning) { return }
    if (-not (Test-Path -LiteralPath $Exe)) {
        Show-Err "Не найден captwin.exe"
        return
    }
    $script:TestRunning = $true
    $btnTest.Enabled = $false
    $btnTest.Text = "Печать..."
    Add-LogLine "Тест: сервер остановлен, печать на USB..."
    Stop-Server
    Start-Sleep -Milliseconds 400

    $exePath = $Exe
    $workDir = $InstallDir
    $script:TestStartedAt = Get-Date
    $script:TestJob = Start-Job -ScriptBlock {
        param($ExePath, $WorkDir)
        $outFile = [IO.Path]::GetTempFileName()
        $errFile = [IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath $ExePath -ArgumentList @('testpage') -WorkingDirectory $WorkDir `
                -PassThru -Wait -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
            $out = if (Test-Path -LiteralPath $outFile) { [IO.File]::ReadAllText($outFile) } else { "" }
            $err = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) } else { "" }
            [PSCustomObject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
        } catch {
            [PSCustomObject]@{ Code = 1; Out = ""; Err = $_.Exception.Message }
        } finally {
            Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList $exePath, $workDir

    if (-not $script:TestPollTimer) {
        $script:TestPollTimer = New-Object System.Windows.Forms.Timer
        $script:TestPollTimer.Interval = 300
        $script:TestPollTimer.Add_Tick({
            if (-not $script:TestJob) { return }
            $elapsed = ((Get-Date) - $script:TestStartedAt).TotalSeconds
            if ($script:TestJob.State -eq 'Running') {
                if ($elapsed -lt 125) { return }
                Add-LogLine "Тест: превышено время ожидания, отмена..."
                try { Stop-Job $script:TestJob -ErrorAction SilentlyContinue } catch { }
                Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            $script:TestPollTimer.Stop()
            $result = @{ Code = 1; Out = ""; Err = "" }
            try {
                if ($script:TestJob.State -eq 'Completed') {
                    $result = Receive-Job $script:TestJob -ErrorAction Stop
                } elseif ($elapsed -ge 125) {
                    $result.Err = "Печать заняла слишком много времени (лимит 2 мин)."
                }
            } catch {
                $result = @{ Code = 1; Out = ""; Err = $_.Exception.Message }
            }
            Remove-Job $script:TestJob -Force -ErrorAction SilentlyContinue
            $script:TestJob = $null
            Complete-TestPageJob $result
        })
    }
    $script:TestPollTimer.Start()
}

function Start-HiddenProcess([string]$file, [string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $InstallDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [void][System.Diagnostics.Process]::Start($psi)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Canon LBP1120"
$form.Size = New-Object Drawing.Size(420, 380)
$form.MinimumSize = New-Object Drawing.Size(380, 340)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.BackColor = [Drawing.Color]::White

$grpStatus = New-Object System.Windows.Forms.GroupBox
$grpStatus.Text = ""
$grpStatus.Dock = "Top"
$grpStatus.Height = 132
$grpStatus.Padding = New-Object Windows.Forms.Padding(16, 12, 16, 8)

function New-StatusDot([int]$y) {
    $dot = New-Object System.Windows.Forms.Label
    $dot.AutoSize = $true
    $dot.Font = New-Object Drawing.Font("Segoe UI", 12, [Drawing.FontStyle]::Bold)
    $dot.Text = [char]0x25CF
    $dot.Location = New-Object Drawing.Point(20, $y)
    return $dot
}
function New-StatusLabel([int]$y, [string]$text) {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $true
    $l.Text = $text
    $l.Location = New-Object Drawing.Point(44, ($y + 1))
    return $l
}

$lblSrvDot = New-StatusDot 8
$lblGsDot = New-StatusDot 32
$lblPrDot = New-StatusDot 56
$lblSrvText = New-StatusLabel 8 "Сервер не запущен"
$lblGsText = New-StatusLabel 32 "Ghostscript"
$lblPrText = New-StatusLabel 56 "Canon LBP-1120"

$lblReady = New-Object System.Windows.Forms.Label
$lblReady.AutoSize = $true
$lblReady.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$lblReady.Location = New-Object Drawing.Point(20, 88)
$lblReady.Text = "Не готов к печати"

$grpStatus.Controls.AddRange(@(
        $lblSrvDot, $lblSrvText,
        $lblGsDot, $lblGsText,
        $lblPrDot, $lblPrText,
        $lblReady
    ))

$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Dock = "Bottom"
$panelBottom.Height = 44
$panelBottom.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6)

$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Text = "Запустить"
$btnToggle.Size = New-Object Drawing.Size(100, 30)
$btnToggle.Location = New-Object Drawing.Point(8, 6)
$btnToggle.FlatStyle = "Flat"
$btnToggle.Add_Click({
    if ($script:ServerProcess -and -not $script:ServerProcess.HasExited) { Stop-Server }
    else { Start-Server }
})

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = "Тестовая страница"
$btnTest.Size = New-Object Drawing.Size(130, 30)
$btnTest.Location = New-Object Drawing.Point(114, 6)
$btnTest.FlatStyle = "Flat"
$btnTest.Add_Click({ Start-TestPageAsync })

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Обновить"
$btnRefresh.Size = New-Object Drawing.Size(90, 30)
$btnRefresh.Location = New-Object Drawing.Point(250, 6)
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.Add_Click({
    if ($script:ServerProcess -and $script:ServerProcess.HasExited) {
        $script:ServerProcess = $null
    }
    $script:CachedGsPath = $null
    $script:ServerStartedOnce = $false
    if (-not (Test-PrinterActive)) {
        $pq = Join-Path $InstallDir "installer\Install-PrinterQueue.ps1"
        if (Test-Path $pq) {
            try {
                . $pq
                [void](Install-CaptWinPrinterQueue)
            } catch { }
        }
    }
    Start-UsbCheckAsync
    Start-ServerOnce
    Update-StatusPanel
})

$panelBottom.Controls.AddRange(@($btnToggle, $btnTest, $btnRefresh))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.Dock = "Fill"
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = New-Object Drawing.Font("Consolas", 8.5)
$txtLog.BorderStyle = "FixedSingle"

$form.Controls.Add($txtLog)
$form.Controls.Add($panelBottom)
$form.Controls.Add($grpStatus)

$script:StatusTimer = New-Object System.Windows.Forms.Timer
$script:StatusTimer.Interval = 2000
$script:StatusTimer.Add_Tick({
    if ($script:ServerProcess -and $script:ServerProcess.HasExited) {
        $script:ServerProcess = $null
        $script:ServerStartedOnce = $false
    }
    if (-not $script:TestRunning -and -not ($script:ServerProcess -and -not $script:ServerProcess.HasExited)) {
        Start-ServerOnce
    }
    Update-StatusPanel
})

$form.Add_FormClosing({
    $script:StatusTimer.Stop()
    if ($script:UsbPollTimer) { $script:UsbPollTimer.Stop() }
    if ($script:TestPollTimer) { $script:TestPollTimer.Stop() }
    if ($script:UsbJob) { Remove-Job $script:UsbJob -Force -ErrorAction SilentlyContinue }
    if ($script:TestJob) { Remove-Job $script:TestJob -Force -ErrorAction SilentlyContinue }
    Stop-Server
})

$form.Add_Shown({
    try {
        [void](Resolve-GsPath)
        $script:ServerStartedOnce = $false
        $script:StatusTimer.Start()
        Update-StatusPanel
        Start-ServerOnce
        Start-UsbCheckAsync
    } catch {
        Show-Err $_.Exception.Message
    }
})

try {
    [void]$form.ShowDialog()
} catch {
    if (Get-Command Write-CaptWinLog -ErrorAction SilentlyContinue) {
        Write-CaptWinLog $_.Exception.Message "ERROR"
        Write-CaptWinLog $_.ScriptStackTrace "ERROR"
    }
    Show-Err $_.Exception.Message
    exit 1
} finally {
    Stop-Server
}
exit 0
