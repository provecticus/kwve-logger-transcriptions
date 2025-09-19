@echo off
REM =====================================================================
REM verify-deploy.cmd — Minimal, robust PASS/FAIL verification (CMD-safe)
REM No multiline variables, no tokenized URL lists, no PowerShell.
REM Works from repo root or scripts\ via pushd ..
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0\.."

REM ----- locate repo root -----
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

REM ----- config -----
set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"

REM ----- defaults (overridden by infra\.env) -----
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"   REM ### CHANGED: now respected
set "MINIO_PORT=9000"
set "POSTGRES_PORT=5432"
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "REDIS_PORT=6379"

REM ----- read env safely -----
if exist "%ENV_FILE%" (
  for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_FILE%") do (
    set "K=%%~A" & set "V=%%~B"
    if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
    if /I "!K!"=="OPENSEARCH_DASHBOARDS_PORT" set "OPENSEARCH_DASHBOARDS_PORT=!V!"
    if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
    if /I "!K!"=="POSTGRES_PORT" set "POSTGRES_PORT=!V!"
    if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
    if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
    if /I "!K!"=="REDIS_PORT" set "REDIS_PORT=!V!"
  )
)

REM ----- derived URLs -----
set "OS_URL=http://localhost:%OPENSEARCH_PORT%"
set "OSD_URL=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"
set "MINIO_HEALTH=http://localhost:%MINIO_PORT%/minio/health/ready"

REM ----- index/doc -----
set "OS_INDEX=kwve-transcripts"
set "OS_DOC_ID=radio:KWVE:2025-09-04T09:00:00Z"
set "OS_DOC_URL=%OS_URL%/%OS_INDEX%/_doc/%OS_DOC_ID%"

REM ----- logging -----
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "LOGDIR=scripts\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\verify-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

set PASS_COUNT=0
set FAIL_COUNT=0

call :log "=== KWVE Verify (env-aware) ==="
call :log "OS: %OS_URL%  OSD: %OSD_URL%  MinIO: %MINIO_HEALTH%"
call :log "PG user/db/port: %POSTGRES_USER% / %POSTGRES_DB% / %POSTGRES_PORT%"

REM ----- (1) Containers -----
echo [1] Checking containers...
for %%C in (kwve_pg kwve_os kwve_os_dash kwve_minio kwve_redis) do (
  docker ps | findstr /I "%%C" >nul && (
    call :pass "Container up: %%C"
  ) || (
    call :fail "Container missing: %%C"
  )
)

REM ----- (2) HTTP endpoints -----
echo [2] Checking HTTP endpoints...
call :curl_check "OpenSearch" "%OS_URL%" 200
call :curl_check "OpenSearch Dashboards" "%OSD_URL%" 200
call :curl_check "MinIO Health" "%MINIO_HEALTH%" 200

REM ----- (3) OpenSearch index & doc -----
echo [3] Checking OpenSearch index/doc...
call :curl_code "%OS_URL%/%OS_INDEX%"
if "!_CURL_CODE!"=="200" (
  call :pass "Index exists: %OS_INDEX% (200)"
) else (
  call :fail "Index missing: %OS_INDEX% (!_CURL_CODE!)"
)

call :curl_code "%OS_DOC_URL%"
if "!_CURL_CODE!"=="200" (
  call :pass "Sample doc present (200)"
) else (
  call :fail "Sample doc missing (!_CURL_CODE!)"
)

REM ----- (4) Postgres connectivity (uses POSTGRES_DB from env) -----
echo [4] Checking Postgres connectivity...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -c "SELECT 1;" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
  call :fail "Postgres connectivity failed."
) else (
  call :pass "Postgres connectivity OK (SELECT 1)."
)

REM ----- summary -----
echo.
echo === SUMMARY ===
echo PASS: %PASS_COUNT%
echo FAIL: %FAIL_COUNT%
echo.
if %FAIL_COUNT%==0 (
  echo RESULT: PASS  (All checks successful)
  echo Logs: %LOGFILE%
  echo =============================================================
  popd & endlocal & exit /b 0
) else (
  echo RESULT: FAIL  (%FAIL_COUNT% failed)
  echo See logs: %LOGFILE%
  echo =============================================================
  popd & endlocal & exit /b 1
)

REM ----- helpers -----
:log
>>"%LOGFILE%" echo %~1
goto :eof

:pass
set /a PASS_COUNT+=1
echo [PASS] %~1
>>"%LOGFILE%" echo [PASS] %~1
goto :eof

:fail
set /a FAIL_COUNT+=1
echo [FAIL] %~1
>>"%LOGFILE%" echo [FAIL] %~1
goto :eof

:curl_code
set "_URL=%~1"
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%_URL%" 2^>^&1`) do set "_CURL_CODE=%%S"
>>"%LOGFILE%" echo curl "%_URL%" -> !_CURL_CODE!
goto :eof

:curl_check
set "_LBL=%~1"
set "_URL=%~2"
set "_EXP=%~3"
call :curl_code "%_URL%"
if "!_CURL_CODE!"=="%_EXP%" (
  call :pass "%_LBL% !_CURL_CODE!"
) else (
  call :fail "%_LBL% expected %_EXP%, got !_CURL_CODE!  (%_URL%)"
)
goto :eof
