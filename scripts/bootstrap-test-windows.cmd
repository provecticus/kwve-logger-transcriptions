
@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd — bring up stack, wait, and seed (env-aware)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"
set "LOGDIR=scripts\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "BOOTLOG=%LOGDIR%\bootstrap-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

REM defaults
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
set "OS_URLS=https://localhost:%OPENSEARCH_PORT%"
set "OSD_STATUS=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"

set "OS_AUTH="
if defined OPENSEARCH_USERNAME if defined OPENSEARCH_PASSWORD (
  set "OS_AUTH=-u %OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%"
)

set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\\"

echo [INFO] Using: PG=%POSTGRES_USER%@%POSTGRES_PORT% DB=%POSTGRES_DB%  OS=%OS_URL%  OSD=%OPENSEARCH_DASHBOARDS_PORT%  MinIO=%MINIO_PORT%
echo [STEP] docker compose up -d

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

REM --- initial grace period to let JVM bind ports ---
timeout /t 5 >nul

REM --- WAIT: OpenSearch (accept 200/401 via HTTP or HTTPS) ---
set "TRIES=0"
set "MAX_TRIES_OS=180"
set "SLEEP=2"
echo [WAIT] OpenSearch at %OS_URL% ...
:wait_os
set /a IDX=TRIES %% 4
for %%z in (!IDX!) do set "CH=!SP%%z!"
set "CODE_HTTP="
set "CODE_HTTPS="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" %OS_AUTH% "%OS_URL%/" 2^>^&1`) do set "CODE_HTTP=%%S"
for /f "usebackq delims=" %%S in (`curl -k -s -o NUL -w "%%{http_code}" %OS_AUTH% "%OS_URLS%/" 2^>^&1`) do set "CODE_HTTPS=%%S"
<nul set /p "=  [!CH!] OS http=!CODE_HTTP! https=!CODE_HTTPS! (try !TRIES!/!MAX_TRIES_OS!)   `r"
if "!CODE_HTTP!"=="200"  (echo. & echo [OK ] OpenSearch HTTP 200 & goto :os_ready)
if "!CODE_HTTP!"=="401"  (echo. & echo [OK ] OpenSearch HTTP 401 (auth) & goto :os_ready)
if "!CODE_HTTPS!"=="200" (echo. & echo [OK ] OpenSearch HTTPS 200 & goto :os_ready)
if "!CODE_HTTPS!"=="401" (echo. & echo [OK ] OpenSearch HTTPS 401 (auth) & goto :os_ready)
set /a TRIES+=1
if !TRIES! GEQ !MAX_TRIES_OS! (
  echo.
  echo [FAIL] OpenSearch not ready (HTTP=!CODE_HTTP! HTTPS=!CODE_HTTPS!)
  goto :abort
)
timeout /t !SLEEP! >nul
goto :wait_os
:os_ready

REM --- WAIT: Dashboards (accept 200/401/302) ---
set "TRIES=0"
set "MAX_TRIES_OSD=180"
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

REM --- SEED: Postgres (idempotent) ---
echo [STEP] Seeding Postgres (schema + sample)...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql >> "%BOOTLOG%" 2>&1
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql >> "%BOOTLOG%" 2>&1

REM --- SEED: OpenSearch template + CREATE index + sample doc ---
echo [STEP] Seeding OpenSearch (template + index + sample doc)...

REM apply template (ignore failures; we create index next)
curl -s -X PUT %OS_AUTH% -H "Content-Type: application/json" ^
  "%OS_URL%/_index_template/kwve-transcripts-template" ^
  --data-binary "@sql/opensearch_index_template.json" >> "%BOOTLOG%" 2>&1

REM simple index create (no body) to avoid CMD quoting issues
curl -s -X PUT %OS_AUTH% "%OS_URL%/kwve-transcripts" >> "%BOOTLOG%" 2>&1

REM insert sample document
curl -s -X POST %OS_AUTH% -H "Content-Type: application/json" ^
  "%OS_URL%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
  --data-binary "@sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json" >> "%BOOTLOG%" 2>&1

echo [DONE] Bootstrap complete. See %BOOTLOG%
popd & endlocal & exit /b 0

:abort
echo [ABORT] Bootstrap failed due to readiness or init error.
echo [HINT] Try:  docker compose -f "%COMPOSE_FILE%" logs --since=2m opensearch
popd & endlocal & exit /b 1
