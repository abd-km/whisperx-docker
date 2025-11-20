# Use NVIDIA CUDA base image per WhisperX 3.7.4 pyproject.toml (CUDA 12.8 / cu128)
# WhisperX 3.7.4 explicitly uses pytorch index: download.pytorch.org/whl/cu128
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install system dependencies (Python 3.12 is default for Ubuntu 24.04)
# Note: cuDNN 9 is already included in the base image (12.8.0-cudnn-devel)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    ffmpeg \
    wget \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
# Use cu128 index per WhisperX 3.7.4 pyproject.toml specification
# --break-system-packages is safe and required in Docker with Ubuntu 24.04 (PEP 668)
RUN pip3 install --no-cache-dir --break-system-packages \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    -r requirements.txt

# Copy application code
COPY app/ .

# Expose API port
EXPOSE 8000

# Run the API with production settings
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]

