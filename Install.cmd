@echo off
setlocal
echo.
echo   Grok Bot cursor study
echo.
echo   [1] Apply this scheme
echo   [2] Restore previous pointers
echo   [3] Exit without changes
echo.
choice /C 123 /N /M "  Select: "
if errorlevel 3 exit /b
if errorlevel 2 goto restore
if not errorlevel 1 exit /b
set "MODE=Install"
goto run
:restore
set "MODE=Restore"
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Cursors.ps1" -Action %MODE%
if errorlevel 1 echo   The action failed. See the message above.
pause
