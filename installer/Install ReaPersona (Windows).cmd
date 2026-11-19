@echo off
rem ReaPersona setup for Windows: double-click this file. It runs install_windows.ps1 from this folder, or downloads it from ReaPersona's
rem GitHub (main branch) if this file was downloaded on its own. Arguments pass through, e.g. -Persona pro_tools.
set HERE=%~dp0
if exist "%HERE%install_windows.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install_windows.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; $f = Join-Path $env:TEMP 'reapersona_install.ps1'; Invoke-WebRequest -UseBasicParsing 'https://github.com/FmsJay/ReaPersona/raw/main/installer/install_windows.ps1' -OutFile $f; & $f %*"
)
echo.
pause
