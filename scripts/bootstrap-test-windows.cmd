@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd — Idempotent bootstrap with waits + init
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
set "OPENSEARCH_DASHBOARDS_PORT=5601"  & REM ### CHANGED: new var
set "POSTGRES_USER=kwve"
set "POSTGRES_DB=kwve"
set "MINIO_PORT=9000"
if exist "%ENV_FILE%" (
  for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_FILE%") do (
    set "K=%%~A" & set "V=%%~B"
    if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
    if /I "!K!"=="OPENSEARCH_DASHBOARDS_PORT" set "OPENSEARCH_DASHBOARDS_PORT=!V!"  & REM ### CHANGED
    if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
    if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
    if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
  )
)

echo [INFO] Using: POSTGRES_USER=%POSTGRES_USER% POSTGRES_DB=%POSTGRES_DB% OS=http://localhost:%OPENSEARCH_PORT% MinIO=%MINIO_PORT%
echo [STEP] docker compose up -d
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d >> "%LOGFILE%" 2>&1
if errorlevel 1 (
  echo [ERR] compose up failed
  popd & endlocal & exit /b 1
)

REM --- build convenience URLs ---
set "OS_HTTP=http://localhost:%OPENSEARCH_PORT%"
set "OS_HTTPS=https://localhost:%OPENSEARCH_PORT%"
set "OSD_STATUS=http://localhost:%OPENSEARCH_DASHBOARDS_PORT%/api/status"  & REM ### CHANGED

REM --- wait: OpenSearch (accept HTTP 200/401 or HTTPS 200/401) ---
echo [WAIT] OpenSearch at %OS_HTTP% ...
set "TRIES=0"
:wait_os
set "CODE_HTTP=" & set "CODE_HTTPS="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OS_HTTP%" 2^>^&1`) do set "CODE_HTTP=%%S"
for /f "usebackq delims=" %%S in (`curl -k -s -o NUL -w "%%{http_code}" "%OS_HTTPS%" 2^>^&1`) do set "CODE_HTTPS=%%S"
if "%CODE_HTTP%"=="200"  (echo [OK ] OpenSearch HTTP 200 & goto :os_ready)
if "%CODE_HTTP%"=="401"  (echo [OK ] OpenSearch HTTP 401 (auth required) & goto :os_ready)
if "%CODE_HTTPS%"=="200" (echo [OK ] OpenSearch HTTPS 200 & goto :os_ready)
if "%CODE_HTTPS%"=="401" (echo [OK ] OpenSearch HTTPS 401 (auth required) & goto :os_ready)
set /a TRIES+=1
if %TRIES% GEQ 90 ( echo [FAIL] OpenSearch not ready (HTTP=%CODE_HTTP% HTTPS=%CODE_HTTPS%) & goto :failout )
timeout /t 2 >nul
goto :wait_os
:os_ready

REM --- wait: Dashboards (HTTP) — now uses OSD port from .env ---
echo [WAIT] OpenSearch Dashboards at %OSD_STATUS% ...
set "TRIES=0"
:wait_osd
set "CODE_OSD="
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OSD_STATUS%" 2^>^&1`) do set "CODE_OSD=%%S"
if "%CODE_OSD%"=="200" (
  echo [OK ] Dashboards HTTP 200
) else (
  set /a TRIES+=1
  if %TRIES% GEQ 90 (
    echo [FAIL] Dashboards not ready (HTTP=%CODE_OSD%)
    goto :failout
  )
  timeout /t 2 >nul
  goto :wait_osd
)

REM --- optional: container sanity log ---
echo [INFO] docker ps summary >> "%LOGFILE%"
docker ps >> "%LOGFILE%" 2>&1

REM --- seed Postgres (uses POSTGRES_DB from env) ---
echo [STEP] Seeding Postgres...
docker compose -f "%COMPOSE_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql >> "%LOGFILE%" 2>&1
if errorlevel 1 echo [WARN] schema init failed or already applied. See log.
docker compose -f "%COMPOSE_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql >> "%LOGFILE%" 2>&1
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
exit /b 0

:failout
echo [ABORT] Bootstrap failed due to readiness or init error.
popd
exit /b 1
