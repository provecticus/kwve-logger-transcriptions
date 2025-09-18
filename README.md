# KWVE Logger Transcriptions — Infrastructure Scaffold

This repository contains the **infrastructure scaffold** for KWVE Logger Transcriptions, designed for quick lab/dev deployments. It brings up **Postgres**, **OpenSearch**, **MinIO**, and **Redis** with sample data and schemas, plus Windows helper scripts for bootstrap, verification, and reset.

---

## Repository Layout

```
kwve-logger-transcriptions/
│   .gitignore
│   README.md
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   ├── KWVE_Bootstrap_Testing_Guide.md
│   ├── KWVE_Quickstart_Deployment.md
│   └── KWVE_Scripts_Usage.md
│
├── infra/
│   ├── .env
│   ├── .env.example
│   └── docker-compose.yml
│
├── policies/
│   └── retention.yaml
│
├── sample-data/
│   └── radio/
│       └── 2025-09-04/
│           ├── 09-00-00.sample.mp3
│           ├── 2025-09-04T09-00-00Z.sample-transcript.json
│           ├── 2025-09-04T09-00-00Z.sample-transcript.srt
│           ├── 2025-09-04T09-00-00Z.sample-transcript.txt
│           └── 2025-09-04T09-00-00Z.sample-transcript.vtt
│
├── schemas/
│   ├── asset.schema.json
│   └── transcript.schema.json
│
├── scripts/
│   ├── bootstrap-test-windows.cmd
│   ├── reset-stack.cmd
│   ├── verify-deploy.cmd
│   └── logs/
│       └── verify-*.log
│
└── sql/
    ├── 001_init.sql
    ├── 090_sample_inserts.sql
    └── opensearch_index_template.json
```

- `infra/` — Docker Compose + environment files
- `scripts/` — helper scripts for bootstrap, verify, and reset
- `docs/` — architecture, roadmap, quickstart, bootstrap guide, scripts usage
- `schemas/` — JSON Schemas for assets and transcripts
- `sql/` — Postgres schema, inserts, and OpenSearch index template
- `sample-data/` — example hour transcript + TXT/VTT/SRT/VTT/JSON and a tiny MP3 placeholder
- `policies/` — example retention policy YAML

---

## Quick Start

### Prerequisites
- Windows 10/11 with **CMD** or **PowerShell**
- **Docker Desktop** installed and running
- `infra/.env` created (copy from `infra/.env.example` and edit creds/ports)

### Deployment Flow (Windows)
From the repo root:
```cmd
scripts\reset-stack.cmd
scripts\bootstrap-test-windows.cmd
scripts\verify-deploy.cmd
```

- **reset-stack.cmd** → Cleans all containers, volumes, networks (use if you want a clean slate)
- **bootstrap-test-windows.cmd** → Brings up stack, waits for services, seeds Postgres + OpenSearch
- **verify-deploy.cmd** → Checks container health, endpoints, index/doc presence, Postgres connectivity. Produces PASS/FAIL and logs.

### Expected Verification PASS
```
RESULT: PASS  (All checks successful)
Logs: scripts\logs\verify-YYYYMMDD-HHMMSS.log
```

---

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — overall system design
- [Roadmap](docs/ROADMAP.md) — planned features and phases
- [Bootstrap Testing Guide](docs/KWVE_Bootstrap_Testing_Guide.md) — original manual bootstrap process
- [Quickstart Deployment](docs/KWVE_Quickstart_Deployment.md) — streamlined guide for new deployments
- [Scripts Usage](docs/KWVE_Scripts_Usage.md) — detailed guide for `reset`, `bootstrap`, and `verify`

---

## Troubleshooting

- **`.env not found`** → ensure `infra/.env` exists; if compose expects a root `.env`, bootstrap will self-heal by copying.
- **HTTP 000 / 503 in verify** → services not ready; wait 30–60s and rerun.
- **Index/doc missing** → re-run bootstrap to seed OpenSearch.
- **Postgres fail** → check `POSTGRES_USER`/`POSTGRES_DB` in `infra/.env`; tail logs:
  ```cmd
  pushd infra
  docker compose logs --since=5m postgres
  popd
  ```
- **Container name conflict (`already in use`)** → run `scripts\reset-stack.cmd` to clear fixed-name containers.

---

## CI/CD Integration

- `verify-deploy.cmd` returns **exit codes**: `0` (pass), `1` (fail).
- Logs are written to `scripts/logs/verify-*.log`.
- Use this in pipelines to gate further automation.

---

## Notes

- This scaffold is **data-plane only**. API/UI and GPU ASR workers live in separate repos/services.
- Retention defaults are set in [policies/retention.yaml](policies/retention.yaml).
  - Audio objects: 60 days (example) via MinIO lifecycle rules
  - Transcripts/metadata: indefinite or 2+ years depending on policy
- You can adapt the scripts for PowerShell or Linux/Mac if needed — the flow remains: **reset → bootstrap → verify**.

---

## Scripts Quick Reference

| Script                     | Purpose                                                                 | When to Run                                         |
|-----------------------------|-------------------------------------------------------------------------|-----------------------------------------------------|
| `reset-stack.cmd`           | Aggressively tears down containers, networks, volumes, clears state     | If you want a clean slate, or hit container conflicts |
| `bootstrap-test-windows.cmd`| Brings up stack, waits for readiness, seeds Postgres + OpenSearch       | First-time setup, or after reset                    |
| `verify-deploy.cmd`         | Runs health/content checks with PASS/FAIL and logs to `scripts/logs/`   | After bootstrap, or any time you want to validate   |
