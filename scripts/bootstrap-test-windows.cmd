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

if not exist "%ENV_FILE%" (
  echo [ERR] Missing %ENV_FILE%
  popd & endlocal & exit /b 1
)

REM --- read env (ignore blanks / comments) ---
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

REM optional auth for OS when security is enabled
set "OS_AUTH="
if defined OPENSEARCH_USERNAME if defined OPENSEARCH_PASSWORD (
  set "OS_AUTH=-u %OPENSEARCH_USERNAME%:%OPENSEARCH_PASSWORD%"
)

REM spinner glyphs
set "SP0=|"
set "SP1=/"
set "SP2=-"
set "SP3=\"

echo [INFO] Using: PG=%POSTGRES_USER%@%POSTGRES_PORT% DB=%POSTGRES_DB%  OS=%OS_URL%  OSD=%OPENSEARCH_DASHBOARDS_PORT%  MinIO=%MINIO_PORT%/%MINIO_CONSOLE_PORT%
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

REM --- short grace before probing (JVM bind) ---
timeout /t 5 >nul

REM --- WAIT: OpenSearch (HTTP first, HTTPS fallback; accept 200/401) ---
set "CURL=%SystemRoot%\System32\curl.exe"
set "TRIES=0"
set "MAX_TRIES_OS=180"
set "SLEEP=2"
echo [WAIT] OpenSearch at %OS_URL% ...
:wait_os
set /a IDX=TRIES %% 4
for %%z in (!IDX!) do set "CH=!SP%%z!"
set "CODE_HTTP=" & set "CODE_HTTPS="
for /f "usebackq delims=" %%S in (`"%CURL%" -s -o NUL -w "%%{http_code}" %OS_AUTH% "%OS_URL%/" 2^>^&1`) do set "CODE_HTTP=%%S"
if not defined CODE_HTTP (
  for /f "usebackq delims=" %%S in (`"%CURL%" -k -s -o NUL -w "%%{http_code}" %OS_AUTH% "%OS_URLS%/" 2^>^&1`) do set "CODE_HTTPS=%%S"
)
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
for /f "usebackq delims=" %%S in (`"%CURL%" -s -o NUL -w "%%{http_code}" "%OSD_STATUS%" 2^>^&1`) do set "CODE_OSD=%%S"
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

REM --- SEED: Postgres (schema + sample) ---
echo [STEP] Seeding Postgres (schema + sample)...
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/001_init.sql >> "%BOOTLOG%" 2>&1
docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" exec -T postgres psql -U "%POSTGRES_USER%" -d "%POSTGRES_DB%" -f /sql/090_sample_inserts.sql >> "%BOOTLOG%" 2>&1

REM --- SEED: OpenSearch template + index + sample doc (idempotent, with retries) ---
echo [STEP] Seeding OpenSearch (template + index + sample doc)...
set "TEMPLATE_PATH=sql\opensearch_index_template.json"
if not exist "%TEMPLATE_PATH%" set "TEMPLATE_PATH=infra\opensearch_index_template.json"
if exist "%TEMPLATE_PATH%" (
  for /f "usebackq delims=" %%C in (`"%CURL%" -s -o NUL -w "%%{http_code}" %OS_AUTH% -H "Content-Type: application/json" -X PUT "%OS_URL%/_index_template/kwve-transcripts-template" --data-binary "@%TEMPLATE_PATH%"`) do set CODE_TPL=%%C
  if "%CODE_TPL%"=="200" (echo [PASS] OS template applied (HTTP 200)) else if "%CODE_TPL%"=="201" (echo [PASS] OS template created (HTTP 201)) else (echo [WARN] OS template apply returned HTTP %CODE_TPL%)
) else (
  echo [WARN] No index template JSON found (looked in sql\ and infra\).
)

for /f "usebackq delims=" %%C in (`"%CURL%" -s -o NUL -w "%%{http_code}" %OS_AUTH% -X PUT "%OS_URL%/kwve-transcripts"`) do set CODE_IDX=%%C
if "%CODE_IDX%"=="200" (echo [PASS] OS index ok (HTTP 200)) ^
else if "%CODE_IDX%"=="201" (echo [PASS] OS index created (HTTP 201)) ^
else if "%CODE_IDX%"=="400" (echo [PASS] OS index already exists (HTTP 400)) ^
else if "%CODE_IDX%"=="409" (echo [PASS] OS index already exists (HTTP 409)) ^
else (echo [WARN] OS index create returned HTTP %CODE_IDX%)

set "SAMPLE_JSON=sample-data\radio\2025-09-04\2025-09-04T09-00-00Z.sample-transcript.json"
if exist "%SAMPLE_JSON%" (
  for /f "usebackq delims=" %%C in (`"%CURL%" -s -o NUL -w "%%{http_code}" %OS_AUTH% -H "Content-Type: application/json" -X POST "%OS_URL%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" --data-binary "@%SAMPLE_JSON%"`) do set CODE_DOC=%%C
  if "%CODE_DOC%"=="200" (echo [PASS] OS sample doc inserted (HTTP 200)) ^
  else if "%CODE_DOC%"=="201" (echo [PASS] OS sample doc created (HTTP 201)) ^
  else (
    echo [INFO] OS sample doc insert returned HTTP %CODE_DOC% - retrying once...
    timeout /t 2 >nul
    for /f "usebackq delims=" %%C in (`"%CURL%" -s -o NUL -w "%%{http_code}" %OS_AUTH% -H "Content-Type: application/json" -X POST "%OS_URL%/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" --data-binary "@%SAMPLE_JSON%"`) do set CODE_DOC2=%%C
    if "%CODE_DOC2%"=="200" (echo [PASS] OS sample doc inserted (HTTP 200)) ^
    else if "%CODE_DOC2%"=="201" (echo [PASS] OS sample doc created (HTTP 201)) ^
    else (echo [WARN] OS sample doc insert still returned HTTP %CODE_DOC2%)
  )
) else (
  echo [WARN] Sample transcript not found at %SAMPLE_JSON%
)

echo [DONE] Bootstrap complete. See %BOOTLOG%
popd & endlocal & exit /b 0

:abort
echo [ABORT] Bootstrap failed due to readiness or init error.
echo [HINT] Try:  docker compose -f "%COMPOSE_FILE%" logs --since=2m opensearch
popd & endlocal & exit /b 1
