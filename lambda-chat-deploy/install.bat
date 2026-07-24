@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

echo ============================================================
echo   Lambda Chat Extension - Installer
echo ============================================================
echo.

:: Get script directory
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: ============================================================
:: Configuration - Change these to match your servers
:: ============================================================
set "GALLERY_URL=https://100.252.201.200:8443"
set "DEVPI_URL=http://100.252.201.200:3141"
set "DEVPI_INDEX=root/staging"

:: Temp directory
set "TMPDIR=%TEMP%\lambda-install"
if exist "%TMPDIR%" rmdir /s /q "%TMPDIR%"
mkdir "%TMPDIR%"

:: ============================================================
:: Step 1: Configure VS Code gallery + certificate + settings
:: ============================================================
echo [1/4] Configuring VS Code private gallery (%GALLERY_URL%)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\configure-vscode.ps1" -GalleryUrl "%GALLERY_URL%" -InstallCert
echo.

:: ============================================================
:: Step 2: Download + Install Lambda 999.5.0 VSIX
:: ============================================================
echo [2/4] Downloading and installing Lambda Chat extension...
set "LAMBDA_URL=%GALLERY_URL%/files/github/copilot-chat/999.5.0/github.copilot-chat-999.5.0.vsix"
set "LAMBDA_PATH=%TMPDIR%\copilot-chat-999.5.0.vsix"
curl -k -s -L -o "%LAMBDA_PATH%" "%LAMBDA_URL%"
set "VSIX_SIZE=0"
for %%A in ("%LAMBDA_PATH%") do set "VSIX_SIZE=%%~zA"
if "!VSIX_SIZE!"=="" set "VSIX_SIZE=0"
if !VSIX_SIZE! lss 1000 (
    echo   [FAIL] Download failed
    pause
    exit /b 1
)
echo   [OK] Downloaded !VSIX_SIZE! bytes

echo   Installing Lambda Chat extension...
call code --install-extension "%LAMBDA_PATH%" --force
timeout /t 5 /nobreak >nul

REM ============================================================
REM CRITICAL: Completely kill ALL VS Code processes.
REM A single taskkill /f is not enough - Electron spawns multiple
REM child processes (Extension Host, Language Server, GPU, etc)
REM that linger. We must kill them ALL and wait, so that the next
REM VS Code launch starts a fresh Extension Host that loads the
REM Lambda extension's customoai routing correctly.
REM ============================================================
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

:: Cleanup temp
rmdir /s /q "%TMPDIR%" >nul 2>&1

:: ============================================================
:: Step 3: Configure pip to use devpi (only if Python is installed)
:: ============================================================
echo [3/4] Configuring pip to use private package server (%DEVPI_URL%)...

where python >nul 2>&1
if !errorlevel! neq 0 (
    echo   [SKIP] Python not found - skipping pip configuration.
    echo         Install Python first, then run configure-pip.ps1 manually.
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\configure-pip.ps1" -DevpiUrl "%DEVPI_URL%" -Index "%DEVPI_INDEX%"
)
echo.

:: ============================================================
:: Step 4: Launch VS Code fresh
:: ============================================================
echo [4/4] Launching VS Code...
echo   Extension Host will start fresh and load Lambda configuration.
start "" code
echo       Step 4 complete.
echo.

:: ============================================================
:: Done
:: ============================================================
echo ============================================================
echo   Installation Complete!
echo ============================================================
echo.
echo   VS Code has been launched. Please wait for it to fully load.
echo.
echo   Then verify:
echo   1. Settings (Ctrl+,) ^> search "customoai"
echo      - CustomOAI: Url  -> http://100.252.201.200:8088/v1
echo      - CustomOAI: Key  -> dummy-key
echo.
echo   2. Chat panel ^> select a model ^> send a message
echo.
echo   *** If customoai is missing or chat doesn't respond ***
echo   1. Close VS Code completely (all windows)
echo   2. Restart VS Code
echo   3. Check again
echo.
echo   If still not working after restart:
echo   - Extensions (Ctrl+Shift+X) ^> search "copilot chat"
echo   - Disable AI Feature ^> wait 5s
echo   - Enable AI Feature
echo   - Close VS Code completely and restart
echo.
echo   Python packages (if Python installed):
echo   - pip install ^<package^> uses the private devpi server
echo.
pause
