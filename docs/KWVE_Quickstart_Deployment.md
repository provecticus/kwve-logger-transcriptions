# KWVE Logger Transcriptions - Quickstart Deployment Guide

This guide is designed to help you **quickly stand up and test** the KWVE Logger Transcriptions scaffold (Phase 0) using a Windows environment. It leverages a ready-made script to reduce manual steps and avoid common pitfalls.

---

## 📦 Prerequisites

Before you begin, make sure you have:

- **Windows 10/11** with administrative access.
- **Docker Desktop** installed and running (with WSL2 backend enabled).
- **Git** installed (optional, for cloning repo).
- **cURL** installed (bundled with Windows 10+ by default).

---

## ⚙️ Project Structure

Your repo should look like this after setup:

```
kwve-logger-transcriptions/
│   .gitignore
│   bootstrap-test-windows.cmd
│   README.md
│
├───docs/
│       ARCHITECTURE.md
│       KWVE_Bootstrap_Testing_Guide.md
│       ROADMAP.md
│
├───infra/
│       .env
│       .env.example
│       docker-compose.yml
│
├───policies/
│       retention.yaml
│
├───sample-data/
│   └───radio/
│       └───2025-09-04/
│               09-00-00.sample.mp3
│               2025-09-04T09-00-00Z.sample-transcript.json
│               2025-09-04T09-00-00Z.sample-transcript.srt
│               2025-09-04T09-00-00Z.sample-transcript.txt
│               2025-09-04T09-00-00Z.sample-transcript.vtt
│
├───schemas/
│       asset.schema.json
│       transcript.schema.json
│
└───sql/
        001_init.sql
        090_sample_inserts.sql
        opensearch_index_template.json
```

> Note: `.env` now lives under `infra/` next to `docker-compose.yml`. The quickstart script references it explicitly.

---

## 📝 .env File Setup

Navigate to `infra/`, copy `.env.example` to `.env`, and adjust values. Example:

```ini
POSTGRES_USER=kwve
POSTGRES_PASSWORD=secret
POSTGRES_DB=kwve
POSTGRES_PORT=5432

OPENSEARCH_USERNAME=admin
OPENSEARCH_PASSWORD=admin
OPENSEARCH_PORT=9200
OPENSEARCH_INITIAL_ADMIN_PASSWORD=admin

MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=minio123
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001

REDIS_PORT=6379
```

---

## 🚀 Quickstart Script

To make deployment simple, we provide a **Windows batch script**: `bootstrap-test-windows.cmd`.

### Steps:
1. Ensure `bootstrap-test-windows.cmd` is in the project root.  
2. Ensure `.env` is inside the `infra/` folder.  
3. Double-click the script or run inside `cmd.exe`:

   ```cmd
   bootstrap-test-windows.cmd
   ```

### What It Does:
- Starts the Docker stack with your `infra/.env` configuration.  
- Initializes Postgres schema and inserts sample data.  
- Loads the OpenSearch index template.  
- Indexes a sample transcript.  
- Prints a completion message with the URL to OpenSearch Dashboards.

---

## 🔍 Verification

Once the script finishes:

1. Open **OpenSearch Dashboards** in your browser:  
   [http://localhost:5601](http://localhost:5601)

2. Log in with the credentials from `.env` (default: `admin/admin`).

3. Add an index pattern for `kwve-transcripts`.

4. Perform a search by keyword, speaker, or timestamp to confirm the sample transcript is available.

---

## 📂 Storage Check

Open MinIO Console: [http://localhost:9001](http://localhost:9001)  
- Login with `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` from `infra/.env`.  
- Verify that sample data objects exist under the bucket.  

---

## 🛠 Troubleshooting

- **Containers restarting?**  
  Likely `.env` is missing or variables are blank. Confirm `infra/.env` exists and restart with:  
  ```cmd
  docker compose -f infra\docker-compose.yml --env-file infra\.env down -v
  docker compose -f infra\docker-compose.yml --env-file infra\.env up -d
  ```

- **psql not found?**  
  Always use `docker compose exec postgres psql ...` (already handled by the script).

- **cURL errors on Windows**?  
  Make sure you're running `cmd.exe`, not PowerShell. The script uses CMD syntax.

---

## ✅ Next Steps

- Drop real logger recordings into MinIO for ingestion tests.  
- Extend the system with **Phase 1 Ingestion Watcher** and **Phase 2 ASR Worker**.  
- Prepare additional deployment docs for production (TLS, HA, backups).

---

## 🎯 Summary

The quickstart script makes it possible to go from **zero to a working demo** of KWVE Logger Transcriptions in just a few minutes.  
You should now have:  
- Docker stack running.  
- Postgres initialized with schema.  
- OpenSearch ready with index template + sample transcript.  
- MinIO serving objects with retention policies.  

You are ready to begin experimenting and extending toward full deployment!


---

## 🔁 Clean Reset (Start Fresh)

If a previous attempt partially deployed containers, reset to a clean state:

```cmd
reset-stack.cmd
```

This will:
- Stop and remove the stack (`down -v`), including volumes.
- Prune dangling Docker resources.
- List remaining volumes/networks for reference.

> After resetting, re-run the quickstart script:
> ```cmd
> bootstrap-test-windows.cmd
> ```

---

## ✅ Post-Deployment Verification

Use the verification script to validate services and capture a log:

```cmd
verify-deploy.cmd
```

What it checks:
- **docker ps** output to ensure containers are up.
- **OpenSearch (9200)** and **Dashboards (5601/api/status)** return HTTP 200.
- **MinIO health** (`/minio/health/ready`) returns HTTP 200.
- **OpenSearch** contains the `kwve-transcripts` index and the sample document ID.
- **Postgres** responds and lists tables; optional row counts for `assets` and `transcripts`.

All output is saved to `logs\verify-YYYYMMDD-HHMM.log`.

If your team prefers PowerShell, we can provide `.ps1` equivalents that stream richer output and JSON summaries. Ask and we'll include them here.
