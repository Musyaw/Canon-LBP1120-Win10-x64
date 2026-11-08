# Ярлык «LBP-1120 — быстрый запуск»: мастер (один раз) → окно сервера (один процесс PowerShell / STA).
param(
    [string]$InstallDir = "",
    [switch]$ForceWizard,
    [switch]$SkipWizard
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$loggingPs1 = Join-Path $InstallDir "installer\CaptWin-Logging.ps1"
if (Test-Path -LiteralPath $loggingPs1) {
    . $loggingPs1
    Initialize-CaptWinLog -InstallDir $InstallDir -Source "Launcher"
} else {
    function Write-CaptWinLog { param($Message, $Level = "INFO")
        $p = Join-Path ([Environment]::GetFolderPath("Desktop")) "LBP1120-CAPT.log"
        Add-Content -LiteralPath $p -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    function Show-CaptWinFailure { param($Title, $Message)
        Write-CaptWinLog "$Title`: $Message" "ERROR"
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [void][System.Windows.Forms.MessageBox]::Show("$Message`n`nСм. LBP1120-CAPT.log на рабочем столе.", "Canon LBP1120 CAPT", "OK", "Error")
    }
    function Get-ScriptParseErrors { param($ScriptPath) @() }
}

$doneFlag = Join-Path $InstallDir "data\setup-wizard.done"
$wizardPs1 = Join-Path $InstallDir "installer\PostInstall-Wizard.ps1"
$guiPs1 = Join-Path $InstallDir "CaptWin-Server-Gui.ps1"

function Invoke-CaptWinScript {
    param(
        [string]$ScriptPath,
        [string]$Label,
        [switch]$Force
    )
    Write-CaptWinLog "Invoke $Label`: $ScriptPath"
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return @{ Ok = $false; Code = 1; Error = "Не найден:`n$ScriptPath" }
    }
    foreach ($pe in (Get-ScriptParseErrors -ScriptPath $ScriptPath)) {
        Write-CaptWinLog "Parse $Label`: $pe" "ERROR"
    }
    try {
        if ($Force) {
            & $ScriptPath -InstallDir $InstallDir -Force
        } else {
            & $ScriptPath -InstallDir $InstallDir
        }
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        Write-CaptWinLog "Exit $Label code=$code"
        return @{ Ok = ($code -eq 0); Code = $code; Error = $null }
    } catch {
        Write-CaptWinLog "$Label exception: $($_.Exception.Message)" "ERROR"
        Write-CaptWinLog $_.ScriptStackTrace "ERROR"
        return @{ Ok = $false; Code = 1; Error = $_.Exception.Message }
    }
}

try {
    Write-CaptWinLog "InstallDir=$InstallDir SkipWizard=$SkipWizard ForceWizard=$ForceWizard"

    if (-not $SkipWizard) {
        if ($ForceWizard) {
            $r = Invoke-CaptWinScript -ScriptPath $wizardPs1 -Label "Wizard" -Force
            if (-not $r.Ok) {
                $errMsg = if ($r.Error) { $r.Error } else { "Код выхода $($r.Code)" }
                Show-CaptWinFailure "Мастер настройки" $errMsg
                exit ($r.Code)
            }
        } elseif (-not (Test-Path -LiteralPath $doneFlag)) {
            $r = Invoke-CaptWinScript -ScriptPath $wizardPs1 -Label "Wizard"
            if (-not $r.Ok) {
                $errMsg = if ($r.Error) { $r.Error } else { "Код выхода $($r.Code)" }
                Show-CaptWinFailure "Мастер настройки" $errMsg
                exit ($r.Code)
            }
        }
    }

    $rGui = Invoke-CaptWinScript -ScriptPath $guiPs1 -Label "ServerGUI"
    if (-not $rGui.Ok) {
        $msg = if ($rGui.Error) { $rGui.Error } else { "Окно сервера завершилось с кодом $($rGui.Code)." }
        Show-CaptWinFailure "Сервер печати" $msg
        exit ($rGui.Code)
    }

    Write-CaptWinLog "OK"
    exit 0
} catch {
    Show-CaptWinFailure "Запуск" $_.Exception.Message
    Write-CaptWinLog $_.ScriptStackTrace "ERROR"
    exit 1
}
