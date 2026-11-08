@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0installer\Install-Ghostscript.ps1"
if errorlevel 1 pause
exit /b %errorlevel%
