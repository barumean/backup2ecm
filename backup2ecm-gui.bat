@echo off
rem Backup2ECM GUI launcher
cd /d "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0backup2ecm-gui.ps1"
