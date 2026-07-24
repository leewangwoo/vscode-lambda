@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

echo ============================================================
echo   VS Code 설정 초기화 스크립트
echo ============================================================
echo.
echo   이 스크립트는 다음을 삭제/초기화합니다:
echo   - 설치된 사용자 확장 (Lambda 포함)
echo   - VS Code 사용자 설정 (settings.json)
echo   - VS Code 전역 상태/캐시 (globalState, extensions 캐시)
echo   - product.json 백업에서 원본 복원
echo   - 갤러리 인증서 제거
echo   - pip 설정 (devpi) 제거
echo.
echo   *** VS Code 창이 모두 닫힙니다 ***
echo.
echo   계속하려면 아무 키나 누르세요. 취소하려면 창을 닫으세요.
pause
echo.

:: ============================================================
:: 1. VS Code 완전히 종료
:: ============================================================
echo [1/7] VS Code 종료 중...
taskkill /im Code.exe /f >nul 2>&1
timeout /t 3 /nobreak >nul
taskkill /im Code.exe /f >nul 2>&1
timeout /t 2 /nobreak >nul
echo   완료
echo.

:: ============================================================
:: 2. 사용자 확장 전체 삭제
:: ============================================================
echo [2/7] 사용자 확장 삭제 중...
set "EXT_DIR=%USERPROFILE%\.vscode\extensions"
if exist "%EXT_DIR%" (
    rmdir /s /q "%EXT_DIR%" 2>nul
    echo   삭제: %EXT_DIR%
) else (
    echo   확장 폴더 없음
)
echo   완료
echo.

:: ============================================================
:: 3. VS Code 사용자 데이터/캐시 삭제
:: ============================================================
echo [3/7] VS Code 사용자 데이터 및 캐시 삭제 중...

REM 전역 상태, 캐시된 확장 정보
set "APPDATA_CODE=%APPDATA%\Code"

if exist "%APPDATA_CODE%\CachedExtensionVSIXs" (
    rmdir /s /q "%APPDATA_CODE%\CachedExtensionVSIXs" 2>nul
    echo   삭제: CachedExtensionVSIXs
)
if exist "%APPDATA_CODE%\CachedExtensions" (
    rmdir /s /q "%APPDATA_CODE%\CachedExtensions" 2>nul
    echo   삭제: CachedExtensions
)
if exist "%APPDATA_CODE%\CachedData" (
    rmdir /s /q "%APPDATA_CODE%\CachedData" 2>nul
    echo   삭제: CachedData
)
if exist "%APPDATA_CODE%\Code Cache" (
    rmdir /s /q "%APPDATA_CODE%\Code Cache" 2>nul
    echo   삭제: Code Cache
)
if exist "%APPDATA_CODE%\GPUCache" (
    rmdir /s /q "%APPDATA_CODE%\GPUCache" 2>nul
    echo   삭제: GPUCache
)

REM 사용자 설정 (settings.json) - Lambda 관련 설정 제거
if exist "%APPDATA_CODE%\User\settings.json" (
    del /f /q "%APPDATA_CODE%\User\settings.json" 2>nul
    echo   삭제: settings.json
)
echo   완료
echo.

:: ============================================================
:: 4. product.json 원본 복원
:: ============================================================
echo [4/7] product.json 원본 복원 중...
set "VSCODE_BASE=%LOCALAPPDATA%\Programs\Microsoft VS Code"
if not exist "%VSCODE_BASE%" set "VSCODE_BASE=C:\Program Files\Microsoft VS Code"

for /f "delims=" %%D in ('dir /b /ad "%VSCODE_BASE%" 2^>nul ^| findstr "^[0-9a-f]*$"') do (
    set "PRODUCT=%VSCODE_BASE%\%%D\resources\app\product.json"
    set "BAK=%VSCODE_BASE%\%%D\resources\app\product.json.bak"
    if exist "!BAK!" (
        copy /y "!BAK!" "!PRODUCT!" >nul 2>&1
        echo   복원: %%D\product.json
    )
)
echo   완료
echo.

:: ============================================================
:: 5. 갤러리 인증서 제거
:: ============================================================
echo [5/7] 갤러리 인증서 제거 중...
powershell -NoProfile -Command "Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -match '100\.252\.201\.200' } | ForEach-Object { Remove-Item -Path ('Cert:\CurrentUser\Root\' + $_.Thumbprint) -Force -ErrorAction SilentlyContinue }; Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match '100\.252\.201\.200' } | ForEach-Object { Remove-Item -Path ('Cert:\LocalMachine\Root\' + $_.Thumbprint) -Force -ErrorAction SilentlyContinue }" 2>nul
echo   완료
echo.

:: ============================================================
:: 6. pip 설정 제거 (devpi)
:: ============================================================
echo [6/7] pip 설정 제거 중...
set "PIP_INI=%APPDATA%\pip\pip.ini"
if exist "%PIP_INI%" (
    del /f /q "%PIP_INI%" 2>nul
    echo   삭제: %PIP_INI%
) else (
    echo   pip.ini 없음
)
echo   완료
echo.

:: ============================================================
:: 7. 남은 Lambda 관련 임시 파일 정리
:: ============================================================
echo [7/7] 임시 파일 정리 중...
if exist "%TEMP%\lambda-install" rmdir /s /q "%TEMP%\lambda-install" 2>nul
if exist "%TEMP%\lambda-gallery-ca.cer" del /f /q "%TEMP%\lambda-gallery-ca.cer" 2>nul
if exist "%TEMP%\lambda-upload_resp.txt" del /f /q "%TEMP%\lambda-upload_resp.txt" 2>nul
if exist "%TEMP%\vsix-download" rmdir /s /q "%TEMP%\vsix-download" 2>nul
echo   완료
echo.

:: ============================================================
:: 완료
:: ============================================================
echo ============================================================
echo   초기화 완료!
echo ============================================================
echo.
echo   VS Code가 완전히 초기화되었습니다.
echo   이제 install.bat을 처음부터 다시 실행할 수 있습니다.
echo.
pause
