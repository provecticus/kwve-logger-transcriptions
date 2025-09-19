@echo off
REM =====================================================================
REM reset-stack.cmd — Aggressive reset for KWVE stack (handles name conflicts)
REM Removes compose stacks created from either repo root or infra\ and any
REM stray containers using fixed container_name (kwve_*).
REM =====================================================================
setlocal EnableExtensions

echo Stopping/removing compose stack from REPO ROOT (project=kwve-logger-transcriptions)...
docker compose -f infra\docker-compose.yml --env-file infra\.env down -v --remove-orphans

echo Stopping/removing compose stack from INFRA dir (project=infra)...
pushd infra
docker compose down -v --remove-orphans
popd

echo Force removing any lingering containers with fixed names...
for %%C in (kwve_minio kwve_os kwve_os_dash kwve_pg kwve_redis) do (
  docker rm -f %%C 2>nul
)

echo Removing known networks if present...
for %%N in (infra_kwve_net kwve-logger-transcriptions_kwve_net) do (
  docker network rm %%N 2>nul
)

echo Removing known volumes if present...
for %%V in (infra_minio_data infra_os_data infra_pg_data kwve-logger-transcriptions_minio_data kwve-logger-transcriptions_os_data kwve-logger-transcriptions_pg_data) do (
  docker volume rm %%V 2>nul
)

echo Pruning dangling Docker resources...
docker system prune -af --volumes

echo Listing remaining project volumes and networks...
docker volume ls
docker network ls

echo Done. You are reset to a clean state.
pause
