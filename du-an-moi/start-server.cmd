@echo off
cd /d "%~dp0"
start "Cham Cong Server" powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 8092 -BindAddress 0.0.0.0
