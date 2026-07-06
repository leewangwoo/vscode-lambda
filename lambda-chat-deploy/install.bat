@echo off
chcp 65001 >nul 2>&1

echo ============================================================
echo   Lambda Chat Extension - Installer
echo ============================================================
echo.

:: Get script directory
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: ============================================================
:: Configuration - Change this to your gallery server URL
:: ============================================================
set "GALLERY_URL=http://100.252.201.200:8000"

:: ============================================================
:: Step 1: Configure VS Code to use private gallery
:: ============================================================
echo [1/5] Configuring VS Code private gallery (%GALLERY_URL%)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\configure-vscode.ps1" -GalleryUrl "%GALLERY_URL%"
echo.

:: ============================================================
:: Step 2: Install original GitHub Copilot Chat VSIX (trust setup)
:: ============================================================
echo [2/5] Installing original GitHub Copilot Chat (trust setup)...
echo       (If "Incompatible" appears, that's OK)
call code --install-extension "%SCRIPT_DIR%\copilot-chat-original.vsix" --force
echo       Step 2 complete.
echo.

:: ============================================================
:: Step 3: Disable builtin AI features (clears config cache)
:: ============================================================
echo [3/5] Disabling builtin AI features to clear configuration cache...
taskkill /im Code.exe /f >nul 2>&1
timeout /t 2 /nobreak >nul

call code --disable-extension GitHub.copilot-chat
timeout /t 8 /nobreak >nul
taskkill /im Code.exe /f >nul 2>&1
timeout /t 2 /nobreak >nul
echo       Step 3 complete.
echo.

:: ============================================================
:: Step 4: Install Lambda custom VSIX
:: ============================================================
echo [4/5] Installing Lambda Chat extension (custom VSIX)...
call code --install-extension "%SCRIPT_DIR%\copilot-chat-999.1.0.vsix" --force
echo       Step 4 complete.
echo.

:: ============================================================
:: Step 5: Enable builtin AI features (refreshes config)
:: ============================================================
echo [5/5] Enabling AI features to load Lambda configuration...
call code --enable-extension GitHub.copilot-chat
timeout /t 8 /nobreak >nul
taskkill /im Code.exe /f >nul 2>&1
timeout /t 2 /nobreak >nul
echo       Step 5 complete.
echo.

:: ============================================================
:: Done
:: ============================================================
echo ============================================================
echo   Installation Complete!
echo ============================================================
echo.
echo   Next steps:
echo   1. Start VS Code
echo   2. Run: Developer: Reload Window (Ctrl+Shift+P)
echo   3. Open Chat panel from the sidebar
echo   4. Select a model from the dropdown
echo.
echo   Settings (Ctrl+,):
echo   - Search "customoai" to configure LiteLLM endpoint
echo   - Default endpoint: http://100.252.201.200:8088/v1
echo.
echo   Private Gallery:
echo   - Extensions tab (Ctrl+Shift+X) shows internal gallery
echo   - Updates are checked automatically
echo.
echo   If customoai settings don't appear:
echo   - Ctrl+Shift+X ^> search "@builtin copilot-chat"
echo   - Disable ^> Reload Window ^> Enable ^> Reload Window
echo.
pause
