@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM   Offline Docker Image Builder (External Network - Windows)
REM
REM   Builds/pulls all images the airgapped deployment needs and
REM   exports them as tar files for transfer to the internal network.
REM
REM   Produces:
REM     code-marketplace.tar   - the gallery backend (VS Code API)
REM     uploader.tar           - VSIX upload sidecar (/upload endpoint)
REM     caddy.tar              - TLS-terminating reverse proxy
REM     devpi-server.tar       - private PyPI mirror
REM
REM   Usage:
REM     build-offline-image.bat [output-dir]
REM
REM   Example:
REM     build-offline-image.bat .\offline-images
REM ============================================================

set "OUTPUT_DIR=%~1"
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=.\offline-images"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%\..") do set "GALLERY_DIR=%%~fi"
for %%i in ("%SCRIPT_DIR%\..\..") do set "PROJECT_ROOT=%%~fi"

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo ============================================================
echo   Offline Docker Image Builder (External Network)
echo ============================================================
echo   Output dir: %OUTPUT_DIR%
echo   Project:    %PROJECT_ROOT%
echo.

REM ============================================================
REM 1. Pull code-marketplace
REM ============================================================
echo [1/8] Pulling code-marketplace image...
docker pull ghcr.io/coder/code-marketplace:v2.4.2
if !errorlevel! neq 0 (
    echo   [FAIL] Pull failed
    pause
    exit /b 1
)
echo   [OK] Pull complete
echo.

REM ============================================================
REM 2. Export code-marketplace image to tar
REM ============================================================
echo [2/8] Exporting code-marketplace image to tar...
docker save ghcr.io/coder/code-marketplace:v2.4.2 -o "%OUTPUT_DIR%\code-marketplace.tar"
if !errorlevel! neq 0 (
    echo   [FAIL] Export failed
    pause
    exit /b 1
)
for %%A in ("%OUTPUT_DIR%\code-marketplace.tar") do echo   [OK] Exported %%~zA bytes
echo.

REM ============================================================
REM 3. Build uploader sidecar image
REM ============================================================
echo [3/8] Building uploader sidecar image...
docker build -t lambda-gallery-uploader:latest "%GALLERY_DIR%\uploader"
if !errorlevel! neq 0 (
    echo   [FAIL] Build failed
    pause
    exit /b 1
)
echo   [OK] Build complete
echo.

REM ============================================================
REM 4. Export uploader image to tar
REM ============================================================
echo [4/8] Exporting uploader image to tar...
docker save lambda-gallery-uploader:latest -o "%OUTPUT_DIR%\uploader.tar"
if !errorlevel! neq 0 (
    echo   [FAIL] Export failed
    pause
    exit /b 1
)
for %%A in ("%OUTPUT_DIR%\uploader.tar") do echo   [OK] Exported %%~zA bytes
echo.

REM ============================================================
REM 5. Build Caddy reverse proxy image
REM ============================================================
echo [5/8] Building Caddy reverse-proxy image...
docker build -t lambda-gallery-caddy:latest "%GALLERY_DIR%\caddy"
if !errorlevel! neq 0 (
    echo   [FAIL] Build failed
    pause
    exit /b 1
)
echo   [OK] Build complete
echo.

REM ============================================================
REM 6. Export Caddy image to tar
REM ============================================================
echo [6/8] Exporting Caddy image to tar...
docker save lambda-gallery-caddy:latest -o "%OUTPUT_DIR%\caddy.tar"
if !errorlevel! neq 0 (
    echo   [FAIL] Export failed
    pause
    exit /b 1
)
for %%A in ("%OUTPUT_DIR%\caddy.tar") do echo   [OK] Exported %%~zA bytes
echo.

REM ============================================================
REM 7. Pull devpi-server image
REM ============================================================
echo [7/8] Pulling devpi-server image...
docker pull jonasal/devpi-server:latest
if !errorlevel! neq 0 (
    echo   [FAIL] Pull failed
    pause
    exit /b 1
)
echo   [OK] Pull complete
echo.

REM ============================================================
REM 8. Export devpi-server image to tar
REM ============================================================
echo [8/8] Exporting devpi-server image to tar...
docker save jonasal/devpi-server:latest -o "%OUTPUT_DIR%\devpi-server.tar"
if !errorlevel! neq 0 (
    echo   [FAIL] Export failed
    pause
    exit /b 1
)
for %%A in ("%OUTPUT_DIR%\devpi-server.tar") do echo   [OK] Exported %%~zA bytes
echo.

REM ============================================================
REM Done
REM ============================================================
echo ============================================================
echo   Build Complete!
echo ============================================================
echo.
echo   Generated files:
for %%A in ("%OUTPUT_DIR%\*.tar") do echo   %%~nxA  %%~zA bytes
echo.
echo   Next steps:
echo   1. Copy the %OUTPUT_DIR%\ folder to the internal network server.
echo   2. Run load-offline-images.sh on the internal server.
echo.
pause
