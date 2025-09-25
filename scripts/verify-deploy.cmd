@echo off
REM =====================================================================
REM verify-deploy.cmd — Live-progress verification (env-aware, robust)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0\.."

set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"
set "PS=powershell -NoLogo -NoProfile -Command"

REM defaults
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"
set "MINIO_PORT=9000"
set "MINIO_CONSOLE_PORT=9001"
set "POSTGRES_PORT=5432"
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "REDIS_PORT=6379"

if exist "%ENV_FILE%" (
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

set "OS=%OPENSEARCH_PORT%"
set "OSD=%OPENSEARCH_DASHBOARDS_PORT%"
set "MINIO=%MINIO_PORT%"
set "MINIOC=%MINIO_CONSOLE_PORT%"

set PASS=0
set FAIL=0

echo === KWVE Logger Transcriptions — Verification (env-aware) ===
echo Compose: %COMPOSE_FILE%   Env: %ENV_FILE%
echo.

REM 1) Containers
echo [1] Checking containers...
for %%C in (kwve_pg kwve_os kwve_os_dash kwve_minio kwve_redis) do (
  docker ps --filter "name=^%%C$" --format "{{.Names}}" | findstr /I /X "%%C" >nul && (
    echo [PASS] Container up: %%C
    set /a PASS+=1
  ) || (
    echo [FAIL] Container missing: %%C
    set /a FAIL+=1
  )
)

REM helper to wait with PS
set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\"

REM 2) HTTP endpoints
echo [2] Checking HTTP endpoints...

REM OS accept 200/401
set "MAX=60"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OS%/').StatusCode}catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] OpenSearch HTTP 200 & set /a PASS+=1 & goto :os_ok)
  if "%CODE%"=="401" (echo [PASS] OpenSearch HTTP 401 (auth) & set /a PASS+=1 & goto :os_ok)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] OpenSearch … attempt %%i/%MAX% (status=%CODE%)
  timeout /t 2 >nul
)
echo [FAIL] OpenSearch never reached 200/401 (last=%CODE%)
set /a FAIL+=1
:os_ok

REM OSD accept 200/401/302
set "MAX=90"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OSD%/api/status').StatusCode}catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] OpenSearch Dashboards HTTP 200 & set /a PASS+=1 & goto :osd_ok)
  if "%CODE%"=="401" (echo [PASS] OpenSearch Dashboards HTTP 401 (auth) & set /a PASS+=1 & goto :osd_ok)
  if "%CODE%"=="302" (echo [PASS] OpenSearch Dashboards HTTP 302 (redirect) & set /a PASS+=1 & goto :osd_ok)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] Dashboards … attempt %%i/%MAX% (status=%CODE%)
  timeout /t 2 >nul
)
echo [FAIL] Dashboards never reached 200/401/302 (last=%CODE%)
set /a FAIL+=1
:osd_ok

REM MinIO console /ready, then /live, then API HEAD /
set "MAX=20"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%MINIOC%/minio/health/ready').StatusCode}catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] MinIO /ready 200 & set /a PASS+=1 & goto :minio_ok)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO /ready … attempt %%i/%MAX% (status=%CODE%)
  timeout /t 2 >nul
)
echo [INFO] MinIO /ready not 200; trying /live…
set "MAX=40"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%MINIOC%/minio/health/live').StatusCode}catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] MinIO /live 200 & set /a PASS+=1 & goto :minio_ok)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO /live … attempt %%i/%MAX% (status=%CODE%)
  timeout /t 2 >nul
)
echo [INFO] Falling back to S3 HEAD / on API port…
set "MAX=40"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{ (Invoke-WebRequest -UseBasicParsing -Method Head -Uri 'http://localhost:%MINIO%/').StatusCode }catch{0}"`) do set CODE=%%S
  if "%CODE%"=="200" (echo [PASS] MinIO S3 HEAD / 200 & set /a PASS+=1 & goto :minio_ok)
  if "%CODE%"=="204" (echo [PASS] MinIO S3 HEAD / 204 & set /a PASS+=1 & goto :minio_ok)
  if "%CODE%"=="301" (echo [PASS] MinIO S3 HEAD / 301 & set /a PASS+=1 & goto :minio_ok)
  if "%CODE%"=="302" (echo [PASS] MinIO S3 HEAD / 302 & set /a PASS+=1 & goto :minio_ok)
  set /a idx=%%i %% 4 & for %%z in (!idx!) do set "CH=!SP%%z!"
  echo [WAIT] MinIO S3 HEAD … attempt %%i/%MAX% (status=%CODE%)
  timeout /t 2 >nul
)
echo [FAIL] MinIO health failed (console & API)
set /a FAIL+=1
:minio_ok

REM 3) OpenSearch index/doc (single-shot report)
for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OS%/kwve-transcripts').StatusCode}catch{0}"`) do set CODE=%%S
if "%CODE%"=="200" (echo [PASS] Index exists: kwve-transcripts (200) & set /a PASS+=1) else (echo [FAIL] Index kwve-transcripts not accessible (%CODE%) & set /a FAIL+=1)

for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:%OS%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z').StatusCode}catch{0}"`) do set CODE=%%S
if "%CODE%"=="200" (echo [PASS] Sample doc present (200) & set /a PASS+=1) else (echo [FAIL] Sample doc missing (%CODE%) & set /a FAIL+=1)

REM 4) Postgres connectivity
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -c "SELECT 1;" >nul 2>&1
if errorlevel 1 (echo [FAIL] Postgres connectivity failed & set /a FAIL+=1) else (echo [PASS] Postgres connectivity OK (SELECT 1) & set /a PASS+=1)

echo.
echo === SUMMARY ===
echo PASS: %PASS%
echo FAIL: %FAIL%
echo.
if %FAIL%==0 (echo RESULT: PASS & popd & endlocal & exit /b 0) else (e
