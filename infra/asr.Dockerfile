FROM python:3.11-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Python deps
# faster-whisper pulls PyTorch CPU wheels automatically; this stays CPU.
# minio: S3 client; opensearch-py: OS client; srt/vtt generation libs are simple.
RUN pip install --no-cache-dir \
    faster-whisper==1.0.3 \
    minio==7.2.8 \
    opensearch-py==2.6.0 \
    pysrt==1.1.2 \
    webvtt-py==0.4.6

# App
WORKDIR /app/asr
COPY asr/worker.py /app/asr/worker.py

ENTRYPOINT ["python", "/app/asr/worker.py"]
