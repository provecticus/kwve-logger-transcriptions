@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd - bring up stack, wait, and seed (env-aware)
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
set "PS=powershell -NoLogo -NoProfile -Command"
echo [WAIT] OpenSearch at %OS_HTTP%
for /l %%I in (1,1,%MAX%) do (
  set "CODE_HTTP="
  set "CODE_HTTPS="

  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OS_HTTP%').StatusCode}catch{0}"`) do set "CODE_HTTP=%%S"
  set "CODE_HTTP=!CODE_HTTP: =!"
  if "!CODE_HTTP!"=="200"  (echo [OK ] OpenSearch HTTP 200 & goto :os_ready)
  if "!CODE_HTTP!"=="401"  (echo [OK ] OpenSearch HTTP 401 (auth) & goto :os_ready)

  for /f "usebackq delims=" %%S in (`%PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OS_HTTPS%').StatusCode}catch{0}"`) do set "CODE_HTTPS=%%S"
  set "CODE_HTTPS=!CODE_HTTPS: =!"
  if "!CODE_HTTPS!"=="200" (echo [OK ] OpenSearch HTTPS 200 & goto :os_ready)
  if "!CODE_HTTPS!"=="401" (echo [OK ] OpenSearch HTTPS 401 (auth) & goto :os_ready)

  echo [WAIT] OpenSearch ... status http=!CODE_HTTP! https=!CODE_HTTPS!  (try %%I/%MAX%)
  timeout /t 2 >nul
)
echo [FAIL] OpenSearch not ready (http=!CODE_HTTP! https=!CODE_HTTPS!)
goto :abort
:os_ready



REM ===== WAIT: OpenSearch Dashboards (accept 200/401/302) =====
set "MAX=180"
if not defined PS set "PS=powershell -NoLogo -NoProfile -Command"
echo [WAIT] OpenSearch Dashboards at %OSD_STATUS%
for /l %%I in (1,1,%MAX%) do (
  set "CODE_OSD="
  for /f "usebackq delims=" %%S in (`
    %PS% "$ProgressPreference='SilentlyContinue'; try{(Invoke-WebRequest -UseBasicParsing -Uri '%OSD_STATUS%').StatusCode}catch{0}"
  `) do set "CODE_OSD=%%S"

  REM trim any stray spaces just in case
  set "CODE_OSD=!CODE_OSD: =!"

  if "!CODE_OSD!"=="200"  (echo [OK ] Dashboards HTTP 200 & goto :osd_ready)
  if "!CODE_OSD!"=="401"  (echo [OK ] Dashboards HTTP 401 (auth) & goto :osd_ready)
  if "!CODE_OSD!"=="302"  (echo [OK ] Dashboards HTTP 302 (redirect) & goto :osd_ready)

  echo [WAIT] Dashboards status=!CODE_OSD!  (try %%I/%MAX%)
  timeout /t 2 >nul
)
echo [WARN] Dashboards never returned 200/401/302 (last=!CODE_OSD!). Continuing...
:osd_ready



REM ===== SEED: Postgres =====
echo [STEP] Seeding Postgres (schema + sample)...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql



REM ===== SEED: OpenSearch (template + index + sample doc; PowerShell body) =====
REM ===== SEED: OpenSearch via PowerShell (no @file paths) =====
echo [STEP] Seeding OpenSearch (template + index + sample doc)...

REM Pin repo root to the script’s folder
set "REPO=%~dp0.."
for %%R in ("%REPO%") do set "REPO=%%~fR"

REM Compute absolute template & sample paths (both optional)
set "TPL_ABS=%REPO%\sql\opensearch_index_template.json"
if not exist "%TPL_ABS%" set "TPL_ABS=%REPO%\infra\opensearch_index_template.json"
set "SAMPLE_ABS=%REPO%\sample-data\radio\2025-09-04\2025-09-04T09-00-00Z.sample-transcript.json"

echo [DEBUG] TPL_ABS="%TPL_ABS%"
echo [DEBUG] SAMPLE_ABS="%SAMPLE_ABS%"

REM Call the PS seeder (ExecutionPolicy bypass to avoid policy prompts)
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "scripts\seed-os.ps1" ^
  -OsBaseUrl "http://localhost:%OPENSEARCH_PORT%" ^
  -IndexName "kwve-transcripts" ^
  -TemplatePath "%TPL_ABS%" ^
  -SamplePath "%SAMPLE_ABS%"






echo [DONE] Bootstrap complete.
popd & endlocal & exit /b 0

:abort
echo [ABORT] Bootstrap failed due to readiness or init error.
popd & endlocal & exit /b 1
