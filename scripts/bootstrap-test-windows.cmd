@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd — Idempotent bootstrap with live progress
REM Shows status codes while waiting for services; seeds DB and OpenSearch
REM Works from repo root OR scripts\ (auto-cds to repo root)
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM --- locate repo root (works from scripts\ or root) ---
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

REM --- paths ---
set "COMPOSE_FILE=infra\docker-compose.yml"
set "ENV_FILE=infra\.env"
set "INDEX_TEMPLATE=sql\opensearch_index_template.json"
set "SAMPLE_DOC=sample-data\radio\2025-09-04\2025-09-04T09-00-00Z.sample-transcript.json"

REM --- logging prep ---
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (set mm=%%a& set dd=%%b& set yyyy=%%c)
for /f "tokens=1-3 delims=:." %%a in ("%time%") do (set hh=%%a& set nn=%%b& set ss=%%c)
set hh=0%hh%
set hh=%hh:~-2%
set "LOGDIR=scripts\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\bootstrap-%yyyy%%mm%%dd%-%hh%%nn%%ss%.log"

REM --- read env (minimal, robust) ---
set "OPENSEARCH_PORT=9200"
set "OPENSEARCH_DASHBOARDS_PORT=5601"
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "MINIO_PORT=9000"
if exist "%ENV_FILE%" (
  for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_FILE%") do (
    set "K=%%~A" & set "V=%%~B"
    if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
    if /I "!K!"=="OPENSEARCH_DASHBOARDS_PORT" set "OPENSEARCH_DASHBOARDS_PORT=!V!"
    if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
    if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
    if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
  )
)

echo [INFO] Using: POSTGRES_USER=%POSTGRES_USER% POSTGRES_DB=%POSTGRES_DB% OS=http://localhost:%OPENSEARCH_PORT% MinIO=%MINIO_PORT%
echo [STEP] docker compose up -d
REM Print compose output to console AND log
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d | tee.exe "%LOGFILE%" >nul 2>&1
if errorlevel 1 (
  echo [ERR] compose up failed (see %LOGFILE%)
  popd & endlocal & exit /b 1
)

REM --- build convenience URLs ---
set "OS_HTTP=http://localhost:%OPENSEARCH_PORT%"
set "OS_HTTPS=https://localhost:%OPENSEARCH_PORT%"
set "OSD_STATUS=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"

REM --- helper: spinner char (just for fun) ---
set "SPIN=|/-\"

REM --- WAIT SETTINGS (tweak if you like) ---
set "MAX_TRIES_OS=120"          REM ~4 min at 2s
set "MAX_TRIES_OSD=180"         REM ~6 min at 2s
set "SLEEP_SECONDS=2"

REM --- wait: OpenSearch (accept HTTP/HTTPS 200 or 401) ---
echo [WAIT] OpenSearch at %OS_HTTP% ...
set "TRIES=0"
:wait_os
set "CODE_HTTP=" & set "CODE_HTTPS="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OS_HTTP%" 2^>^&1`) do set "CODE_HTTP=%%S"
for /f "usebackq delims=" %%S in (`curl -k -s -o NUL -w "%%{http_code}" "%OS_HTTPS%" 2^>^&1`) do set "CODE_HTTPS=%%S"

set /a IDX=TRIES %% 4
for /f %%c in ("!IDX!") do set "CH=!SPIN:~%%c,1!"

<nul set /p "=  [!CH!] OS http=!CODE_HTTP! https=!CODE_HTTPS! (try !TRIES!/!MAX_TRIES_OS!)   `r"

if "!CODE_HTTP!"=="200"  (echo. & echo [OK ] OpenSearch HTTP 200 & goto :os_ready)
if "!CODE_HTTP!"=="401"  (echo. & echo [OK ] OpenSearch HTTP 401 (auth required) & goto :os_ready)
if "!CODE_HTTPS!"=="200" (echo. & echo [OK ] OpenSearch HTTPS 200 & goto :os_ready)
if "!CODE_HTTPS!"=="401" (echo. & echo [OK ] OpenSearch HTTPS 401 (auth required) & goto :os_ready)

set /a TRIES+=1
if !TRIES! GEQ !MAX_TRIES_OS! (
  echo.
  echo [FAIL] OpenSearch not ready (HTTP=!CODE_HTTP! HTTPS=!CODE_HTTPS!)
  goto :diag_fail
)
timeout /t %SLEEP_SECONDS% >nul
goto :wait_os
:os_ready

REM --- wait: Dashboards (accept 200, 401, 302) ---
echo [WAIT] OpenSearch Dashboards at %OSD_STATUS% ...
set "TRIES=0"
:wait_osd
set "CODE_OSD="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OSD_STATUS%" 2^>^&1`) do set "CODE_OSD=%%S"

set /a IDX=TRIES %% 4
for /f %%c in ("!IDX!") do (
  set "SP0=|"
  set "SP1=/"
  set "SP2=-"
  set "SP3=\"
  for %%z in (!IDX!) do set "CH=!SP%%z!"
)
<nul set /p "=  [!CH!] Dashboards http=!CODE_OSD! (try !TRIES!/!MAX_TRIES_OSD!)   `r"

if "!CODE_OSD!"=="200"  (echo. & echo [OK ] Dashboards HTTP 200 & goto :dash_ready)
if "!CODE_OSD!"=="401"  (echo. & echo [OK ] Dashboards HTTP 401 (auth) & goto :dash_ready)
if "!CODE_OSD!"=="302"  (echo. & echo [OK ] Dashboards HTTP 302 (redirect) & goto :dash_ready)

set /a TRIES+=1
if !TRIES! GEQ !MAX_TRIES_OSD! (
  echo.
  echo [FAIL] Dashboards not ready (HTTP=!CODE_OSD!)
  goto :diag_fail
)
timeout /t %SLEEP_SECONDS% >nul
goto :wait_osd

:dash_ready


REM --- optional: container sanity log ---
echo [INFO] docker ps summary >> "%LOGFILE%"
docker ps >> "%LOGFILE%" 2>&1

REM --- seed Postgres (uses POSTGRES_DB from env) ---
echo [STEP] Seeding Postgres...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql >> "%LOGFILE%" 2>&1
if errorlevel 1 echo [WARN] schema init failed or already applied. See log.
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql >> "%LOGFILE%" 2>&1
if errorlevel 1 echo [WARN] sample inserts failed or already applied. See log.

REM --- seed OpenSearch: template + sample doc ---
set "INDEX_TEMPLATE_PATH=%INDEX_TEMPLATE%"
if not exist "%INDEX_TEMPLATE_PATH%" set "INDEX_TEMPLATE_PATH=infra\opensearch_index_template.json"
if exist "%INDEX_TEMPLATE_PATH%" (
  echo [STEP] Applying index template...
  curl -s -o NUL -w "HTTP=%%{http_code}\n" -X PUT "%OS_HTTP%/_index_template/kwve-transcripts-template" ^
    -H "Content-Type: application/json" --data-binary "@%INDEX_TEMPLATE_PATH%"
) else (
  echo [WARN] Index template JSON not found (looked in sql\ and infra\).
)

if exist "%SAMPLE_DOC%" (
  echo [STEP] Inserting sample transcript doc...
  curl -s -o NUL -w "HTTP=%%{http_code}\n" -X POST "%OS_HTTP%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
    -H "Content-Type: application/json" --data-binary "@%SAMPLE_DOC%"
) else (
  echo [WARN] Sample transcript JSON not found at %SAMPLE_DOC%.
)

echo [DONE] Bootstrap completed.
popd
endlocal
exit /b 0

:diag_fail
echo [DIAG] Checking port mappings...
pushd infra
docker compose port dashboards 5601
docker compose port opensearch 9200
echo [DIAG] Last 40 lines of dashboards logs:
docker compose logs --since=5m dashboards | tail -n 40
popd
echo [ABORT] Bootstrap failed due to readiness or init error.
popd
endlocal
exit /b 1
