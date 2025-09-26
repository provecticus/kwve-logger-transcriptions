# KWVE Logger Transcriptions - System Usage Guide

This guide explains how to **use** the deployed stack (after bootstrap), how to check health, where to find data, and how to perform common tasks.

> This document assumes the stack is running via `docker compose` using the env in `infra/.env`.

---

## Quick Links (from your `.env`)

- **OpenSearch (REST banner):** `http://localhost:${OPENSEARCH_PORT}/`
- **OpenSearch Dashboards (UI):** `http://localhost:${OPENSEARCH_DASHBOARDS_PORT}/`
- **MinIO Console (UI):** `http://localhost:${MINIO_CONSOLE_PORT}/`
- **MinIO S3 API (programmatic):** `http://localhost:${MINIO_PORT}/`

> Default host ports often used in this project:
> - OpenSearch: `19220`
> - Dashboards: `15601`
> - MinIO Console: `19001`
> - MinIO API (S3): `19000`
> - Postgres: `15432`
> (Your values may differ - always check `infra/.env`.)

---

## Health & Verification

### One-command health check (Windows)
From repo root:
```cmd
scripts\verify-deploy.cmd
```
What it confirms:
- Containers running (postgres, opensearch, dashboards, minio, redis)
- OpenSearch (HTTP 200/401), Dashboards (200/401/302)
- MinIO health (console `/ready` → `/live` → API fallback)
- Postgres connectivity (`SELECT 1`)
- OpenSearch index `kwve-transcripts` exists and the sample doc is present

A log is written to `scripts\logs\verify-YYYYMMDD-HHMMSS.log`.

---

## Where data lives

- **MinIO (S3-compatible)**
  - **Bucket:** (e.g.) `kwve-radio`
  - **What:** raw audio files and processing artifacts (TXT/VTT/SRT/JSON)
  - **Access:** `http://localhost:${MINIO_CONSOLE_PORT}/`
  - **Login:** `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` (from `infra/.env`)

- **Postgres**
  - **DB:** `${POSTGRES_DB}` (e.g. `kwve_logs`)
  - **Tables:** `assets`, transcript metadata, retention/legal-hold flags
  - **Port:** `${POSTGRES_PORT}`

- **OpenSearch**
  - **Index:** `kwve-transcripts`
  - **What:** full-text searchable document with transcript text + metadata
  - **Port:** `${OPENSEARCH_PORT}`

---

## Searching transcripts (in Dashboards)

1. Open **OpenSearch Dashboards** → `http://localhost:${OPENSEARCH_DASHBOARDS_PORT}/`
2. First time only: **Management → Stack Management → Index Patterns**  
   Add index pattern:  
   ```
   kwve-transcripts*
   ```
3. Go to **Discover**  
   - Use the search bar for words/phrases  
   - Add field filters (e.g., `station`, `utc_start`, etc.)  
   - Adjust the time picker to the hour/day you need

> If you use the Security plugin: you'll be prompted to login (`OPENSEARCH_USERNAME` / `OPENSEARCH_PASSWORD`). For local dev, we commonly disable the Dashboards security plugin so no login is required.

---

## Uploading / Viewing artifacts (MinIO)

1. Open **MinIO Console** → `http://localhost:${MINIO_CONSOLE_PORT}/`
2. Login with `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
3. Create or open the configured bucket (e.g., `kwve-radio`)
4. Upload artifacts (WAV/MP3, TXT, VTT, SRT, JSON) as needed

> The S3 API is available at `http://localhost:${MINIO_PORT}/` for scripted operations (e.g., `mc`, AWS SDKs, rclone).

---

## Seeding / Re-seeding OpenSearch (if blank)

The bootstrap script auto-seeds the template, creates the index, and inserts a sample doc. If you need to do it manually:

```cmd
REM Create index
curl -s -X PUT "http://localhost:${OPENSEARCH_PORT}/kwve-transcripts"

REM Insert sample record
curl -s -H "Content-Type: application/json" ^
  -X POST "http://localhost:${OPENSEARCH_PORT}/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
  --data-binary @sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json
```

Verify:
```cmd
curl -s -o NUL -w "IDX=%{http_code}\n" "http://localhost:${OPENSEARCH_PORT}/kwve-transcripts"
curl -s -o NUL -w "DOC=%{http_code}\n" "http://localhost:${OPENSEARCH_PORT}/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z"
```

---

## Common Operator Tasks

### Check service URLs quickly
- OpenSearch banner: `http://localhost:${OPENSEARCH_PORT}/`
- Dashboards status: `http://localhost:${OPENSEARCH_DASHBOARDS_PORT}/api/status`
- MinIO console: `http://localhost:${MINIO_CONSOLE_PORT}/`

### Reset + Re-Deploy (Windows)
```cmd
scripts\reset-stack.cmd
scripts\bootstrap-test-windows.cmd
scripts\verify-deploy.cmd
```

### Check container logs
```cmd
pushd infra
docker compose logs --since=5m opensearch
docker compose logs --since=5m dashboards
docker compose logs --since=5m minio
docker compose logs --since=5m postgres
popd
```

---

## Troubleshooting

- **Dashboards shows a login when you don't expect it**  
  Ensure the security plugin is disabled in Dashboards (local dev):
  ```yaml
  dashboards:
    environment:
      - OPENSEARCH_HOSTS=["http://opensearch:9200"]
      - DISABLE_SECURITY_DASHBOARDS_PLUGIN=true
  ```
  Restart just Dashboards:  
  `docker compose -f infra\docker-compose.yml up -d dashboards`

- **MinIO Console is blank / ERR_EMPTY_RESPONSE**  
  Ensure **console binds inside the container** to `:9001` and ports map host→container:
  ```yaml
  minio:
    command: ["server", "/data", "--console-address", ":9001"]
    ports:
      - "${MINIO_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
  ```
  Then `http://localhost:${MINIO_CONSOLE_PORT}/` should load.

- **Health probe returns 400**  
  Some MinIO builds return `400` for `/minio/health/ready` on the API port. Use console health (`/ready`, `/live`) or an S3 `HEAD /` (200/204/301/302).

- **OpenSearch index/doc 404**  
  Seed once (see "Seeding / Re-seeding OpenSearch" above) or re-run bootstrap. Verification can be extended to auto-seed if missing.

- **Compose says `services.X must be a mapping`**  
  YAML indentation/placement error; ensure `environment:` and `command:` are **inside** each service, not under `services:` root.

---

## Scripts (Windows)

- `scripts\reset-stack.cmd` - tear down containers, remove project volumes/networks, prune
- `scripts\bootstrap-test-windows.cmd` - start stack, wait for health, seed Postgres & OpenSearch
- `scripts\verify-deploy.cmd` - health & content checks with a log under `scripts\logs\`

> Save `.cmd` files as **ANSI** (or UTF-8 without BOM) and **CRLF** line endings to avoid `cmd.exe` parsing issues.

---

## Post-Deploy Checklist

- [ ] `scripts\verify-deploy.cmd` prints `RESULT: PASS`
- [ ] Dashboards opens and `kwve-transcripts*` index pattern is available
- [ ] MinIO console login works
- [ ] Sample doc is searchable in Dashboards
- [ ] Operator has shortcuts to URLs/ports and log locations
