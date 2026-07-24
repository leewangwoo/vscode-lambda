@echo off
chcp 65001 >nul 2>&1

REM Unblock the ps1 file (removes Zone.Identifier MOTW mark).
powershell -NoProfile -Command "Unblock-File -LiteralPath '%~dp0진단.ps1' -ErrorAction SilentlyContinue"

REM Run with ExecutionPolicy Bypass (does NOT require admin).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0진단.ps1"
