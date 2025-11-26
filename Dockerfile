# Production Dockerfile using pytorch/pytorch base image
# WhisperX with PyTorch 2.5.1 and CUDA 12.1 (no CUDA 12.8)
FROM pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Strategy: Pin PyTorch 2.5.1 explicitly, then install WhisperX with constraints
# This prevents WhisperX from upgrading PyTorch to 2.8.0

# Step 1: Explicitly ensure PyTorch 2.5.1+cu121 is installed and pinned
RUN pip install --no-cache-dir --upgrade-strategy only-if-needed \
    "torch==2.5.1+cu121" \
    "torchaudio==2.5.1+cu121" \
    --extra-index-url https://download.pytorch.org/whl/cu121

# Step 2: Create a constraints file to prevent PyTorch upgrade
RUN echo "torch==2.5.1+cu121" > /tmp/constraints.txt && \
    echo "torchaudio==2.5.1+cu121" >> /tmp/constraints.txt

# Step 3: Install WhisperX with --no-deps to prevent PyTorch upgrade
RUN pip install --no-cache-dir --no-deps whisperx==3.7.4

# Step 4: Install WhisperX dependencies manually, excluding torch/torchaudio
# This allows us to control which CUDA version gets installed
RUN pip install --no-cache-dir \
    --constraint /tmp/constraints.txt \
    --extra-index-url https://download.pytorch.org/whl/cu121 \
    ctranslate2>=4.5.0 \
    faster-whisper>=1.1.1 \
    transformers>=4.48.0 \
    nltk>=3.9.1 \
    "numpy>=2.0.2,<2.1.0" \
    "pandas>=2.2.3,<2.3.0" \
    "av<16.0.0" \
    "pyannote-audio>=3.3.2,<4.0.0"

# Step 5: Install triton 3.5.1 separately (WhisperX requirement)
# Pin to 3.5.1 - tested and confirmed working with PyTorch 2.5.1
# Must be separate because pip's resolver conflicts with constraints, but runtime works fine
RUN pip install --no-cache-dir --upgrade "triton==3.5.1; sys_platform == 'linux' and platform_machine == 'x86_64'" || echo "Triton install failed but may not be critical"

# Step 6: Install FastAPI and API dependencies
RUN pip install --no-cache-dir \
    fastapi>=0.115.0 \
    "uvicorn[standard]>=0.30.0" \
    python-multipart>=0.0.9

# Add PyTorch's bundled cuDNN libraries to LD_LIBRARY_PATH
# Per WhisperX troubleshooting guide: PyTorch comes bundled with cuDNN libraries
# that need to be in LD_LIBRARY_PATH for WhisperX to find them
# The path varies by Python version - detect it dynamically
RUN PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") && \
    CUDNN_PATH=$(python -c "import site; print(site.getsitepackages()[0])")/nvidia/cudnn/lib && \
    if [ -d "$CUDNN_PATH" ]; then \
        echo "Found cuDNN path: $CUDNN_PATH" && \
        echo "export LD_LIBRARY_PATH=$CUDNN_PATH:\${LD_LIBRARY_PATH}" >> /etc/profile.d/cudnn.sh && \
        export LD_LIBRARY_PATH=$CUDNN_PATH:${LD_LIBRARY_PATH}; \
    else \
        echo "Warning: cuDNN path not found at $CUDNN_PATH, main.py will handle it dynamically"; \
    fi

# Copy application code
COPY app/ .

# Expose API port
EXPOSE 8000

# Run the API with production settings
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
