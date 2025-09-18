@echo off
REM ===============================================
REM Reset KWVE Logger Transcriptions Docker Stack
REM ===============================================
setlocal

echo Stopping and removing containers, networks, and volumes...
docker compose -f infra\docker-compose.yml --env-file infra\.env down -v

echo Pruning any dangling Docker resources (images, networks, build cache, volumes)...
docker system prune -af --volumes

echo Listing remaining project volumes and networks for reference...
docker volume ls
docker network ls

echo Done. You are reset to a clean state.
pause
