@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

echo ============================================================
echo   Lambda Chat Extension - Update
echo ============================================================
echo.

:: Get script directory
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: ============================================================
:: Configuration
:: ============================================================
set "GALLERY_URL=https://100.252.201.200:8443"
set "LAMBDA_EXT_VERSION=999.46.0"

:: Temp directory
set "TMPDIR=%TEMP%\lambda-update"
if exist "%TMPDIR%" rmdir /s /q "%TMPDIR%"
mkdir "%TMPDIR%"

:: ============================================================
:: Step 1: Download latest Lambda VSIX from gallery
:: ============================================================
echo [1/3] Downloading Lambda Chat v%LAMBDA_EXT_VERSION% from gallery...
set "VSIX_URL=%GALLERY_URL%/files/github/copilot-chat/%LAMBDA_EXT_VERSION%/github.copilot-chat-%LAMBDA_EXT_VERSION%.vsix"
set "VSIX_PATH=%TMPDIR%\copilot-chat-%LAMBDA_EXT_VERSION%.vsix"

curl -k -s -L -o "%VSIX_PATH%" "%VSIX_URL%"
set "VSIX_SIZE=0"
for %%A in ("%VSIX_PATH%") do set "VSIX_SIZE=%%~zA"
if "!VSIX_SIZE!"=="" set "VSIX_SIZE=0"
if !VSIX_SIZE! lss 1000 (
    echo   [FAIL] Download failed
    pause
    exit /b 1
)
echo   [OK] Downloaded !VSIX_SIZE! bytes
echo.

:: ============================================================
:: Step 2: Install new version (--force overwrites existing)
:: ============================================================
echo [2/3] Installing Lambda Chat v%LAMBDA_EXT_VERSION%...
call code --install-extension "%VSIX_PATH%" --force
timeout /t 5 /nobreak >nul

REM Completely kill VS Code so Extension Host restarts fresh.
echo   Stopping VS Code completely...
:kill_loop
taskkill /im Code.exe /f /t >nul 2>&1
timeout /t 2 /nobreak >nul
tasklist /fi "imagename eq Code.exe" 2>nul | find /i "Code.exe" >nul
if !errorlevel! equ 0 (
    echo   Still running, retrying...
    goto kill_loop
)
echo   VS Code fully stopped.
timeout /t 3 /nobreak >nul
echo       Step 2 complete.
echo.

:: Cleanup
rmdir /s /q "%TMPDIR%" >nul 2>&1

:: ============================================================
:: Step 3: Launch VS Code fresh
:: ============================================================
echo [3/3] Launching VS Code...
start "" code
echo       Step 3 complete.
echo.

:: ============================================================
:: Done
:: ============================================================
echo ============================================================
echo   Update Complete! (v%LAMBDA_EXT_VERSION%)
echo ============================================================
echo.
echo   VS Code has been launched with the new version.
echo.
echo   Verify:
echo   1. Settings (Ctrl+,) ^> search "customoai"
echo   2. Chat panel ^> send a message to test
echo.
echo   If customoai is missing or chat doesn't respond:
echo   1. Close VS Code completely
echo   2. Restart VS Code
echo.
pause
