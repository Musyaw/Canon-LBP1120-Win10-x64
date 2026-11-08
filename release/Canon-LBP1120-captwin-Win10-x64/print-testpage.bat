@echo off
cd /d "%~dp0"
echo Test page for Canon LBP-1120...
captwin.exe testpage
if errorlevel 1 pause
