@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM   Publish VSIX extension(s) to the private code-marketplace
REM   over HTTPS. Uploads via the gallery's uploader sidecar,
REM   which registers the file with code-marketplace automatically.
REM
REM   This runs on the EXTERNAL PC and pushes to the internal
REM   network gallery server. No SSH/docker access needed.
REM
REM   Usage:
REM     publish.bat <file.vsix> [file2.vsix ...]
REM     publish.bat <directory>
REM     publish.bat                       (publishes *.vsix in cwd)
REM
REM   Examples:
REM     publish.bat ..\..\lambda-chat-deploy\copilot-chat-999.1.0.vsix
REM     publish.bat C:\extensions
REM     publish.bat
REM ============================================================

REM Gallery URL + upload token (must match uploader UPLOAD_TOKEN).
set "GALLERY_URL=https://100.252.201.200:8443"
set "UPLOAD_TOKEN=lambda-upload"

REM If arg1 starts with http, treat it as the gallery URL.
set "FIRSTARG=%~1"
if defined FIRSTARG (
    if /i "!FIRSTARG:~0,4!"=="http" (
        set "GALLERY_URL=!FIRSTARG!"
        shift
    )
)

REM Strip trailing slash.
if "!GALLERY_URL:~-1!"=="/" set "GALLERY_URL=!GALLERY_URL:~0,-1!"

echo ============================================================
echo   Publish to code-marketplace
echo ============================================================
echo   Target: !GALLERY_URL!/upload
echo.

set "FILECOUNT=0"
set "OKCOUNT=0"
set "ANYARG=%~1"

REM ----------------------------------------------------------------
REM Decide what to publish.
REM ----------------------------------------------------------------
if not defined ANYARG goto publish_cwd

REM Directory argument?
if exist "!ANYARG!\*.vsix" (
    call :publish_dir "!ANYARG!"
    goto done
)

REM Otherwise treat all remaining args as individual VSIX files.
:file_loop
if "%~1"=="" goto done
call :publish_one "%~1"
shift
goto file_loop

:publish_cwd
for %%F in (*.vsix) do (
    call :publish_one "%%F"
)
goto done

:publish_dir
for %%F in ("%~1\*.vsix") do (
    call :publish_one "%%F"
)
goto :eof

:done
echo ============================================================
if !FILECOUNT! equ 0 (
    echo   No VSIX files found.
) else (
    echo   Done: !OKCOUNT!/!FILECOUNT! uploaded and registered.
)
echo ============================================================
exit /b 0


REM ----------------------------------------------------------------
REM Upload a single VSIX file via HTTPS POST /upload.
REM ----------------------------------------------------------------
:publish_one
set "VSIX=%~1"
set "FNAME=%~nx1"

echo Publishing: !FNAME!
set /a FILECOUNT+=1

curl -k -s -m 600 ^
    -X POST ^
    -H "X-Upload-Token: !UPLOAD_TOKEN!" ^
    -F "file=@!VSIX!" ^
    "!GALLERY_URL!/upload" > "%TEMP%\lambda_upload_resp.txt" 2>&1

findstr /C:"\"status\":\"ok\"" "%TEMP%\lambda_upload_resp.txt" >nul 2>&1
if !errorlevel! equ 0 (
    echo   [OK] Registered
    set /a OKCOUNT+=1
) else (
    echo   [FAIL] Upload failed
    type "%TEMP%\lambda_upload_resp.txt"
)
del "%TEMP%\lambda_upload_resp.txt" >nul 2>&1
echo.
exit /b 0
