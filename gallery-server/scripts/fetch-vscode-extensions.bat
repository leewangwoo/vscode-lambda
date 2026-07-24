@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM   Download VS Code extensions from the public marketplace and
REM   push them to the private code-marketplace gallery over HTTPS.
REM
REM   Uses fetch-extension.js to get the WIN32-X64 VSIX (not @web or
REM   darwin-x64) so Windows clients can actually install them.
REM
REM   Run this on a machine WITH internet access. It does NOT need
REM   docker/SSH access to the gallery server - it just POSTs the
REM   VSIXes to https://<gallery>/upload.
REM
REM   Usage:
REM     fetch-vscode-extensions.bat [gallery-url] [target-platform]
REM
REM   Example:
REM     fetch-vscode-extensions.bat
REM     fetch-vscode-extensions.bat https://100.252.201.200:8443 win32-x64
REM ============================================================

set "GALLERY_URL=%~1"
if "!GALLERY_URL!"=="" set "GALLERY_URL=https://100.252.201.200:8443"
if "!GALLERY_URL:~-1!"=="/" set "GALLERY_URL=!GALLERY_URL:~0,-1!"

set "PLATFORM=%~2"
if "!PLATFORM!"=="" set "PLATFORM=win32-x64"

set "UPLOAD_TOKEN=lambda-upload"

set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

set "OUTDIR=%TEMP%\vsix-download"
if exist "!OUTDIR!" rmdir /s /q "!OUTDIR!"
mkdir "!OUTDIR!"

echo ============================================================
echo   VS Code Extension Downloader ^> Private Gallery
echo ============================================================
echo   Source:   marketplace.visualstudio.com
echo   Target:   !GALLERY_URL!/upload
echo   Platform: !PLATFORM!
echo ============================================================
echo.

set DOWNLOADED=0
set FAILED=0

for %%E in (
    ms-python.python
    ms-python.vscode-pylance
    ms-python.debugpy
    ms-python.black-formatter
    ms-python.isort
    ms-vscode.powershell
    redhat.vscode-yaml
    ms-azuretools.vscode-docker
    ms-vscode-remote.remote-ssh
) do (
    set "EXT=%%E"
    echo Fetching: !EXT!

    node "!SCRIPT_DIR!\fetch-extension.js" "!EXT!" "!OUTDIR!\!EXT!.vsix" "!PLATFORM!"
    if !errorlevel! equ 0 (
        if exist "!OUTDIR!\!EXT!.vsix" (
            for %%A in ("!OUTDIR!\!EXT!.vsix") do set "FSIZE=%%~zA"
            echo   [OK] !FSIZE! bytes
            set /a DOWNLOADED+=1
        ) else (
            echo   [WARN] File missing after download
            set /a FAILED+=1
        )
    ) else (
        echo   [WARN] Download failed
        set /a FAILED+=1
    )
    echo.
)

echo ============================================================
echo   Downloads: !DOWNLOADED! ok, !FAILED! failed
echo ============================================================
echo.

if !DOWNLOADED! equ 0 (
    echo [FAIL] Nothing downloaded - check internet connectivity.
    rmdir /s /q "!OUTDIR!" 2>nul
    exit /b 1
)

REM ----------------------------------------------------------------
REM Push every downloaded VSIX to the gallery via /upload.
REM ----------------------------------------------------------------
echo Publishing !DOWNLOADED! extension^(s^) to !GALLERY_URL!/upload ...
echo.

set PUBLISHED=0
for %%F in ("!OUTDIR!\*.vsix") do (
    echo Uploading: %%~nxF
    curl -k -s -m 600 -X POST ^
        -H "X-Upload-Token: !UPLOAD_TOKEN!" ^
        -F "file=@%%F" ^
        "!GALLERY_URL!/upload" > "!OUTDIR!\resp.txt" 2>&1

    findstr /C:"\"status\":\"ok\"" "!OUTDIR!\resp.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [OK] Registered
        set /a PUBLISHED+=1
    ) else (
        echo   [FAIL] Upload failed
        type "!OUTDIR!\resp.txt"
    )
    echo.
)

echo ============================================================
echo   Summary: !PUBLISHED!/!DOWNLOADED! registered in gallery.
echo ============================================================

rmdir /s /q "!OUTDIR!" 2>nul
endlocal
