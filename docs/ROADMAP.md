# Roadmap

## Phase 0 — Bootstrap (this repo)
- Docker Compose stack: Postgres, OpenSearch, OpenSearch Dashboards, MinIO, Redis.
- DB schema + OpenSearch index + sample data.
- Documentation: Architecture, operations basics.

## Phase 1 — Ingestion service
- Linux watcher to detect complete hourly files and push to MinIO.
- Job enqueue (Redis) with metadata (station, UTC start/end, codec, checksum).
- Operational metrics (queue depth, failures).

## Phase 2 — ASR worker (GPU)
- faster-whisper + WhisperX + diarization (pyannote) integration.
- Emit JSON with word timestamps + speakers; generate TXT/SRT/VTT.
- Store artifacts in MinIO; write metadata to Postgres; index to OpenSearch.

## Phase 3 — Search API and UI
- FastAPI for query, exports, and auth (OIDC).
- Next.js UI: calendar/date → show → hour; search with highlights; jump-to-timestamp.
- Role-based access (Viewer/Admin); audit logging.

## Phase 4 — Retention & legal hold
- MinIO lifecycle rules (audio); deletion ledger.
- Legal-hold flag in DB; UI control; reports.

## Phase 5 — Hardening & HA
- TLS everywhere, backup/restore SOPs.
- Optional second OpenSearch node; read replica for Postgres.
- GPU worker autoscaling (multiple workers, multiple GPUs).
