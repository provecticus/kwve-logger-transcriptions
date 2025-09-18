@echo off
REM =====================================================================
REM verify-deploy.cmd — Minimal, robust PASS/FAIL verification (CMD-safe)
REM No multiline variables, no tokenized URL lists, no PowerShell.
REM Works from repo root or scripts\ via pushd ..
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM ----- locate repo root -----
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

REM ----- config -----
set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"

set "REQ1=kwve_pg"
set "REQ2=kwve_os"
set "REQ3=kwve_os_dash"
set "REQ4=kwve_minio"
set "REQ5=kwve_redis"

set "OS_URL=http://localhost:9200"
set "OSD_URL=http://localhost:5601/api/status"
set "MINIO_HEALTH=http://localhost:9000/minio/health/ready"

set "OS_INDEX=kwve-transcripts"
set "OS_DOC_ID=radio:KWVE:2025-09-04T09:00:00Z"
set "OS_DOC_URL=http://localhost:9200/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z"

set "PG_CMD=SELECT 1;"

REM ----- logging -----
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "LOGDIR=logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\verify-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

set PASS_COUNT=0
set FAIL_COUNT=0

call :log "=== KWVE Logger Transcriptions — Verification Started ==="
call :log "Compose: %COMPOSE_FILE%   Env: %ENV_FILE%"
call :log "CWD: %CD%"
call :log ""

REM ----- sanity -----
if not exist "%COMPOSE_FILE%" call :fail "Missing %COMPOSE_FILE%"
if not exist "%ENV_FILE%" call :fail "Missing %ENV_FILE% (copy infra\.env.example -> infra\.env)"

REM ----- (1) containers -----
call :log "[1] Checking containers..."
for /f "delims=" %%N in ('docker ps --format "{{.Names}}"') do (
  >>"%LOGFILE%" echo CONTAINER: %%N
  if /I "%%N"=="%REQ1%" set FOUND1=1
  if /I "%%N"=="%REQ2%" set FOUND2=1
  if /I "%%N"=="%REQ3%" set FOUND3=1
  if /I "%%N"=="%REQ4%" set FOUND4=1
  if /I "%%N"=="%REQ5%" set FOUND5=1
)
if "%FOUND1%"=="1" (call :pass "Container up: %REQ1%") else (call :fail "Missing: %REQ1%")
if "%FOUND2%"=="1" (call :pass "Container up: %REQ2%") else (call :fail "Missing: %REQ2%")
if "%FOUND3%"=="1" (call :pass "Container up: %REQ3%") else (call :fail "Missing: %REQ3%")
if "%FOUND4%"=="1" (call :pass "Container up: %REQ4%") else (call :fail "Missing: %REQ4%")
if "%FOUND5%"=="1" (call :pass "Container up: %REQ5%") else (call :fail "Missing: %REQ5%")

REM ----- (2) HTTP endpoints (explicit, one by one) -----
call :log ""
call :log "[2] Checking HTTP endpoints..."
call :curl_check "OpenSearch" "%OS_URL%" 200
call :curl_check "OpenSearch Dashboards" "%OSD_URL%" 200
call :curl_check "MinIO Health" "%MINIO_HEALTH%" 200

REM ----- (3) OpenSearch index & doc -----
call :log ""
call :log "[3] Checking OpenSearch index & sample doc..."
call :curl_code "http://localhost:9200/%OS_INDEX%"
if "!_CURL_CODE!"=="200" ( call :pass "Index exists: %OS_INDEX% (200)" ) else ( call :fail "Index missing: %OS_INDEX% (! _CURL_CODE !)" )
call :curl_code "%OS_DOC_URL%"
if "!_CURL_CODE!"=="200" ( call :pass "Sample doc present: %OS_DOC_ID% (200)" ) else ( call :fail "Sample doc missing: %OS_DOC_ID% (! _CURL_CODE !)" )

REM ----- (4) Postgres connectivity -----
call :log ""
call :log "[4] Checking Postgres connectivity..."
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U kwve -d kwve -c "%PG_CMD%" >> "%LOGFILE%" 2>&1
if errorlevel 1 ( call :fail "Postgres connectivity failed." ) else ( call :pass "Postgres connectivity OK (SELECT 1)." )

REM ----- summary -----
call :log ""
call :log "=== SUMMARY ==="
call :log "PASS: %PASS_COUNT%"
call :log "FAIL: %FAIL_COUNT%"
echo.
echo ===================== VERIFICATION RESULT =====================
if %FAIL_COUNT%==0 (
  echo RESULT: PASS  (All checks successful)
  echo Logs: %LOGFILE%
  echo =============================================================
  popd
  endlocal & exit /b 0
) else (
  echo RESULT: FAIL  (%FAIL_COUNT% check(s) failed)
  echo See logs: %LOGFILE%
  echo =============================================================
  popd
  endlocal & exit /b 1
)

:log
echo %~1
>>"%LOGFILE%" echo %~1
goto :eof

:pass
set /a PASS_COUNT+=1
call :log "[PASS] %~1"
goto :eof

:fail
set /a FAIL_COUNT+=1
call :log "[FAIL] %~1"
goto :eof

:curl_code
REM arg: URL -> sets _CURL_CODE to HTTP status or 0 on failure
set "_URL=%~1"
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%_URL%" 2^>^&1`) do set "_CURL_CODE=%%S"
>>"%LOGFILE%" echo curl "%_URL%" -> !_CURL_CODE!
goto :eof

:curl_check
REM args: LABEL, URL, EXPECT_CODE
set "_LBL=%~1"
set "_URL=%~2"
set "_EXP=%~3"
call :curl_code "%_URL%"
if "%_EXP%"=="!_CURL_CODE!" ( call :pass "%_LBL% !_CURL_CODE!" ) else ( call :fail "%_LBL% expected %_EXP%, got !_CURL_CODE!  (%_URL%)" )
goto :eof
