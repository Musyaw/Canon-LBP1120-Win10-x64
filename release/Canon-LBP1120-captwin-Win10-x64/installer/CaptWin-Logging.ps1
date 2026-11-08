# Общий лог Canon LBP1120 CAPT → рабочий стол + data\launch.log
function Initialize-CaptWinLog {
    param(
        [string]$InstallDir = "",
        [string]$Source = "app"
    )
    $script:CaptWinDesktopLog = Join-Path ([Environment]::GetFolderPath("Desktop")) "LBP1120-CAPT.log"
    $script:CaptWinInstallLog = $null
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $dataDir = Join-Path $InstallDir "data"
        try {
            New-Item -ItemType Directory -Force -Path $dataDir -ErrorAction Stop | Out-Null
            $script:CaptWinInstallLog = Join-Path $dataDir "launch.log"
        } catch { }
    }
    Write-CaptWinLog "----- $Source -----"
}

function Write-CaptWinLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    if (-not $script:CaptWinDesktopLog) {
        $script:CaptWinDesktopLog = Join-Path ([Environment]::GetFolderPath("Desktop")) "LBP1120-CAPT.log"
    }
    $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
    foreach ($path in @($script:CaptWinDesktopLog, $script:CaptWinInstallLog)) {
        if (-not $path) { continue }
        try { Add-Content -LiteralPath $path -Value $line -Encoding UTF8 } catch { }
    }
}

function Get-ScriptParseErrors {
    param([string]$ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return @("Файл не найден: $ScriptPath")
    }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath, [ref]$tokens, [ref]$parseErrors)
    if (-not $parseErrors -or $parseErrors.Count -eq 0) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($pe in $parseErrors) {
        [void]$out.Add(("{0}:{1} {2}" -f $pe.Extent.StartLineNumber, $pe.Extent.StartColumnNumber, $pe.Message))
    }
    return $out.ToArray()
}

function Show-CaptWinFailure {
    param([string]$Title, [string]$Message)
    Write-CaptWinLog "$Title`: $Message" "ERROR"
    $logHint = "Подробности: $script:CaptWinDesktopLog"
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [void][System.Windows.Forms.MessageBox]::Show(
            "$Message`n`n$logHint", "Canon LBP1120 CAPT", "OK", "Error")
    } catch { }
    try {
        if (Test-Path -LiteralPath $script:CaptWinDesktopLog) {
            Start-Process -FilePath "notepad.exe" -ArgumentList @($script:CaptWinDesktopLog)
        }
    } catch { }
}
