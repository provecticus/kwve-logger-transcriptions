# KWVE Logger Transcriptions - Bootstrap Testing & Deployment Guide

This document provides step-by-step instructions for testing and
deploying the Phase 0 (Bootstrap) scaffold of the KWVE Logger
Transcriptions system. The goal is to bring up the Docker stack,
initialize the database and index, load sample data, and verify that the
system is functional.

## Step 1 --- Prepare Your Environment

\- Install Docker Desktop (Windows/Mac) or Docker Engine (Linux).\
- Clone this repository locally.\
- Copy \`.env.example\` to \`.env\` and edit passwords, ports, and
credentials as needed.

Example \`.env\` configuration:

POSTGRES_USER=kwve\
POSTGRES_PASSWORD=secret\
POSTGRES_DB=kwve\
POSTGRES_PORT=5432\
OPENSEARCH_USERNAME=admin\
OPENSEARCH_PASSWORD=admin\
OPENSEARCH_PORT=9200\
MINIO_ROOT_USER=minio\
MINIO_ROOT_PASSWORD=minio123

## Step 2 --- Bring Up the Stack

Run the following command to start the Docker stack:

docker compose -f infra/docker-compose.yml up -d

This launches Postgres, OpenSearch, OpenSearch Dashboards, MinIO, and
Redis.\
To check logs if anything fails, run:

docker compose -f infra/docker-compose.yml logs -f

## Step 3 --- Initialize Database & Index

Load schema and sample inserts into Postgres:

docker compose -f infra/docker-compose.yml exec postgres \\\
psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -f /sql/001_init.sql\
\
docker compose -f infra/docker-compose.yml exec postgres \\\
psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -f
/sql/090_sample_inserts.sql

Install the OpenSearch index template:

curl -u \"\$OPENSEARCH_USERNAME:\$OPENSEARCH_PASSWORD\" \\\
-X PUT
\"http://localhost:\$OPENSEARCH_PORT/\_index_template/kwve-transcripts-template\"
\\\
-H \'Content-Type: application/json\' \\\
\--data-binary \@infra/opensearch_index_template.json

Load sample transcript into OpenSearch:

curl -u \"\$OPENSEARCH_USERNAME:\$OPENSEARCH_PASSWORD\" \\\
-X POST
\"http://localhost:\$OPENSEARCH_PORT/kwve-transcripts/\_doc/radio:KWVE:2025-09-04T09:00:00Z\"
\\\
-H \'Content-Type: application/json\' \\\
\--data-binary
\@sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json

## Step 4 --- Verify in OpenSearch Dashboards

\- Open: http://localhost:5601\
- Login with credentials from \`.env\`.\
- Add \`kwve-transcripts\` as an index pattern.\
- Run a search by phrase or timestamp to validate.

## Step 5 --- Validate Storage & Retention

\- Open MinIO console at http://localhost:9000 (credentials from
\`.env\`).\
- Check audio/transcript objects in MinIO.\
- Ensure lifecycle policy (\`retention.yaml\`) is configured to expire
audio in \~60 days.

## Next Steps (Optional)

\- Add real logger recordings into MinIO manually for testing.\
- Extend Docker Compose to mount a directory for dropping test WAV
files.\
- Proceed to Phase 1 (Ingestion Watcher) and Phase 2 (ASR Worker).


---

## Windows CMD Quick Start Script

For Windows users, you can automate the entire bootstrap process with the provided batch file:

1. Save the following as `bootstrap-test-windows.cmd` in the project root (next to `.env`).  
2. Double-click to run, or execute in a `cmd.exe` window.

```bat
@echo off
REM ==========================================================
REM KWVE Logger Transcriptions - Bootstrap Test (Windows CMD)
REM ==========================================================

echo Starting KWVE Logger Transcriptions stack...

REM Bring up Docker stack with explicit env file
docker compose -f infra\docker-compose.yml --env-file .env up -d

echo Initializing Postgres schema...
docker compose -f infra\docker-compose.yml exec postgres psql -U kwve -d kwve -f /sql/001_init.sql
docker compose -f infra\docker-compose.yml exec postgres psql -U kwve -d kwve -f /sql/090_sample_inserts.sql

echo Loading OpenSearch index template...
curl -u admin:admin -X PUT http://localhost:9200/_index_template/kwve-transcripts-template ^
  -H "Content-Type: application/json" ^
  --data-binary @sql/opensearch_index_template.json

echo Loading sample transcript...
curl -u admin:admin -X POST http://localhost:9200/kwve-transcripts/_doc/radio:KWVE:2025-09-04T09:00:00Z ^
  -H "Content-Type: application/json" ^
  --data-binary @sample-data/radio/2025-09-04/2025-09-04T09-00-00Z.sample-transcript.json

echo All steps completed. Open http://localhost:5601 to verify in OpenSearch Dashboards.
pause
```

This script ensures `.env` is loaded correctly and uses Windows CMD syntax (`^` for line breaks instead of `\`).

