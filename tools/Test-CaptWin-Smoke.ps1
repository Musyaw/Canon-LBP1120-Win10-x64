# Smoke-тесты UI/launcher (Windows PowerShell 5.1). Запуск: .\tools\Test-CaptWin-Smoke.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $Root "installer\CaptWin-Launcher.ps1"))) {
    $Root = "c:\Users\DELL\Desktop\printer fix"
}

$Release = Join-Path $Root "release\Canon-LBP1120-captwin-Win10-x64"
$Prog = Join-Path ${env:ProgramFiles} "CanonLBP1120Capt"
$InstallDir = if (Test-Path (Join-Path $Release "captwin.exe")) { $Release } elseif (Test-Path (Join-Path $Prog "captwin.exe")) { $Prog } else { $Release }

$fail = New-Object System.Collections.Generic.List[string]
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { [void]$fail.Add($msg); Write-Host "FAIL: $msg" -ForegroundColor Red }
    else { Write-Host "OK: $msg" -ForegroundColor Green }
}

Write-Host "InstallDir=$InstallDir" -ForegroundColor Cyan

Assert (Test-Path (Join-Path $Root "tools\zadig\zadig.exe")) "tools\zadig\zadig.exe present for installer"
$issPath = Join-Path $Root "installer\CaptWinSetup.iss"
if (Test-Path $issPath) {
    $issText = Get-Content -LiteralPath $issPath -Raw
    Assert ($issText -match 'tools\\zadig\\zadig\.exe') "CaptWinSetup.iss embeds zadig.exe"
    Assert ($issText -match 'example-1\.pbm') "CaptWinSetup.iss embeds test page PBM"
}

# --- Parse ---
$critical = @(
    "installer\CaptWin-Launcher.ps1",
    "installer\CaptWin-Server-Gui.ps1",
    "installer\PostInstall-Wizard.ps1",
    "installer\CaptWin-Logging.ps1"
)
foreach ($rel in $critical) {
    $path = Join-Path $Root $rel
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Assert ((-not $parseErrors -or $parseErrors.Count -eq 0)) "Parse $rel"
}

# --- No PS7 / broken patterns ---
foreach ($rel in $critical) {
    $text = Get-Content -LiteralPath (Join-Path $Root $rel) -Raw
    Assert ($text -notmatch '\?\?') "No PS7 ?? in $rel"
    Assert ($text -notmatch '\.DoWork\s\+=') "No BackgroundWorker DoWork += in $rel"
    Assert ($text -notmatch '\$worker\.RunWorkerCompleted\s\+=') "No RunWorkerCompleted += in $rel"
}

# --- USB job (same as GUI) ---
if (Test-Path (Join-Path $InstallDir "captwin.exe")) {
    $job = Start-Job -ScriptBlock {
        param([string]$Root)
        $dev = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId -match 'VID_04A9&PID_262B' -and $_.Status -eq 'OK'
        } | Select-Object -First 1
        if (-not $dev) { return $false }
        $blob = pnputil /enum-devices /instanceid $dev.InstanceId /drivers 2>&1 | Out-String
        if ($blob -match 'Driver Name:\s+usbprint\.inf') { return $false }
        return $true
    } -ArgumentList $InstallDir
    $null = Wait-Job $job -Timeout 20
    if ($job.State -eq 'Running') { Stop-Job $job; Remove-Job $job -Force }
    Assert ($job.State -eq 'Completed') "USB Start-Job completes (state=$($job.State))"
    if ($job.State -eq 'Completed') {
        $usbResult = Receive-Job $job
        Write-Host "  USB check result: $usbResult"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "SKIP: USB job (no captwin.exe in $InstallDir)" -ForegroundColor Yellow
}

# --- Wizard exits immediately when done flag ---
$wizard = Join-Path $Root "installer\PostInstall-Wizard.ps1"
$dataDir = Join-Path $InstallDir "data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$doneFlag = Join-Path $dataDir "setup-wizard.done"
$hadDone = Test-Path $doneFlag
$backup = $null
if ($hadDone) { $backup = Get-Content $doneFlag -Raw; Remove-Item $doneFlag -Force }
Set-Content -Path $doneFlag -Value "test" -Encoding UTF8
try {
    & $wizard -InstallDir $InstallDir
    $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    Assert ($code -eq 0) "Wizard skip when setup-wizard.done (exit=$code)"
} finally {
    if ($hadDone -and $null -ne $backup) { Set-Content $doneFlag $backup -Encoding UTF8 }
    elseif (-not $hadDone) { Remove-Item $doneFlag -Force -ErrorAction SilentlyContinue }
}

# --- Sync release tree for GUI test ---
$instInstaller = Join-Path $InstallDir "installer"
New-Item -ItemType Directory -Force -Path $instInstaller | Out-Null
Copy-Item (Join-Path $Root "installer\CaptWin-Server-Gui.ps1") $InstallDir -Force
Copy-Item (Join-Path $Root "installer\CaptWin-Launcher.ps1") $InstallDir -Force
Copy-Item (Join-Path $Root "installer\CaptWin-Logging.ps1") $instInstaller -Force

# --- GUI smoke: launcher не падает сразу ---
$launcherCopy = Join-Path $InstallDir "CaptWin-Launcher.ps1"
$cmd = "& `"$launcherCopy`" -InstallDir `"$InstallDir`" -SkipWizard"
$p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-STA", "-NoLogo", "-ExecutionPolicy", "Bypass", "-Command", $cmd) `
    -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
Assert ($null -ne $p -and -not $p.HasExited) "Launcher/GUI alive after 3s (no immediate crash)"
if ($p -and -not $p.HasExited) {
    Assert ($p.Responding) "Launcher process Responding"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Get-Process captwin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($fail.Count -gt 0) {
    Write-Host "FAILED $($fail.Count) test(s)" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host "All smoke tests passed." -ForegroundColor Green
exit 0
