# Use NVIDIA CUDA base image for GPU support (CUDA 12.8 per WhisperX 3.7.4)
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install system dependencies (Python 3.12 is default for Ubuntu 24.04)
# Note: libcudnn already included in base image
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies (--break-system-packages is safe in Docker containers)
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Copy application code
COPY app/ .

# Expose API port
EXPOSE 8000

# Run the API with production settings
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]

