@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd — bring up stack, wait, and seed (env-aware)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM --- resolve repo root (script may be run from anywhere) ---
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

REM --- files/paths ---
set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"

REM --- defaults (overridden by infra\.env) ---
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "POSTGRES_PORT=5432"
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"
set "MINIO_PORT=9000"
set "MINIO_CONSOLE_PORT=9001"
set "OPENSEARCH_USERNAME="
set "OPENSEARCH_PASSWORD="

if not exist "%ENV_FILE%" (
  echo [ERR] Missing %ENV_FILE%
  popd & endlocal & exit /b 1
)

REM --- read env safely ---
for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_FILE%") do (
  set "K=%%~A" & set "V=%%~B"
  if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
  if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
  if /I "!K!"=="POSTGRES_PORT" set "POSTGRES_PORT=!V!"
  if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
  if /I "!K!"=="OPENSEARCH_DASHBOARDS_PORT" set "OPENSEARCH_DASHBOARDS_PORT=!V!"
  if /I "!K!"=="OPENSEARCH_USERNAME" set "OPENSEARCH_USERNAME=!V!"
  if /I "!K!"=="OPENSEARCH_PASSWORD" set "OPENSEARCH_PASSWORD=!V!"
  if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
  if /I "!K!"=="MINIO_CONSOLE_PORT" set "MINIO_CONSOLE_PORT=!V!"
)

set "OS_HTTP=http://localhost:%OPENSEARCH_PORT%/"
set "OS_HTTPS=https://localhost:%OPENSEARCH_PORT%/"
set "OSD_STATUS=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"

echo [INFO] Using: PG=%POSTGRES_USER%@%POSTGRES_PORT% DB=%POSTGRES_DB%  OS=%OS_HTTP%  OSD=%OPENSEARCH_DASHBOARDS_PORT%  MinIO=%MINIO_PORT%/%MINIO_CONSOLE_PORT%

REM --- bring up stack (no pipes so errorlevel is true) ---
echo [STEP] docker compose up -d
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d
if errorlevel 1 (
  echo [ERR] compose up failed
  popd & endlocal & exit /b 1
)

REM --- short grace (JVM bind) ---
timeout /t 5 >nul

REM --- PowerShell helper ---
set "PS=powershell -NoLogo -NoProfile -Command"

REM ===== WAIT: OpenSearch (HTTP then HTTPS; accept 200/401) =====
set "MAX=180"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OS_HTTP%').StatusCode}catch{0}"`) do set CODE_HTTP=%%S
  if "%CODE_HTTP%"=="200"  (echo [OK ] OpenSearch HTTP 200 & goto :os_ready)
  if "%CODE_HTTP%"=="401"  (echo [OK ] OpenSearch HTTP 401 (auth) & goto :os_ready)

  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OS_HTTPS%').StatusCode}catch{0}"`) do set CODE_HTTPS=%%S
  if "%CODE_HTTPS%"=="200" (echo [OK ] OpenSearch HTTPS 200 & goto :os_ready)
  if "%CODE_HTTPS%"=="401" (echo [OK ] OpenSearch HTTPS 401 (auth) & goto :os_ready)

  echo [WAIT] OpenSearch … attempt %%i/%MAX% (http=%CODE_HTTP% https=%CODE_HTTPS%)
  timeout /t 2 >nul
)
echo [FAIL] OpenSearch not ready (http=%CODE_HTTP% https=%CODE_HTTPS%)
goto :abort
:os_ready

REM ===== WAIT: Dashboards (accept 200/401/302) =====
set "MAX=180"
for /l %%i in (1,1,%MAX%) do (
  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OSD_STATUS%').StatusCode}catch{0}"`) do set CODE_OSD=%%S
  if "%CODE_OSD%"=="200" (echo [OK ] Dashboards HTTP 200 & goto :osd_ready)
  if "%CODE_OSD%"=="401" (echo [OK ] Dashboards HTTP 401 (auth) & goto :osd_ready)
  if "%CODE_OSD%"=="302" (echo [OK ] Dashboards HTTP 302 (redirect) & goto :osd_ready)
  echo [WAIT] Dashboards … attempt %%i/%MAX% (status=%CODE_OSD%)
  timeout /t 2 >nul
)
echo [WARN] Dashboards never returned 200/401/302 (last=%CODE_OSD%). Continuing…
:osd_ready

REM ===== SEED: Postgres =====
echo [STEP] Seeding Postgres (schema + sample)…
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql

REM ===== SEED: OpenSearch (template + index + sample doc) =====
echo [STEP] Seeding OpenSearch (template + index + sample doc)…
set "TPL=sql\opensearch_index_template.json"
if not exist "%TPL%" set "TPL=infra\opensearch_index_template.json"

if exist "%TPL%" (
  for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -Uri '%OS_HTTP%_index_template/kwve-transcripts-template' -Method Put -ContentType 'application/json' -InFile '%TPL%').StatusCode}catch{ $_.Exception.Response.StatusCode.Value__ }"`) do set CODE_TPL=%%S
  if "%CODE_TPL%"=="200" (echo [PASS] Template applied (200)) else if "%CODE_TPL%"=="201" (echo [PASS] Template created (201)) else (echo [WARN] Template HTTP %CODE_TPL%)
) else (
  echo [WARN] No index template json found (sql\ or infra\)
)

for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -Uri '%OS_HTTP%kwve-transcripts' -Method Put).StatusCode}catch{ $_.Exception.Response.StatusCode.Value__ }"`) do set CODE_IDX=%%S
if "%CODE_IDX%"=="200" (echo [PASS] Index ok (200)) ^
else if "%CODE_IDX%"=="201" (echo [PASS] Index created (201)) ^
else if "%CODE_IDX%"=="400" (echo [PASS] Index already exists (400)) ^
else if "%CODE_IDX%"=="409" (echo [PASS] Index already exists (409)) ^
else (echo [WARN] Index create HTTP %CODE_IDX%)

set "SAMPLE=sample-data\radio\2025-09-04\2025-09-04T09-00-00Z.sample-transcript.json"
if exist "%SAMPLE%" (
  for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -Uri '%OS_HTTP%kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z' -Method Post -ContentType 'application/json' -InFile '%SAMPLE%').StatusCode}catch{ $_.Exception.Response.StatusCode.Value__ }"`) do set CODE_DOC=%%S
  if "%CODE_DOC%"=="200" (echo [PASS] Sample doc inserted (200)) ^
  else if "%CODE_DOC%"=="201" (echo [PASS] Sample doc created (201)) ^
  else (
    echo [INFO] Doc insert HTTP %CODE_DOC% — retrying…
    timeout /t 2 >nul
    for /f "usebackq delims=" %%S in (`%PS% "$p='SilentlyContinue'; $ProgressPreference=$p; try{(Invoke-WebRequest -Uri '%OS_HTTP%kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z' -Method Post -ContentType 'application/json' -InFile '%SAMPLE%').StatusCode}catch{ $_.Exception.Response.StatusCode.Value__ }"`) do set CODE_DOC2=%%S
    if "%CODE_DOC2%"=="200" (echo [PASS] Sample doc inserted (200)) ^
    else if "%CODE_DOC2%"=="201" (echo [PASS] Sample doc created (201)) ^
    else (echo [WARN] Doc insert still HTTP %CODE_DOC2%)
  )
) else (
  echo [WARN] Sample not found at %SAMPLE%
)

echo [DONE] Bootstrap complete.
popd & endlocal & exit /b 0

:abort
echo [ABORT] Bootstrap failed due to readiness or init error.
popd & endlocal & exit /b 1
