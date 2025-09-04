# KWVE Logger Transcriptions

On‑prem, containerized platform for ingesting hourly "air‑log" recordings from the KWVE broadcast logger,
transcribing them with timestamps/diarization, and indexing transcripts for fast search by date, time, show,
phrase, and speaker. Audio is retained short‑term; transcripts and metadata are searchable and retained longer.

## Features (v1)
- **Ingestion-first** design: drop completed hour files; they’re queued and processed.
- **Storage**: MinIO (S3) for audio + artifacts (TXT/SRT/VTT/JSON).
- **Index**: PostgreSQL (metadata) + OpenSearch (full-text + highlights).
- **Retention**: lifecycle rules for audio (e.g., 60–90 days), keep transcripts longer.
- **Security**: OIDC-ready (Entra ID) via the future API/UI (not included in this scaffold).

## What’s in this repo
- `docs/ARCHITECTURE.md` — System diagram & data flows.
- `docs/ROADMAP.md` — Phased delivery plan.
- `infra/docker-compose.yml` — Dev/lab stack: Postgres, OpenSearch, OpenSearch Dashboards, MinIO, Redis.
- `schemas/` — JSON Schemas for transcripts and assets.
- `sql/` — Initial DB schema and index template for OpenSearch + sample inserts.
- `sample-data/` — Example hour transcript + TXT/VTT and a tiny MP3 placeholder.
- `policies/` — Example retention policy YAML.

## Quick start (lab/dev)
1. Install Docker Desktop or Docker Engine.
2. Copy `.env.example` → `.env` and edit passwords/ports if needed.
3. `docker compose -f infra/docker-compose.yml up -d`
4. Initialize database and OpenSearch index:
   ```bash
   docker compose -f infra/docker-compose.yml exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /sql/001_init.sql
   docker compose -f infra/docker-compose.yml exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /sql/090_sample_inserts.sql
   curl -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" -X PUT "http://localhost:$OPENSEARCH_PORT/kwve-transcripts" -H 'Content-Type: application/json' --data-binary @sql/opensearch_index_template.json
   curl -u "$OPENSEARCH_USERNAME:$OPENSEARCH_PASSWORD" -X POST "http://localhost:$OPENSEARCH_PORT/kwve-transcripts/_doc/kwve:2025-09-04T09:00:00Z" -H 'Content-Type: application/json' --data-binary @sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json
   ```
5. Open **OpenSearch Dashboards**: http://localhost:5601 (user/pass from `.env`). Add the `kwve-transcripts` index and try a search.

> Note: The **API/UI** and **GPU ASR worker** are separate repos/services you’ll add later. This scaffold focuses on data plane and storage/indexing.

## Retention defaults (edit per policy)
- Audio objects: 60 days (example) via MinIO lifecycle rules.
- Transcripts/metadata: indefinite or 2 years+ depending on policy.

## License
MIT (adjust as needed).
