@echo off
setlocal enabledelayedexpansion

:: Usage: sync-packages.bat <requirements-file> [devpi-url]
set "REQUIREMENTS=%~1"
set "DEVPI_URL=%~2"

if "%REQUIREMENTS%"=="" (
    echo Usage: %~nx0 ^<requirements-file^> [devpi-url]
    exit /b 1
)

if "%DEVPI_URL%"=="" (
    set "DEVPI_URL=http://100.252.201.200:3141"
)

:: Use temporary directory
if "%TMPDIR%"=="" (
    set "TMPDIR=%TEMP%\devpi-sync"
)

if not exist "%REQUIREMENTS%" (
    echo [ERROR] Requirements file not found: %REQUIREMENTS%
    exit /b 1
)

echo ============================================
echo   devpi Package Synchronizer (Windows)
echo ============================================
echo   Source:   PyPI (internet)
echo   Target:   %DEVPI_URL%
echo   Packages: %REQUIREMENTS%
echo ============================================
echo.

:: Ensure devpi-client is installed
where devpi >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Installing devpi-client...
    pip install devpi-client
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Failed to install devpi-client
        exit /b 1
    )
)

:: Configure devpi
call devpi use "%DEVPI_URL%"

:: Check if already logged in
call devpi use | findstr /i "logged in" >nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Already logged in.
) else (
    if not "%DEVPI_PASSWORD%"=="" (
        echo Logging in using DEVPI_PASSWORD...
        call devpi login root --password="%DEVPI_PASSWORD%"
    ) else (
        echo Please login to devpi:
        call devpi login root
    )
)

call devpi use root/staging

:: Create temp directory
if not exist "%TMPDIR%\downloads" (
    mkdir "%TMPDIR%\downloads"
)

:: Download all packages from PyPI
echo.
echo [INFO] Downloading packages from PyPI...
pip download -r "%REQUIREMENTS%" -d "%TMPDIR%\downloads" --index-url https://pypi.org/simple/
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to download packages
    exit /b 1
)

:: Upload all downloaded packages to devpi
echo.
echo [INFO] Uploading packages to devpi...
pushd "%TMPDIR%\downloads"

set "UPLOADED=0"
set "FAILED=0"

for %%f in (*.whl *.tar.gz *.zip) do (
    if exist "%%f" (
        echo   Uploading: %%f
        call devpi upload "%%f" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            set /a UPLOADED+=1
        ) else (
            echo     Warning: Failed (may already exist): %%f
            set /a FAILED+=1
        )
    )
)

popd

echo.
echo ============================================
echo   Sync Complete
echo   Uploaded: %UPLOADED%
echo   Skipped/Failed: %FAILED%
echo ============================================

:: Cleanup
if exist "%TMPDIR%\downloads" (
    rd /s /q "%TMPDIR%\downloads"
)

endlocal
