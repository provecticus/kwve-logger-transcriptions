import os, time, io, json, datetime, hashlib
from urllib.parse import quote
from minio import Minio
from minio.error import S3Error
from faster_whisper import WhisperModel
from opensearchpy import OpenSearch

# -------- config from env --------
INPUT_PREFIX      = os.getenv("ASR_INPUT_PREFIX", "incoming/")
ARTIFACT_PREFIX   = os.getenv("ASR_ARTIFACT_PREFIX", "artifacts/")
OS_INDEX          = os.getenv("OS_INDEX", "kwve-transcripts")
POLL_INTERVAL     = int(os.getenv("ASR_POLL_INTERVAL_SEC", "20"))

ASR_MODEL         = os.getenv("ASR_MODEL", "base.en")
ASR_BEAM_SIZE     = int(os.getenv("ASR_BEAM_SIZE", "5"))
ASR_VAD           = os.getenv("ASR_VAD", "false").lower() == "true"

# MinIO from .env (compose in-cluster)
MINIO_ENDPOINT    = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_SECURE      = os.getenv("MINIO_SECURE", "false").lower() == "true"
MINIO_ACCESS      = os.getenv("MINIO_ROOT_USER")
MINIO_SECRET      = os.getenv("MINIO_ROOT_PASSWORD")
MINIO_BUCKET      = os.getenv("MINIO_BUCKET", "kwve-radio")

# OpenSearch in-cluster (auth disabled in your dev compose; leave creds blank)
OS_URL            = os.getenv("OPENSEARCH_URL", "http://opensearch:9200")
OS_USER           = os.getenv("OPENSEARCH_USERNAME") or None
OS_PASS           = os.getenv("OPENSEARCH_PASSWORD") or None

AUDIO_EXTS = (".wav", ".mp3", ".flac", ".m4a", ".aac", ".ogg")

# -------- clients --------
minio_client = Minio(MINIO_ENDPOINT, access_key=MINIO_ACCESS, secret_key=MINIO_SECRET, secure=MINIO_SECURE)

os_kwargs = {"hosts": [OS_URL]}
if OS_USER and OS_PASS:
    os_kwargs.update(basic_auth=(OS_USER, OS_PASS))
os_client = OpenSearch(**os_kwargs)

# -------- util --------
def obj_exists(bucket, obj):
    try:
        minio_client.stat_object(bucket, obj)
        return True
    except S3Error:
        return False

def put_text(bucket, key, text, content_type="text/plain"):
    data = text.encode("utf-8")
    minio_client.put_object(bucket, key, io.BytesIO(data), length=len(data), content_type=content_type)

def srt_from_segments(segments):
    # very simple SRT writer with pysrt-like format (no number formatting drift)
    lines = []
    for i, seg in enumerate(segments, start=1):
        start = seg["start"]
        end = seg["end"]
        def to_ts(sec):
            ms = int((sec - int(sec)) * 1000)
            s = int(sec) % 60
            m = (int(sec) // 60) % 60
            h = int(sec) // 3600
            return f"{h:02}:{m:02}:{s:02},{ms:03}"
        lines.append(f"{i}")
        lines.append(f"{to_ts(start)} --> {to_ts(end)}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)

def vtt_from_segments(segments):
    lines = ["WEBVTT", ""]
    for seg in segments:
        start = seg["start"]; end = seg["end"]
        def to_ts(sec):
            ms = int((sec - int(sec)) * 1000)
            s = int(sec) % 60
            m = (int(sec) // 60) % 60
            h = int(sec) // 3600
            return f"{h:02}:{m:02}:{s:02}.{ms:03}"
        lines.append(f"{to_ts(start)} --> {to_ts(end)}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)

def build_asset_id(station, utc_start):
    return f"radio:{station}:{utc_start}"

def index_transcript(doc_id, payload):
    os_client.index(index=OS_INDEX, id=doc_id, document=payload, refresh=True)

# -------- ASR model (CPU) --------
model = WhisperModel(ASR_MODEL, device="cpu", compute_type="int8")

# -------- main loop --------
def main():
    # ensure bucket exists
    found = any(b.name == MINIO_BUCKET for b in minio_client.list_buckets())
    if not found:
        minio_client.make_bucket(MINIO_BUCKET)

    print(f"[ASR] Watching s3://{MINIO_BUCKET}/{INPUT_PREFIX}  every {POLL_INTERVAL}s")
    while True:
        try:
            for obj in minio_client.list_objects(MINIO_BUCKET, prefix=INPUT_PREFIX, recursive=True):
                name = obj.object_name
                lname = name.lower()
                if not lname.endswith(AUDIO_EXTS):
                    continue
                # skip if already processed
                marker = f"{name}.done"
                if obj_exists(MINIO_BUCKET, marker):
                    continue

                print(f"[ASR] New audio: {name}")
                # download to /tmp
                data = minio_client.get_object(MINIO_BUCKET, name)
                audio_path = f"/tmp/{os.path.basename(name)}"
                with open(audio_path, "wb") as f:
                    for d in data.stream(32*1024):
                        f.write(d)
                data.close(); data.release_conn()

                # derive minimal metadata from path (customize to your logger naming)
                # e.g., incoming/KWVE/2025-09-04/09-00-00.sample.mp3
                parts = name.split("/")
                station = parts[1] if len(parts) > 1 else "KWVE"
                # naive time; production should parse from filename or external metadata
                utc_start = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
                asset_id = build_asset_id(station, utc_start)

                # transcribe
                segs = []
                text_buf = []
                options = {"beam_size": ASR_BEAM_SIZE}
                if ASR_VAD: options["vad_filter"] = True
                print(f"[ASR] Transcribing {audio_path} model={ASR_MODEL}")
                segments, info = model.transcribe(audio_path, **options)
                for s in segments:
                    seg = {"start": float(s.start), "end": float(s.end), "text": s.text.strip()}
                    segs.append(seg)
                    text_buf.append(s.text.strip())

                full_text = " ".join(text_buf).strip()

                # write artifacts to MinIO
                art_base = f"{ARTIFACT_PREFIX}{asset_id}/"
                txt_key = f"{art_base}{asset_id}.txt"
                srt_key = f"{art_base}{asset_id}.srt"
                vtt_key = f"{art_base}{asset_id}.vtt"
                json_key = f"{art_base}{asset_id}.json"

                put_text(MINIO_BUCKET, txt_key, full_text, "text/plain")
                put_text(MINIO_BUCKET, srt_key, srt_from_segments(segs), "application/x-subrip")
                put_text(MINIO_BUCKET, vtt_key, vtt_from_segments(segs), "text/vtt")

                # build transcript JSON to index (align with your template)
                payload = {
                    "asset_id": asset_id,
                    "source": "logger",
                    "station": station,
                    "program": None,
                    "utc_start": utc_start,
                    "utc_end": None,
                    "duration_sec": int(info.duration) if getattr(info, "duration", None) else None,
                    "text": full_text,
                    "speakers": ["unknown"],
                    "keywords": [],
                }
                # index into OpenSearch
                index_transcript(asset_id, payload)

                # store the JSON artifact
                put_text(MINIO_BUCKET, json_key, json.dumps(payload, ensure_ascii=False, indent=2), "application/json")

                # mark done
                put_text(MINIO_BUCKET, marker, "ok", "text/plain")
                print(f"[ASR] Completed {asset_id} (wrote artifacts under {art_base})")

                # cleanup
                try: os.remove(audio_path)
                except: pass

        except Exception as e:
            print(f"[ASR] ERROR: {e}")

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
