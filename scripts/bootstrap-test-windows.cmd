@echo off
REM =====================================================================
REM bootstrap-test-windows.cmd — Idempotent bootstrap with waits + init
REM Works from repo root OR scripts\ (auto-CDs to repo root)
REM Runs docker compose FROM infra\ to auto-load infra\.env
REM Avoids COMPOSE_FILE env var conflicts
REM =====================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM --- locate repo root ---
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\.."

REM --- paths (use names that DO NOT collide with docker-compose env vars) ---
set "CF_PATH=infra\docker-compose.yml"
set "ENV_PATH=infra\.env"
set "INDEX_TEMPLATE=sql\opensearch_index_template.json"
set "SAMPLE_DOC=sample-data\radio\2025-09-04\2025-09-04T09-00-00Z.sample-transcript.json"

REM --- sanity ---
if not exist "%CF_PATH%" ( echo [ERR] Missing %CF_PATH% & popd & exit /b 2 )
if not exist "%ENV_PATH%" ( echo [ERR] Missing %ENV_PATH% (copy infra\.env.example -> infra\.env) & popd & exit /b 2 )
if not exist "%INDEX_TEMPLATE%" ( echo [ERR] Missing %INDEX_TEMPLATE% & popd & exit /b 2 )
if not exist "%SAMPLE_DOC%" ( echo [ERR] Missing %SAMPLE_DOC% & popd & exit /b 2 )

REM --- read key vars for prints (optional) ---
for /f "usebackq tokens=1* delims== eol=#" %%A in ("%ENV_PATH%") do (
  set "K=%%A" & set "V=%%B"
  if /I "!K!"=="POSTGRES_USER" set "POSTGRES_USER=!V!"
  if /I "!K!"=="POSTGRES_DB" set "POSTGRES_DB=!V!"
  if /I "!K!"=="OPENSEARCH_USERNAME" set "OPENSEARCH_USERNAME=!V!"
  if /I "!K!"=="OPENSEARCH_PASSWORD" set "OPENSEARCH_PASSWORD=!V!"
  if /I "!K!"=="OPENSEARCH_INITIAL_ADMIN_PASSWORD" set "OPENSEARCH_INITIAL_ADMIN_PASSWORD=!V!"
  if /I "!K!"=="OPENSEARCH_PORT" set "OPENSEARCH_PORT=!V!"
  if /I "!K!"=="MINIO_PORT" set "MINIO_PORT=!V!"
)

REM --- defaults & fallbacks ---
if not defined POSTGRES_USER set "POSTGRES_USER=kwve"
if not defined POSTGRES_DB set "POSTGRES_DB=kwve"
if not defined OPENSEARCH_USERNAME set "OPENSEARCH_USERNAME=admin"
if not defined OPENSEARCH_PASSWORD if defined OPENSEARCH_INITIAL_ADMIN_PASSWORD set "OPENSEARCH_PASSWORD=%OPENSEARCH_INITIAL_ADMIN_PASSWORD%"
if not defined OPENSEARCH_PASSWORD set "OPENSEARCH_PASSWORD=admin"
if not defined OPENSEARCH_PORT set "OPENSEARCH_PORT=9200"
if not defined MINIO_PORT set "MINIO_PORT=9000"

set "OS_BASE=http://localhost:%OPENSEARCH_PORT%"
set "MINIO_HEALTH=http://localhost:%MINIO_PORT%/minio/health/ready"

echo [INFO] Using: POSTGRES_USER=%POSTGRES_USER% POSTGRES_DB=%POSTGRES_DB% OS=%OPENSEARCH_USERNAME%@%OS_BASE% MINIO_PORT=%MINIO_PORT%

REM --- bring up stack FROM infra\ so .env is auto-loaded ---
echo [STEP] docker compose up -d
pushd infra
REM Ensure no COMPOSE_FILE env var interferes
set COMPOSE_FILE=
docker compose up -d
if errorlevel 1 ( popd & echo [ERR] compose up failed & popd & exit /b 3 )
popd

REM --- wait: OpenSearch ready ---
echo [WAIT] OpenSearch at %OS_BASE% ...
set "TRIES=0"
:wait_os
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%OS_BASE%" 2^>^&1`) do set "CODE=%%S"
if "%CODE%"=="200" ( echo [OK ] OpenSearch HTTP 200 & goto :os_ready )
set /a TRIES+=1
if %TRIES% GEQ 60 ( echo [FAIL] OpenSearch not ready (last=%CODE%) & goto :failout )
timeout /t 2 >nul
goto :wait_os
:os_ready

REM --- wait: OpenSearch Dashboards (optional) ---
echo [WAIT] OpenSearch Dashboards at http://localhost:5601/api/status ...
set "TRIES=0"
:wait_osd
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "http://localhost:5601/api/status" 2^>^&1`) do set "CODE=%%S"
if "%CODE%"=="200" ( echo [OK ] Dashboards HTTP 200 & goto :osd_ready )
set /a TRIES+=1
if %TRIES% GEQ 60 ( echo [WARN] Dashboards not ready yet (last=%CODE%), continuing... & goto :osd_ready )
timeout /t 2 >nul
goto :wait_osd
:osd_ready

REM --- wait: MinIO health ---
echo [WAIT] MinIO health at %MINIO_HEALTH% ...
set "TRIES=0"
:wait_minio
for /f "usebackq delims=" %%S in (`curl -s -o NUL -w "%%{http_code}" "%MINIO_HEALTH%" 2^>^&1`) do set "CODE=%%S"
if "%CODE%"=="200" ( echo [OK ] MinIO health 200 & goto :minio_ready )
set /a TRIES+=1
if %TRIES% GEQ 60 ( echo [WARN] MinIO health not ready (last=%CODE%), continuing... & goto :minio_ready )
timeout /t 2 >nul
goto :wait_minio
:minio_ready

REM --- wait: Postgres connectivity ---
echo [WAIT] Postgres (SELECT 1) ...
set "TRIES=0"
:wait_pg
pushd infra
set COMPOSE_FILE=
docker compose exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -c "SELECT 1;" 1>nul 2>nul
set "ERRLVL=%ERRORLEVEL%"
popd
if "%ERRLVL%"=="0" ( echo [OK ] Postgres reachable & goto :pg_ready )
set /a TRIES+=1
if %TRIES% GEQ 60 ( echo [FAIL] Postgres not reachable & goto :failout )
timeout /t 2 >nul
goto :wait_pg
:pg_ready

REM --- init DB schema + sample inserts (idempotent) ---
echo [STEP] Initialize DB schema
pushd infra
set COMPOSE_FILE=
docker compose exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql
if errorlevel 1 ( popd & echo [ERR] 001_init.sql failed & goto :failout )
echo [STEP] Sample inserts (may warn on duplicates)
docker compose exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql
if errorlevel 1 ( echo [WARN] sample inserts had warnings/errors )
popd

REM --- install OpenSearch index template ---
echo [STEP] Put OpenSearch index template
curl -u "%OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%" -s -o NUL -w "HTTP=%%{http_code}\n" -X PUT "%OS_BASE%/_index_template/kwve-transcripts-template" ^
  -H "Content-Type: application/json" ^
  --data-binary "@%INDEX_TEMPLATE%"

REM --- load sample transcript doc ---
echo [STEP] Put sample transcript doc
curl -u "%OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%" -s -o NUL -w "HTTP=%%{http_code}\n" -X POST "%OS_BASE%/kwve-transcripts/_doc/%OS_DOC_ID%" ^
  -H "Content-Type: application/json" ^
  --data-binary "@%SAMPLE_DOC%"

echo [DONE] Bootstrap completed.
popd
exit /b 0

:failout
echo [ABORT] Bootstrap failed due to readiness or init error.
popd
exit /b 1
