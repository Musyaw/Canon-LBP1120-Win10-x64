$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Drive = "P:"
if (-not (Test-Path "${Drive}\")) {
    subst $Drive $Root
}
$WorkRoot = $Drive + "\"
$Cmake = Join-Path $WorkRoot "tools\cmake\bin\cmake.exe"
$Mingw = "C:\mingw64\bin"
if (-not (Test-Path (Join-Path $Mingw "g++.exe"))) {
    Write-Host "Copying MinGW to C:\mingw64 (required: no spaces in toolchain path)..."
    robocopy (Join-Path $Root "tools\winlibs_extract\mingw64") "C:\mingw64" /E /NFL /NDL /NJH /NJS /nc /np | Out-Null
}
$env:PATH = "$Mingw;$env:PATH"

if (-not (Test-Path $Cmake)) {
    Write-Error "CMake not found at $Cmake"
}

$BuildDir = Join-Path $WorkRoot "build"
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
& $Cmake -S (Join-Path $WorkRoot "captwin") -B $BuildDir -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Cmake --build $BuildDir --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item "C:\mingw64\bin\libwinpthread-1.dll" (Join-Path $BuildDir "libwinpthread-1.dll") -Force -ErrorAction SilentlyContinue
Write-Host "`nBuilt: $(Join-Path $BuildDir 'captwin.exe')"
