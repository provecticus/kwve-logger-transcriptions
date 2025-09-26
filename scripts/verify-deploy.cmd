@echo off
REM =====================================================================
REM verify-deploy.cmd - Live-progress verification (env-aware, robust)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0\.."

set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"
set "PS=powershell -NoLogo -NoProfile -Command"

REM --- defaults (overridden by env) ---
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"
set "MINIO_PORT=9000"
set "MINIO_CONSOLE_PORT=9001"
set "POSTGRES_PORT=5432"
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "REDIS_PORT=6379"

IF EXIST "%ENV_FILE%" (
  for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_FILE%") do (
    set "K=%%~A" & set "V=%%~B"
    if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
    if /I "!K!"=="OPENSEARCH_DASHBOARDS_PORT" set "OPENSEARCH_DASHBOARDS_PORT=!V!"
    if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
    if /I "!K!"=="MINIO_CONSOLE_PORT" set "MINIO_CONSOLE_PORT=!V!"
    if /I "!K!"=="POSTGRES_PORT" set "POSTGRES_PORT=!V!"
    if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
    if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
    if /I "!K!"=="REDIS_PORT" set "REDIS_PORT=!V!"
  )
)

REM --- URLs derived from env ---
set "OS_URL=http://localhost:%OPENSEARCH_PORT%/"
set "OSD_URL=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"
IF NOT DEFINED MINIO_CONSOLE_PORT set "MINIO_CONSOLE_PORT=%MINIO_PORT%"
set "MINIO_READY=http://localhost:%MINIO_CONSOLE_PORT%/minio/health/ready"
set "MINIO_LIVE=http://localhost:%MINIO_CONSOLE_PORT%/minio/health/live"

REM --- logging (create log file) ---
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "LOGDIR=scripts\logs"
IF NOT EXIST "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\verify-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

REM --- counters and spinner ---
set PASS=0
set FAIL=0
set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\"

echo === KWVE Logger Transcriptions - Verification (env-aware) ===
echo Compose: %COMPOSE_FILE%   Env: %ENV_FILE%
echo Logs: %LOGFILE%
echo.

>>"%LOGFILE%" echo === Verify Start ===
>>"%LOGFILE%" echo OS=%OS_URL%  OSD=%OSD_URL%  MINIO_CONSOLE=http://localhost:%MINIO_CONSOLE_PORT%/
>>"%LOGFILE%" echo PG %POSTGRES_DB%@%POSTGRES_PORT%

REM =====================================================================
REM 1) Containers
REM =====================================================================
echo [1] Checking containers...
for %%C in (kwve_pg kwve_os kwve_os_dash kwve_minio kwve_redis) do (
  docker ps --filter "name=^%%C$" --format "{{.Names}}" | findstr /I /X "%%C" >nul && (
    echo [PASS] Container up: %%C
    >>"%LOGFILE%" echo CONTAINER %%C OK
    set /a PASS+=1
  ) || (
    echo [FAIL] Container missing: %%C
    >>"%LOGFILE%" echo CONTAINER %%C MISSING
    set /a FAIL+=1
  )
)

REM =====================================================================
REM helper: GET status code via PowerShell
REM =====================================================================
REM sets CODE to numeric status (0 on error)
:HTTP_STATUS
set "URL=%~1"
for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%URL%').StatusCode}catch{0}"`) do set CODE=%%S
goto :eof

REM =====================================================================
REM 2) HTTP endpoints (OS, OSD, MinIO)
REM =====================================================================
echo [2] Checking HTTP endpoints...

REM ---- OpenSearch (accept 200/401) ----
set "MAX=60"
for /l %%i in (1,1,%MAX%) do (
  call :HTTP_STATUS "%OS_URL%"
  if "%CODE%"=="200" (echo [PASS] OpenSearch HTTP 200 & >>"%LOGFILE%" echo OS try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :OS_DONE)
  if "%CODE%"=="401" (echo [PASS] OpenSearch HTTP 401 (auth) & >>"%LOGFILE%" echo OS try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :OS_DONE)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] OpenSearch ... attempt %%i/%MAX% (status=%CODE%)
  >>"%LOGFILE%" echo OS try %%i/%MAX% status %CODE%
  timeout /t 2 >nul
)
echo [FAIL] OpenSearch never reached 200/401 (last=%CODE%)
>>"%LOGFILE%" echo OS FAIL last %CODE%
set /a FAIL+=1
:OS_DONE

REM ---- Dashboards (accept 200/401/302) ----
set "MAX=90"
for /l %%i in (1,1,%MAX%) do (
  call :HTTP_STATUS "%OSD_URL%"
  if "%CODE%"=="200" (echo [PASS] OpenSearch Dashboards HTTP 200 & >>"%LOGFILE%" echo OSD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :OSD_DONE)
  if "%CODE%"=="401" (echo [PASS] OpenSearch Dashboards HTTP 401 (auth) & >>"%LOGFILE%" echo OSD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :OSD_DONE)
  if "%CODE%"=="302" (echo [PASS] OpenSearch Dashboards HTTP 302 (redirect) & >>"%LOGFILE%" echo OSD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :OSD_DONE)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] OpenSearch Dashboards ... attempt %%i/%MAX% (status=%CODE%)
  >>"%LOGFILE%" echo OSD try %%i/%MAX% status %CODE%
  timeout /t 2 >nul
)
echo [FAIL] Dashboards never reached 200/401/302 (last=%CODE%)
>>"%LOGFILE%" echo OSD FAIL last %CODE%
set /a FAIL+=1
:OSD_DONE

REM ---- MinIO console /ready then /live, fallback S3 HEAD on API ----
set "MAX=20"
for /l %%i in (1,1,%MAX%) do (
  call :HTTP_STATUS "%MINIO_READY%"
  if "%CODE%"=="200" (echo [PASS] MinIO /ready 200 & >>"%LOGFILE%" echo MINIO /ready try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO /ready ... attempt %%i/%MAX% (status=%CODE%)
  >>"%LOGFILE%" echo MINIO /ready try %%i/%MAX% status %CODE%
  timeout /t 2 >nul
)
echo [INFO] MinIO /ready not 200; trying /live...
>>"%LOGFILE%" echo MINIO /ready failed last %CODE% then /live

set "MAX=40"
for /l %%i in (1,1,%MAX%) do (
  call :HTTP_STATUS "%MINIO_LIVE%"
  if "%CODE%"=="200" (echo [PASS] MinIO /live 200 & >>"%LOGFILE%" echo MINIO /live try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO /live ... attempt %%i/%MAX% (status=%CODE%)
  >>"%LOGFILE%" echo MINIO /live try %%i/%MAX% status %CODE%
  timeout /t 2 >nul
)
echo [INFO] Falling back to S3 HEAD / on API port...
>>"%LOGFILE%" echo MINIO falling back to S3 HEAD

set "MAX=40"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{ (Invoke-WebRequest -UseBasicParsing -Method Head -Uri 'http://localhost:%MINIO%/').StatusCode }catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] MinIO S3 HEAD / 200 & >>"%LOGFILE%" echo MINIO S3 HEAD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  if "%CODE%"=="204" (echo [PASS] MinIO S3 HEAD / 204 & >>"%LOGFILE%" echo MINIO S3 HEAD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  if "%CODE%"=="301" (echo [PASS] MinIO S3 HEAD / 301 & >>"%LOGFILE%" echo MINIO S3 HEAD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  if "%CODE%"=="302" (echo [PASS] MinIO S3 HEAD / 302 & >>"%LOGFILE%" echo MINIO S3 HEAD try %%i/%MAX% status %CODE% & set /a PASS+=1 & goto :MINIO_DONE)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO S3 HEAD ... attempt %%i/%MAX% (status=%CODE%)
  >>"%LOGFILE%" echo MINIO S3 HEAD try %%i/%MAX% status %CODE%
  timeout /t 2 >nul
)
echo [FAIL] MinIO health failed (console & API)
>>"%LOGFILE%" echo MINIO FAIL last %CODE%
set /a FAIL+=1
:MINIO_DONE

REM =====================================================================
REM 3) OpenSearch index/doc (single-shot report)
REM =====================================================================
for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OPENSEARCH_PORT%/kwve-transcripts').StatusCode}catch{0}"`) do set CODE=%%S
if "%CODE%"=="200" (
  echo [PASS] Index exists: kwve-transcripts (200)
  >>"%LOGFILE%" echo INDEX status %CODE%
  set /a PASS+=1
) else (
  echo [FAIL] Index kwve-transcripts not accessible (%CODE%)
  >>"%LOGFILE%" echo INDEX FAIL %CODE%
  set /a FAIL+=1
)

for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OPENSEARCH_PORT%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z').StatusCode}catch{0}"`) do set CODE=%%S
if "%CODE%"=="200" (
  echo [PASS] Sample doc present (200)
  >>"%LOGFILE%" echo DOc status %CODE%
  set /a PASS+=1
) else (
  echo [FAIL] Sample doc missing (%CODE%)
  >>"%LOGFILE%" echo DOC FAIL %CODE%
  set /a FAIL+=1
)

REM =====================================================================
REM 4) Postgres connectivity
REM =====================================================================
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -c "SELECT 1;" >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Postgres connectivity failed
  >>"%LOGFILE%" echo PG FAIL
  set /a FAIL+=1
) else (
  echo [PASS] Postgres connectivity OK (SELECT 1)
  >>"%LOGFILE%" echo PG OK
  set /a PASS+=1
)

echo.
echo === SUMMARY ===
echo PASS: %PASS%
echo FAIL: %FAIL%
>>"%LOGFILE%" echo PASS=%PASS% FAIL=%FAIL%
echo.

if %FAIL%==0 (
  echo RESULT: PASS
  popd & endlocal & exit /b 0
) else (
  echo RESULT: FAIL
  popd & endlocal & exit /b 1
)
