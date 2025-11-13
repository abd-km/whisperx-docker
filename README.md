# WhisperX API - Production-Ready Deployment

A containerized FastAPI service for audio transcription using WhisperX with **alignment** and **speaker diarization**.

## Features

- 🎯 **Transcription**: High-quality speech-to-text using WhisperX
- 🎵 **Word-Level Alignment**: Precise timestamps for each word
- 👥 **Speaker Diarization**: Identify and label different speakers
- 🚀 **GPU Accelerated**: CUDA support for fast processing
- 🐳 **Docker Ready**: Fully containerized for easy deployment
- 📊 **Batch Processing**: Handle multiple files simultaneously

---

## Quick Start

### Prerequisites

1. **Docker** installed
2. **NVIDIA Docker** (for GPU support)
3. **Hugging Face Token** (required for diarization)

### Get Hugging Face Token

1. Create account at [huggingface.co](https://huggingface.co)
2. Go to Settings → Access Tokens → Create new token
3. Accept user agreement for [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)

---

## Build & Run

### 1. Build Docker Image

```bash
docker build -t whisperx-api .
```

### 2. Run with GPU Support

```bash
docker run --gpus all \
  -p 8000:8000 \
  -e HF_TOKEN="your_huggingface_token_here" \
  -e WHISPER_MODEL="large-v3" \
  whisperx-api
```

### 3. Run without GPU (CPU mode)

```bash
docker run \
  -p 8000:8000 \
  -e HF_TOKEN="your_huggingface_token_here" \
  -e WHISPER_MODEL="base" \
  whisperx-api
```

---

## API Documentation

Once running, visit:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Endpoints

#### 1. Health Check
```bash
curl http://localhost:8000/health
```

#### 2. Transcribe Audio (Basic)
```bash
curl -X POST "http://localhost:8000/transcribe/" \
  -F "file=@audio.mp3"
```

#### 3. Transcribe with Alignment
```bash
curl -X POST "http://localhost:8000/transcribe/?align=true" \
  -F "file=@audio.mp3"
```

#### 4. Transcribe with Diarization
```bash
curl -X POST "http://localhost:8000/transcribe/?align=true&diarize=true" \
  -F "file=@audio.mp3"
```

#### 5. Batch Processing
```bash
curl -X POST "http://localhost:8000/transcribe/batch/?align=true&diarize=true" \
  -F "files=@audio1.mp3" \
  -F "files=@audio2.mp3"
```

---

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `HF_TOKEN` | Hugging Face API token | - | Yes (for diarization) |
| `WHISPER_MODEL` | WhisperX model size | `large-v3` | No |
| `CUDA_VISIBLE_DEVICES` | GPU device IDs | `0` | No |

### Available Models

- `tiny`, `base`, `small`, `medium`, `large-v1`, `large-v2`, `large-v3`
- Larger models = better accuracy but slower
- For CPU deployment, use `base` or `small`

---

## Response Format

```json
{
  "text": "Full transcription text here.",
  "segments": [
    {
      "start": 0.0,
      "end": 2.5,
      "text": "Hello world",
      "speaker": "SPEAKER_00"
    }
  ],
  "word_segments": [
    {
      "word": "Hello",
      "start": 0.0,
      "end": 0.5,
      "score": 0.95
    }
  ],
  "language": "en"
}
```

---

## Production Deployment

### Docker Compose (Recommended)

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  whisperx-api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - HF_TOKEN=${HF_TOKEN}
      - WHISPER_MODEL=large-v3
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped
```

Run with:
```bash
export HF_TOKEN="your_token_here"
docker-compose up -d
```

### Kubernetes Deployment

See `k8s/` directory for example manifests (if needed, let me know and I can add them).

---

## Performance Tips

1. **GPU is highly recommended** for production workloads
2. Use smaller models (`base`/`small`) for faster processing if accuracy allows
3. Adjust `BATCH_SIZE` in code based on GPU memory
4. For high concurrency, deploy multiple instances behind a load balancer
5. Consider using persistent storage for model caching

---

## Troubleshooting

### Out of Memory Errors
- Reduce model size or batch size
- Use CPU mode: Remove `--gpus all` flag

### Diarization Not Working
- Verify `HF_TOKEN` is set correctly
- Ensure you accepted pyannote.audio license agreement

### Slow Performance
- Check GPU is being used: Look for `device: cuda` in health check
- Reduce model size for faster inference

---

## Development

### Local Development (without Docker)

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r app/requirements.txt

# Set environment variables
export HF_TOKEN="your_token_here"
export WHISPER_MODEL="base"

# Run server
cd app
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

---

## License

This project uses WhisperX and pyannote.audio. Please review their respective licenses:
- WhisperX: [License](https://github.com/m-bain/whisperX)
- pyannote.audio: [License](https://github.com/pyannote/pyannote-audio)

---

## Support

For issues or questions:
1. Check the [WhisperX documentation](https://github.com/m-bain/whisperX)
2. Review API docs at `/docs` endpoint
3. Check container logs: `docker logs <container_id>`

---

**Ready to deploy!** 🚀 Hand this off to DevOps with the Dockerfile and they can deploy it anywhere.

