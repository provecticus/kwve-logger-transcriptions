# KWVE Logger Transcriptions

A containerized stack for ingesting, storing, and searching broadcast transcripts.

---

## 📋 Overview

This repository provides an **infrastructure stack** using Docker Compose with the following services:

- **Postgres** - metadata & transcript storage
- **OpenSearch** - full-text search over transcripts
- **OpenSearch Dashboards** - UI for exploring/searching
- **MinIO** - object storage for raw audio assets
- **Redis** - caching, queueing, ephemeral tasks

The stack is designed for reproducible local testing, development, and eventual deployment.

---

## 🚀 Quickstart

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/kwve-logger-transcriptions.git
cd kwve-logger-transcriptions
```

### 2. Prerequisites

Ensure the following are installed on your system:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) or Docker Engine (Linux)
- [Docker Compose V2](https://docs.docker.com/compose/) (comes with Docker Desktop)
- **Windows users only**:
  - [GnuWin32 CoreUtils](http://gnuwin32.sourceforge.net/packages/coreutils.htm) - required for `tee.exe`
    - Add `C:\Program Files (x86)\GnuWin32\bin` (or wherever installed) to your PATH.

```powershell
# verify tee.exe is on PATH
where tee
```

### 3. Environment Variables

Copy the example env file:

```bash
cp infra/.env.example infra/.env
```

Edit `infra/.env` and set the required values (passwords, secrets, ports).

### 4. Bootstrap the Stack

Run the Windows bootstrap script (from repo root):

```powershell
scripts\bootstrap-test-windows.cmd
```

This will:
- Bring up the containers (`docker compose up -d`)
- Wait for OpenSearch and Dashboards to become available
- Initialize Postgres schema & sample data
- Load a sample transcript into OpenSearch

Progress is streamed with `[STEP]`, `[WAIT]`, `[OK]`, `[FAIL]` messages.

### 5. Verify Deployment

Run:

```powershell
scripts\verify-deploy.cmd
```

This performs:
- Container checks (`docker ps`)
- HTTP health checks (OpenSearch, Dashboards, MinIO)
- Index/document existence check in OpenSearch
- Postgres connectivity & simple query

Results are summarized as **PASS/FAIL**, with logs written to `scripts\logs\`.

### 6. Reset the Stack

If you need to start fresh:

```powershell
scripts\reset-stack.cmd
```

This will stop containers, remove volumes/networks, and prune dangling resources.

---

## 🗂 Repo Layout

```
.
├── docs/                # architecture, guides, roadmap
├── infra/               # compose & env files
├── policies/            # data retention policies
├── sample-data/         # demo MP3 + transcript JSON/SRT/TXT/VTT
├── schemas/             # JSON schema for assets + transcripts
├── scripts/             # bootstrap, verify, reset (Windows .cmd)
│   └── logs/            # log output from verification
└── sql/                 # init schema, sample inserts, index templates
```

---

## 📑 Docs

- [ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [ROADMAP.md](docs/ROADMAP.md)
- [KWVE_Bootstrap_Testing_Guide.md](docs/KWVE_Bootstrap_Testing_Guide.md)
- [KWVE_Quickstart_Deployment.md](docs/KWVE_Quickstart_Deployment.md)

---

## ⚡ Scripts Quick Reference

| Script                          | Purpose |
|---------------------------------|---------|
| `scripts/bootstrap-test-windows.cmd` | Launches the full stack, waits for readiness, seeds data |
| `scripts/verify-deploy.cmd`     | Performs health checks (containers, HTTP endpoints, Postgres, indices) |
| `scripts/reset-stack.cmd`       | Stops and removes all stack containers, volumes, and networks |

---

## ✅ Next Steps

- Build ingestion pipeline for real-time transcripts  
- Harden security (TLS, auth, backups)  
- Deploy to staging/production Kubernetes or cloud stack

