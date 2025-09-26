# KWVE Logger Transcriptions - QUICK CARD (Operator)

> One-page, step-by-step: start the system, upload audio, get a transcript visible in the UI.
> Current build: **OpenSearch + Dashboards + Postgres + MinIO**. ASR worker will be added next; this quick card includes a **temporary test path** so you can verify the search UI end-to-end today.

---

## A) Start / Verify

1) From the repo root (Windows CMD):
```
scripts\reset-stack.cmd
scripts\bootstrap-test-windows.cmd
scripts\verify-deploy.cmd
```
You want `RESULT: PASS`. If anything fails, open the log under `scripts\logs\` and follow the hint lines.

---

## B) Upload audio to MinIO

1) Open MinIO Console:
```
http://localhost:$19001/    (e.g., 19001)
```
2) Login with:
```
MINIO_ROOT_USER / MINIO_ROOT_PASSWORD   (from infra/.env)
```
3) Open or create bucket (e.g., `kwve-radio`).
4) **Upload your audio file** (WAV/MP3) into a folder of your choice (e.g., `radio/2025-09-04/`).

> This stores audio and artifacts but does not yet transcribe automatically (ASR worker comes next). The next step lets you test the search UI today.

---

## C) (TEMPORARY) Create a transcript for testing

Until the ASR worker is wired in, use **one** of these simple test paths to see the UI working end-to-end.

### Option 1 - Use the sample transcript already in the repo
1) Seed the index & sample doc (if not already present). From repo root:
```
curl -s -X PUT "http://localhost:$19220/kwve-transcripts"

curl -s -H "Content-Type: application/json" ^
  -X POST "http://localhost:$19220/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
  --data-binary @sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json
```
2) Verify:
```
curl -s -o NUL -w "IDX=%{http_code}\n" "http://localhost:$19220/kwve-transcripts"
curl -s -o NUL -w "DOC=%{http_code}\n" "http://localhost:$19220/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z"
```
You should see `IDX=200` and `DOC=200`.

### Option 2 - Create a quick transcript from a TXT file
If you have a TXT file with the dialog (e.g., `myshow.txt`), convert it into a minimal JSON and index it:

1) Create `temp\myshow.json` with this content (adjust fields):
```json
{
  "asset_id": "radio:KWVE:2025-09-04T09:00:00Z",
  "station": "KWVE",
  "source": "logger",
  "utc_start": "2025-09-04T09:00:00Z",
  "utc_end": "2025-09-04T10:00:00Z",
  "duration_sec": 3600,
  "text": "<<PASTE CONTENTS OF myshow.txt HERE>>",
  "speakers": ["unknown"],
  "keywords": []
}
```
2) Index it:
```
curl -s -H "Content-Type: application/json" ^
  -X POST "http://localhost:$19220/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z" ^
  --data-binary @temp/myshow.json
```

> Either option gives you searchable content immediately. The ASR worker will later produce JSON like this automatically from the audio you uploaded to MinIO.

---

## D) Search the transcript in Dashboards

1) Open Dashboards UI:
```
http://localhost:$15601/   (e.g., 15601)
```
2) First time only: **Stack Management → Index Patterns** → add `kwve-transcripts*`.
3) Go to **Discover**:
   - Use the search bar for words/phrases.
   - Add filters on fields like `station`, `utc_start`.
   - Adjust the time picker to the hour/day of your transcript.

You should now see your text with highlights and fields.

---

## E) What happens next (full pipeline)

- **Planned ASR worker (Phase 2):** A containerized worker (CPU/GPU) watches MinIO or a queue, runs automatic speech recognition (e.g., faster-whisper/whisper.cpp), generates artifacts (TXT/SRT/VTT/JSON), writes transcript JSON to OpenSearch (and metadata to Postgres).

If you want to test the **first cut** ASR worker now, ask for the add-on compose service and we'll wire a simple CPU worker that reads a local file and indexes JSON automatically (good enough for a lab demo).

---

## URLs & Ports (from infra/.env)

- **OpenSearch:** `http://localhost:$19220/`  
- **Dashboards:** `http://localhost:$15601/`  
- **MinIO Console:** `http://localhost:$19001/`  
- **MinIO API:** `http://localhost:$19000/`  
- **Postgres:** `localhost:$15432` / DB `$kwve_logs`

---

## Handy commands

- Verify everything:
```
scripts\verify-deploy.cmd
```
- Logs:
```
pushd infra
docker compose logs --since=5m opensearch
docker compose logs --since=5m dashboards
docker compose logs --since=5m minio
docker compose logs --since=5m postgres
popd
```
- Reset → Bootstrap → Verify:
```
scripts\reset-stack.cmd
scripts\bootstrap-test-windows.cmd
scripts\verify-deploy.cmd
```
