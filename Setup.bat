@echo off
:: Canon LBP1120 CAPT — установка «из коробки» (нужны права администратора)
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
    echo Запуск установщика от имени администратора...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install-CaptWin.ps1"
if errorlevel 1 pause
else echo.
echo Нажмите любую клавишу...
pause >nul
