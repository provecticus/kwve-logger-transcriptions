-- 090_sample_inserts.sql
INSERT INTO assets (id, source, station, program, utc_start, utc_end, duration_sec, sha256, codec, sample_rate, channels, minio_object, retention_expiry_ts)
VALUES (
  'radio:KWVE:2025-09-04T09:00:00Z',
  'radio',
  'KWVE',
  'Morning Show',
  '2025-09-04 09:00:00+00',
  '2025-09-04 10:00:00+00',
  3600,
  'd41d8cd98f00b204e9800998ecf8427e',
  'mp3',
  48000,
  2,
  'radio/KWVE/2025/09/04/09-00-00.sample.mp3',
  '2025-11-03 09:00:00+00'
) ON CONFLICT DO NOTHING;

INSERT INTO transcripts (asset_id, language, wer_est, diarization, keywords, has_pii, json_uri, txt_uri, srt_uri, vtt_uri)
VALUES (
  'radio:KWVE:2025-09-04T09:00:00Z',
  'en',
  0.08,
  jsonb_build_object('speakers', jsonb_build_array('S0','S1')),
  ARRAY['guest','segment','topic'],
  FALSE,
  'radio/KWVE/2025/09/04/09-00-00.sample-transcript.json',
  'radio/KWVE/2025/09/04/09-00-00.sample-transcript.txt',
  'radio/KWVE/2025/09/04/09-00-00.sample-transcript.srt',
  'radio/KWVE/2025/09/04/09-00-00.sample-transcript.vtt'
) ON CONFLICT DO NOTHING;

INSERT INTO segments (asset_id, seg_index, t_start, t_end, speaker, text) VALUES
  ('radio:KWVE:2025-09-04T09:00:00Z', 0, 125.37, 128.92, 'S0', 'You're listening to KWVE—Sharing Life, Delivering Truth, Giving Hope.'),
  ('radio:KWVE:2025-09-04T09:00:00Z', 1, 129.10, 134.02, 'S1', 'Good morning! Today we're joined by our special guest.');
