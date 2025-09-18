# KWVE Scripts Usage — Bootstrap, Verify, and Reset

This doc explains how to use the **bootstrap**, **verify**, and **reset** scripts on Windows (CMD) for the KWVE Logger Transcriptions scaffold.

> Repo layout (paths referenced below):
```
kwve-logger-transcriptions/
│   README.md
│
├── docs/
│   └── (this file recommended to be saved as docs/KWVE_Scripts_Usage.md)
├── infra/
│   ├── .env
│   ├── .env.example
│   └── docker-compose.yml
├── scripts/
│   ├── bootstrap-test-windows.cmd
│   ├── reset-stack.cmd
│   └── verify-deploy.cmd
└── sql/
    ├── 001_init.sql
    ├── 090_sample_inserts.sql
    └── opensearch_index_template.json
```

---

## Prerequisites

- Windows 10/11 with **CMD** (or PowerShell) and admin rights.
- **Docker Desktop** installed and running.
- `infra/.env` configured with your credentials/ports (copy from `infra/.env.example`).

> Tip: Some compose files expect a root `.env`. Our bootstrap script **self-heals** by copying `infra/.env` to root if needed.

---

## 1) Bootstrap — bring up, wait, and seed

**Script:** `scripts/bootstrap-test-windows.cmd`

**What it does:**
- Ensures a root `.env` exists if the compose file expects it.
- Runs `docker compose up -d` **from `infra/`** so `infra/.env` is loaded.
- Waits for:
  - OpenSearch `http://localhost:<OPENSEARCH_PORT>` → 200
  - OpenSearch Dashboards `http://localhost:5601/api/status` → 200 (best-effort)
  - MinIO health `http://localhost:<MINIO_PORT>/minio/health/ready` → 200 (best-effort)
  - Postgres (`SELECT 1`) inside container
- Seeds:
  - Postgres schema (`/sql/001_init.sql`) + optional sample inserts
  - OpenSearch index template (`sql/opensearch_index_template.json`)
  - Sample transcript document

**How to run:**
```cmd
scriptsootstrap-test-windows.cmd
```

**Success looks like:**
```
[OK ] OpenSearch HTTP 200
[OK ] Postgres reachable
[STEP] Put OpenSearch index template
[STEP] Put sample transcript doc
[DONE] Bootstrap completed.
```

---

## 2) Verify — health & content checks with PASS/FAIL

**Script:** `scripts/verify-deploy.cmd`

**What it does:**
- Confirms containers are up (names: `kwve_pg`, `kwve_os`, `kwve_os_dash`, `kwve_minio`, `kwve_redis`).
- HTTP checks (via `curl`): OpenSearch (200), Dashboards (200), MinIO health (200).
- OpenSearch content: index `kwve-transcripts` exists and sample doc is present.
- Postgres connectivity: runs `SELECT 1` inside the container.
- Writes a timestamped log under `scripts/logs/` and returns an **exit code**:
  - `0` → PASS
  - `1` → FAIL

**How to run:**
```cmd
scriptserify-deploy.cmd
```

**Expected output (PASS):**
```
RESULT: PASS  (All checks successful)
Logs: scripts\logserify-YYYYMMDD-HHMMSS.log
```

**If it FAILs:**
- Open the referenced log under `scripts\logs\...` to see which check(s) failed.
- Common causes:
  - Service not ready yet → re-run verify after ~30s.
  - Wrong ports/creds in `infra/.env`.
  - Index/doc not present → re-run bootstrap to seed OS.
  - Postgres db/user mismatch → check `POSTGRES_USER`/`POSTGRES_DB` in `infra/.env`.

---

## 3) Reset — clean slate for redeploys

**Script:** `scripts/reset-stack.cmd`

**What it does:**
- Runs `docker compose down -v --remove-orphans` from both the repo root and `infra/`.
- Force-removes any lingering fixed-name containers: `kwve_minio`, `kwve_os`, `kwve_os_dash`, `kwve_pg`, `kwve_redis`.
- Removes known networks/volumes created by different project names.
- Prunes dangling Docker resources.

**How to run:**
```cmd
scriptseset-stack.cmd
```

**Use this when:**
- You see container name conflicts (e.g., `/kwve_minio already in use`).
- You want to wipe Postgres/OpenSearch/MinIO state and start fresh.

---

## Troubleshooting Cheatsheet

- **`env file ...\.env not found`**  
  Your compose file likely references a **root** `.env` (e.g., `../.env`). Either:
  - Copy: `copy infra\.env .env`, or
  - Edit `infra/docker-compose.yml` to use `env_file: .env` for each service.

- **HTTP 000 / 503 in verify**  
  Services not ready yet or wrong ports. Re-run verify after 30–60s. Check `infra/.env` ports.

- **OpenSearch index/doc missing**  
  Re-run bootstrap to apply the index template and sample doc.

- **Postgres connectivity failed**  
  Ensure DB is ready; verify `POSTGRES_USER`/`POSTGRES_DB` in `infra/.env`. You can also check logs:
  ```cmd
  pushd infra
  docker compose logs --since=5m postgres
  popd
  ```

- **Container name conflict (`already in use`)**  
  Run `scriptseset-stack.cmd` to force-remove fixed-name containers, then bootstrap again.

---

## CI/Automation Notes

- `scriptserify-deploy.cmd` returns **exit code 0/1** and logs to `scripts\logs\...`.  
  You can use it in CI steps to gate promotion or artifacts.

- For non-interactive shells, ensure Docker Desktop is running before bootstrap.

---

## PowerShell Option (optional)

If your team prefers PowerShell, we can provide `.ps1` equivalents that stream richer output and JSON summaries. Ask and we’ll include them here.
