@echo off
setlocal
cd /d "%~dp0"

echo Installing or updating chatterino-kick-chat...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" -CloseChatterino
set "INSTALL_EXIT=%ERRORLEVEL%"

if not "%INSTALL_EXIT%"=="0" (
  echo.
  echo Installation failed. No system-wide PowerShell policy was changed.
  echo Copy the error above when asking for help.
) else (
  echo.
  echo Done. Open Chatterino and run /kick-chat status in a named channel.
)

echo.
pause
exit /b %INSTALL_EXIT%
