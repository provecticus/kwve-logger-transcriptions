
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
set "LOGDIR=scripts\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "BOOTLOG=%LOGDIR%\bootstrap-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

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

REM --- read infra\.env safely (ignore comments/blank) ---
if not exist "%ENV_FILE%" (
  echo [ERR] Missing %ENV_FILE%
  popd & endlocal & exit /b 1
)
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

set "OS_URL=http://localhost:%OPENSEARCH_PORT%"
set "OSD_STATUS=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"
set "MINIO_HEALTH=http://localhost:%MINIO_PORT%/minio/health/ready"

REM optional auth for OS when security is enabled
set "OS_AUTH="
if defined OPENSEARCH_USERNAME if defined OPENSEARCH_PASSWORD (
  set "OS_AUTH=-u %OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%"
)

REM spinner glyphs
set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\\"

echo [INFO] Using: PG=%POSTGRES_USER%@%POSTGRES_PORT% DB=%POSTGRES_DB%  OS=%OS_URL%  OSD=%OPENSEARCH_DASHBOARDS_PORT%  MinIO=%MINIO_PORT%
echo [STEP] docker compose up -d

REM dual-output: prefer tee.exe if available
where tee >nul 2>&1
if %errorlevel%==0 (
  docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d 2>&1 | tee -a "%BOOTLOG%"
) else (
  docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d >> "%BOOTLOG%" 2>&1
)

if errorlevel 1 (
  echo [ERR] compose up failed
  popd & endlocal & exit /b 1
)

REM --- WAIT: OpenSearch ---
set "TRIES=0"
set "MAX_TRIES_OS=60"
set "SLEEP=2"
echo [WAIT] OpenSearch at %OS_URL% ...
:wait_os
set /a IDX=TRIES %% 4
for %%z in (!IDX!) do set "CH=!SP%%z!"
set "CODE_OS="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" %OS_AUTH% "%OS_URL%/" 2^>^&1`) do set "CODE_OS=%%S"
<nul set /p "=  [!CH!] OS http=!CODE_OS! (try !TRIES!/!MAX_TRIES_OS!)   `r"
if "!CODE_OS!"=="200" (
  echo.
  echo [OK ] OpenSearch HTTP 200
  goto :os_ready
)
set /a TRIES+=1
if !TRIES! GEQ !MAX_TRIES_OS! (
  echo.
  echo [FAIL] OpenSearch not ready (last=!CODE_OS!)
  goto :abort
)
timeout /t !SLEEP! >nul
goto :wait_os
:os_ready

REM --- WAIT: Dashboards (accept 200/401/302) ---
set "TRIES=0"
set "MAX_TRIES_OSD=90"
echo [WAIT] OpenSearch Dashboards at %OSD_STATUS% ...
:wait_osd
set /a IDX=TRIES %% 4
for %%z in (!IDX!) do set "CH=!SP%%z!"
set "CODE_OSD="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OSD_STATUS%" 2^>^&1`) do set "CODE_OSD=%%S"
<nul set /p "=  [!CH!] OSD http=!CODE_OSD! (try !TRIES!/!MAX_TRIES_OSD!)   `r"
if "!CODE_OSD!"=="200" (echo. & echo [OK ] Dashboards HTTP 200 & goto :osd_ready)
if "!CODE_OSD!"=="401" (echo. & echo [OK ] Dashboards HTTP 401 (auth) & goto :osd_ready)
if "!CODE_OSD!"=="302" (echo. & echo [OK ] Dashboards HTTP 302 (redirect) & goto :osd_ready)
set /a TRIES+=1
if !TRIES! GEQ !MAX_TRIES_OSD! (
  echo.
  echo [WARN] Dashboards did not return 200/401/302 in time (last=!CODE_OSD!). Continuing.
  goto :osd_ready
)
timeout /t !SLEEP! >nul
goto :wait_osd
:osd_ready

REM --- seed: Postgres schema & sample data ---
echo [STEP] Seeding Postgres (schema + sample)...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql >> "%BOOTLOG%" 2>&1
if errorlevel 1 ( echo [WARN] Schema init non-zero (check %BOOTLOG%) )
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql >> "%BOOTLOG%" 2>&1
if errorlevel 1 ( echo [WARN] Sample inserts non-zero (check %BOOTLOG%) )

REM --- seed: OpenSearch index template & sample doc ---
echo [STEP] Seeding OpenSearch (template + sample doc)...
curl -s -X PUT %OS_AUTH% -H "Content-Type: application/json" ^
  "%OS_URL%/_index_template/kwve-transcripts-template" ^
  --data-binary "@sql/opensearch_index_template.json" >> "%BOOTLOG%" 2>&1

REM create the concrete index once (ignore 400 if exists)
curl -s -X PUT %OS_AUTH% -H "Content-Type: application/json" ^
  "%OS_URL%/kwve-transcripts" ^
  -d "{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": 0}}" >> "%BOOTLOG%" 2>&1

REM load a sample transcript doc
curl -s -X POST %OS_AUTH% -H "Content-Type: application/json" ^
  "%OS_URL%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
  --data-binary "@sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json" >> "%BOOTLOG%" 2>&1

echo [DONE] Bootstrap complete. See %BOOTLOG%
popd & endlocal & exit /b 0

:abort
echo [ABORT] Bootstrap failed due to readiness or init error.
popd & endlocal & exit /b 1
