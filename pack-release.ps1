$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseName = "Canon-LBP1120-captwin-Win10-x64"
$ReleaseDir = Join-Path $Root "release\$ReleaseName"

# Build if missing
$BuildExe = Join-Path $Root "build\captwin.exe"
if (-not (Test-Path $BuildExe)) {
    & (Join-Path $Root "build.ps1")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Packaging to $ReleaseDir ..." -ForegroundColor Cyan
$icoSrc = Join-Path $Root "installer\captwin.ico"
if (-not (Test-Path $icoSrc)) {
    Add-Type -AssemblyName System.Drawing
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\printui.dll")
    $fs = [System.IO.File]::Create($icoSrc)
    $icon.Save($fs)
    $fs.Close()
}
if (Test-Path $ReleaseDir) { Remove-Item $ReleaseDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$ReleaseDir\data", "$ReleaseDir\tools" | Out-Null

Copy-Item $BuildExe $ReleaseDir -Force
Copy-Item (Join-Path $Root "build\libwinpthread-1.dll") $ReleaseDir -Force -ErrorAction SilentlyContinue
if (-not (Test-Path (Join-Path $ReleaseDir "libwinpthread-1.dll"))) {
    Copy-Item "C:\mingw64\bin\libwinpthread-1.dll" $ReleaseDir -Force
}

Copy-Item (Join-Path $Root "libcapt\examples\data\example-1.pbm") "$ReleaseDir\data\" -Force
Copy-Item (Join-Path $Root "tools\zadig\zadig.exe") "$ReleaseDir\tools\" -Force
foreach ($tool in @("devcon.exe", "wdi-simple.exe")) {
    $src = Join-Path $Root "tools\$tool"
    if (Test-Path $src) { Copy-Item $src "$ReleaseDir\tools\" -Force }
}
Copy-Item (Join-Path $Root "install-winusb.ps1") $ReleaseDir -Force
Copy-Item (Join-Path $Root "install-winusb.bat") $ReleaseDir -Force

@'
@echo off
cd /d "%~dp0"
echo Test page for Canon LBP-1120...
captwin.exe testpage
if errorlevel 1 pause
'@ | Set-Content -Path (Join-Path $ReleaseDir "print-testpage.bat") -Encoding ASCII

Copy-Item (Join-Path $Root "release\README.ru.txt") $ReleaseDir -Force
Copy-Item (Join-Path $Root "release\LICENSES.txt") $ReleaseDir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root "release\start-print-server.bat") $ReleaseDir -Force
Copy-Item (Join-Path $Root "release\install-ghostscript.bat") $ReleaseDir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root "installer\CaptWin-Launcher.ps1") $ReleaseDir -Force
Copy-Item (Join-Path $Root "installer\CaptWin-Server-Gui.ps1") $ReleaseDir -Force
Copy-Item (Join-Path $Root "installer\CaptWin-Server.bat") $ReleaseDir -Force
Copy-Item (Join-Path $Root "installer\Launch-CaptWinServer.vbs") $ReleaseDir -Force
Copy-Item (Join-Path $Root "installer\captwin.ico") $ReleaseDir -Force
Copy-Item (Join-Path $Root "release\install-system-printer.ps1") $ReleaseDir -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$ReleaseDir\installer" | Out-Null
Copy-Item (Join-Path $Root "installer\captwin_winusb.inf") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Install-CaptWin.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Install-Ghostscript.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Install-PrinterQueue.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Fix-PrintQueue.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Uninstall-CaptWin.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Setup-PrinterQueue.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Setup-PrinterQueue.bat") $ReleaseDir -Force
Copy-Item (Join-Path $Root "installer\CaptWin-Logging.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\PostInstall-Wizard.ps1") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "installer\Setup-Guide.ru.txt") "$ReleaseDir\installer\" -Force
Copy-Item (Join-Path $Root "Setup.bat") $ReleaseDir -Force

$BundledGs = Join-Path $Root "third_party\ghostscript"
$GsExe = Join-Path $BundledGs "bin\gswin64c.exe"
if (Test-Path $GsExe) {
    Write-Host "Bundling Ghostscript from $BundledGs ..." -ForegroundColor Cyan
    Copy-Item $BundledGs (Join-Path $ReleaseDir "gs") -Recurse -Force
} else {
    Write-Warning "third_party\ghostscript\bin\gswin64c.exe not found. Run: .\tools\fetch-ghostscript.ps1"
}
@'
@echo off
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install-CaptWin.ps1"
pause
'@ | Set-Content -Path (Join-Path $ReleaseDir "Setup.bat") -Encoding ASCII

Write-Host "Done: $ReleaseDir" -ForegroundColor Green
Write-Host "Zip (optional): Compress-Archive -Path '$ReleaseDir' -DestinationPath '$Root\release\$ReleaseName.zip' -Force"
