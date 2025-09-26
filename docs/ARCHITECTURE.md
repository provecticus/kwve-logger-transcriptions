# Architecture

## Components
- **Ingestion Watcher** (to be built): detects completed hourly air-log files and uploads them to MinIO; enqueues a job in Redis with metadata.
- **ASR Worker** (to be built): GPU container running faster-whisper + WhisperX (+ diarization). Produces transcripts + artifacts.
- **Storage**: MinIO for audio and artifacts; lifecycle rules remove audio after retention.
- **Metadata**: PostgreSQL stores assets, transcript metadata, retention flags, legal holds.
- **Search Index**: OpenSearch holds full-text with highlights and (optionally) vector embeddings.
- **API/UI** (to be built): OIDC-protected interface for search, playback links, exports, and admin.

## Data Flow
1. Logger closes hourly file (e.g., 09:00-10:00). 
2. Watcher uploads to `minio://kwve-radio/radio/KWVE/2025/09/04/09-00-00.wav` and pushes a job `{asset_id, start_ts, duration, sha256, codec}` to Redis.
3. ASR Worker pulls job, transcribes, writes artifacts (JSON/TXT/SRT/VTT) to MinIO.
4. Indexer writes metadata to PostgreSQL and a full-text document to OpenSearch.
5. Retention engine (cron) deletes expired audio and records a deletion event; transcripts remain.

## Identifiers
- `asset_id` format: `radio:<CALLSIGN>:<UTC_ISO_START>` e.g., `radio:KWVE:2025-09-04T09:00:00Z`.

## Security
- OIDC login (Entra ID) at API; per-role access.
- All services internal-only; expose only API and Dashboards via reverse proxy with TLS.

## Backups
- Nightly Postgres dump, MinIO replication (optional offsite), OpenSearch snapshot repository.
