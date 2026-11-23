@echo off
rem Daytona USA (recompiled) - settings launcher. See scripts\launcher.ps1.
set "PS1=%~dp0launcher.ps1"
if not exist "%PS1%" set "PS1=%~dp0scripts\launcher.ps1"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%"
