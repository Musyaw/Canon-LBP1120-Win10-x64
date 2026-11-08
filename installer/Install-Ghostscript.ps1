# Ghostscript: встроенная копия в {App}\gs\ (копируется установщиком CAPT). Отдельный установщик GS не запускается.

param(
    [string]$InstallDir = ""
)

function Get-GhostscriptPath {
    param([string]$AppRoot = $InstallDir)

    if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
        $bundled = Join-Path $AppRoot "gs\bin\gswin64c.exe"
        if (Test-Path $bundled) { return $bundled }
        $bundled32 = Join-Path $AppRoot "gs\bin\gswin32c.exe"
        if (Test-Path $bundled32) { return $bundled32 }
    }

    $cmd = Get-Command gswin64c.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($pattern in @(
            "${env:ProgramFiles}\gs\*\bin\gswin64c.exe",
            "${env:ProgramFiles(x86)}\gs\*\bin\gswin64c.exe"
        )) {
        $hit = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Install-GhostscriptIfMissing {
    param([string]$AppRoot = $InstallDir)

    $found = Get-GhostscriptPath -AppRoot $AppRoot
    if ($found) {
        Write-Host "Ghostscript: $found" -ForegroundColor Green
        return $true
    }

    Write-Host @"
Ghostscript не найден.
Переустановите Canon-LBP1120-CAPT-Setup.exe (версия со встроенным gs\).
"@ -ForegroundColor Red
    return $false
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Install-GhostscriptIfMissing -AppRoot $InstallDir)) { exit 1 }
}
