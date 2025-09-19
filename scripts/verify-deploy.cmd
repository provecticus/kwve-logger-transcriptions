
@echo off
REM =====================================================================
REM verify-deploy.cmd — Live-progress verification (env-aware, robust)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0\.."

set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"

REM defaults (overridden by env)
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"
set "MINIO_PORT=9000"
set "POSTGRES_PORT=5432"
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "REDIS_PORT=6379"

set "OPENSEARCH_USERNAME="
set "OPENSEARCH_PASSWORD="

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
    if /I "!K!"=="OPENSEARCH_USERNAME" set "OPENSEARCH_USERNAME=!V!"
    if /I "!K!"=="OPENSEARCH_PASSWORD" set "OPENSEARCH_PASSWORD=!V!"
  )
)

set "OS_URL=http://localhost:%OPENSEARCH_PORT%"
set "OSD_URL=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"
set "MINIO_HEALTH=http://localhost:%MINIO_PORT%/minio/health/ready"
set "OS_INDEX_URL=%OS_URL%/kwve-transcripts"
set "OS_DOC_URL=%OS_URL%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z"

set "OS_AUTH="
if defined OPENSEARCH_USERNAME if defined OPENSEARCH_PASSWORD (
  set "OS_AUTH=-u %OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%"
)

for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "LOGDIR=scripts\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\verify-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

set PASS_COUNT=0
set FAIL_COUNT=0

set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\\"

echo === KWVE Logger Transcriptions — Verification (env-aware) ===
echo Compose: %COMPOSE_FILE%   Env: %ENV_FILE%
echo Logs: %LOGFILE%
echo.

call :log "=== Verify Start ==="
call :log "OS=%OS_URL%  OSD=%OSD_URL%  MINIO=%MINIO_HEALTH%"
call :log "PG user/db/port: %POSTGRES_USER% / %POSTGRES_DB% / %POSTGRES_PORT%"

REM ----- (1) Containers -----
echo [1] Checking containers...
call :container_up kwve_pg
call :container_up kwve_os
call :container_up kwve_os_dash
call :container_up kwve_minio
call :container_up kwve_redis

REM ----- (2) HTTP endpoints with live progress -----
echo [2] Checking HTTP endpoints...
call :wait_http "OpenSearch" "%OS_URL%/" "200,401" 60 2
call :wait_http "OpenSearch Dashboards" "%OSD_URL%" "200,401,302" 90 2
call :wait_http "MinIO Health" "%MINIO_HEALTH%" "200" 60 2

REM ----- (3) OpenSearch index & doc -----
echo [3] Checking OpenSearch index/doc...
call :curl_code "%OS_INDEX_URL%"
if "!_CURL_CODE!"=="200" (
  call :pass "Index exists: kwve-transcripts (200)"
) else (
  call :fail "Index missing or not accessible: kwve-transcripts (!_CURL_CODE!)"
)
call :curl_code "%OS_DOC_URL%"
if "!_CURL_CODE!"=="200" (
  call :pass "Sample doc present (200)"
) else (
  call :fail "Sample doc missing (!_CURL_CODE!)"
)

REM ----- (4) Postgres connectivity -----
echo [4] Checking Postgres connectivity...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -c "SELECT 1;" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
  call :fail "Postgres connectivity failed."
) else (
  call :pass "Postgres connectivity OK (SELECT 1)."
)

echo.
echo === SUMMARY ===
echo PASS: %PASS_COUNT%
echo FAIL: %FAIL_COUNT%
echo.
if %FAIL_COUNT%==0 (
  echo RESULT: PASS  (All checks successful)
  echo Logs: %LOGFILE%
  popd & endlocal & exit /b 0
) else (
  echo RESULT: FAIL  (%FAIL_COUNT% failed)
  echo See logs: %LOGFILE%
  popd & endlocal & exit /b 1
)

REM ===========================
REM Helpers
REM ===========================
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
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" %OS_AUTH% "%_URL%" 2^>^&1`) do set "_CURL_CODE=%%S"
>>"%LOGFILE%" echo curl "%_URL%" -> !_CURL_CODE!
goto :eof

:container_up
set "_NAME=%~1"
for /f "usebackq delims=" %%N in (`docker ps --filter "name=^%_NAME%$" --format "{{.Names}}"`) do set "_FOUND=%%N"
if defined _FOUND (
  call :pass "Container up: %_NAME%"
) else (
  call :fail "Container missing: %_NAME%"
)
set "_FOUND="
goto :eof

REM Live wait: acceptable codes list (e.g., "200,401")
:wait_http
set "_LBL=%~1"
set "_URL=%~2"
set "_ACCEPT=%~3"
set "_MAX=%~4"
set "_SLEEP=%~5"
set "_TRY=0"
echo [WAIT] %_LBL% at %_URL%
:wait_http_loop
set /a IDX=_TRY %% 4
for %%z in (!IDX!) do (
  set "SPIN0=|"
  set "SPIN1=/"
  set "SPIN2=-"
  set "SPIN3=\\"
  for %%q in (!IDX!) do set "CH=!SPIN%%q!"
)
set "CODE="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" %OS_AUTH% "%_URL%" 2^>^&1`) do set "CODE=%%S"
<nul set /p "=  [!CH!] %_LBL% http=!CODE! (try !_TRY!/!_MAX!)   `r"
echo ,%_ACCEPT%, | findstr /C:",!CODE!," >nul
if not errorlevel 1 (
  echo.
  call :pass "%_LBL% HTTP !CODE!"
  goto :eof
)
set /a _TRY+=1
if !_TRY! GEQ !_MAX! (
  echo.
  call :fail "%_LBL% expected one of {%_ACCEPT%}, got !CODE!  (%_URL%)"
  goto :eof
)
timeout /t %_SLEEP% >nul
goto :wait_http_loop
