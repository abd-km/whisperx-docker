#!/bin/bash

# WhisperX API Quick Start Script

set -e

echo "╔════════════════════════════════════════╗"
echo "║     WhisperX API - Quick Start         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    echo "   Install from: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if HF_TOKEN is set
if [ -z "$HF_TOKEN" ]; then
    echo "⚠️  Warning: HF_TOKEN environment variable not set"
    echo "   Diarization will not work without it"
    echo ""
    read -p "Do you want to enter your Hugging Face token now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your HF_TOKEN: " HF_TOKEN
        export HF_TOKEN
    fi
fi

# Check for GPU support
echo "🔍 Checking for GPU support..."
if command -v nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU detected"
    GPU_FLAG="--gpus all"
    WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
else
    echo "⚠️  No GPU detected, will run on CPU (slower)"
    GPU_FLAG=""
    WHISPER_MODEL="${WHISPER_MODEL:-base}"
fi

echo ""
echo "📋 Configuration:"
echo "   Model: $WHISPER_MODEL"
echo "   GPU: ${GPU_FLAG:-CPU mode}"
echo "   Diarization: ${HF_TOKEN:+Enabled}"
echo ""

# Build image
echo "🔨 Building Docker image..."
docker build -t whisperx-api:latest . || {
    echo "❌ Build failed"
    exit 1
}

echo ""
echo "✅ Build successful!"
echo ""

# Stop existing container if running
if [ "$(docker ps -q -f name=whisperx-api)" ]; then
    echo "🛑 Stopping existing container..."
    docker stop whisperx-api
    docker rm whisperx-api
fi

# Run container
echo "🚀 Starting WhisperX API..."
docker run -d \
    --name whisperx-api \
    $GPU_FLAG \
    -p 8000:8000 \
    -e HF_TOKEN="$HF_TOKEN" \
    -e WHISPER_MODEL="$WHISPER_MODEL" \
    -v whisperx-models:/root/.cache \
    --restart unless-stopped \
    whisperx-api:latest

echo ""
echo "⏳ Waiting for API to be ready..."
sleep 5

# Wait for health check
MAX_RETRIES=12
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ API is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "   Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ API failed to start. Check logs with: docker logs whisperx-api"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║       🎉 WhisperX API is Running!      ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "📡 API Endpoints:"
echo "   • Swagger UI: http://localhost:8000/docs"
echo "   • Health: http://localhost:8000/health"
echo "   • Transcribe: http://localhost:8000/transcribe/"
echo ""
echo "📝 Test the API:"
echo "   python test_api.py your_audio.mp3"
echo ""
echo "📊 View logs:"
echo "   docker logs -f whisperx-api"
echo ""
echo "🛑 Stop the API:"
echo "   docker stop whisperx-api"
echo ""

