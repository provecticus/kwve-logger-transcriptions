-- 001_init.sql
CREATE TABLE IF NOT EXISTS assets (
  id TEXT PRIMARY KEY,                  -- asset_id e.g., radio:KWVE:2025-09-04T09:00:00Z
  source TEXT NOT NULL,                 -- 'radio'
  station TEXT NOT NULL,                -- 'KWVE'
  program TEXT,                         -- optional show/program name
  utc_start TIMESTAMPTZ NOT NULL,
  utc_end   TIMESTAMPTZ NOT NULL,
  duration_sec INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  codec TEXT,
  sample_rate INTEGER,
  channels INTEGER,
  minio_object TEXT NOT NULL,           -- s3 key
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  retention_expiry_ts TIMESTAMPTZ,
  legal_hold BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_assets_start ON assets(utc_start);
CREATE INDEX IF NOT EXISTS idx_assets_station ON assets(station);

CREATE TABLE IF NOT EXISTS transcripts (
  asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
  language TEXT DEFAULT 'en',
  wer_est REAL,
  diarization JSONB,
  keywords TEXT[],
  has_pii BOOLEAN DEFAULT FALSE,
  json_uri TEXT NOT NULL,   -- MinIO path to rich JSON
  txt_uri  TEXT NOT NULL,   -- MinIO path to plain text
  srt_uri  TEXT,            -- MinIO path to SRT
  vtt_uri  TEXT,            -- MinIO path to VTT
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS segments (
  asset_id TEXT REFERENCES assets(id) ON DELETE CASCADE,
  seg_index INTEGER,
  t_start DOUBLE PRECISION,
  t_end   DOUBLE PRECISION,
  speaker TEXT,
  text    TEXT,
  PRIMARY KEY(asset_id, seg_index)
);

-- Deletion ledger (for defensible destruction of audio)
CREATE TABLE IF NOT EXISTS deletion_events (
  id BIGSERIAL PRIMARY KEY,
  asset_id TEXT NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor TEXT DEFAULT 'system',
  details TEXT
);
