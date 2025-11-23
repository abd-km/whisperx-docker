# Use NVIDIA CUDA base image per WhisperX 3.7.4 pyproject.toml (CUDA 12.8 / cu128)
# WhisperX 3.7.4 explicitly uses pytorch index: download.pytorch.org/whl/cu128
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set LD_LIBRARY_PATH to include system library paths where cuDNN libraries are located
# /lib/x86_64-linux-gnu and /usr/lib/x86_64-linux-gnu are standard Debian/Ubuntu multiarch paths
# These paths are registered in /etc/ld.so.conf.d/ but need to be in LD_LIBRARY_PATH
# Note: This is architecture-specific (x86_64). For ARM64, paths would be /lib/aarch64-linux-gnu
ENV LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Set working directory
WORKDIR /app

# Install system dependencies (Python 3.12 is default for Ubuntu 24.04)
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

# Add PyTorch's bundled cuDNN libraries to LD_LIBRARY_PATH
# Per WhisperX troubleshooting guide: PyTorch comes bundled with cuDNN libraries
# that need to be in LD_LIBRARY_PATH for WhisperX to find them
# Reference: https://github.com/m-bain/whisperX/wiki/Troubleshooting#unable-to-load-cudnn-libraries
# The path is: /usr/local/lib/python3.12/dist-packages/nvidia/cudnn/lib/
# This ENV is set after pip install so PyTorch's cuDNN libraries are available
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/dist-packages/nvidia/cudnn/lib:${LD_LIBRARY_PATH}

# Create symlinks for cuDNN library versions that PyTorch looks for
# PyTorch bundles libcudnn_cnn.so.9 but looks for libcudnn_cnn.so.9.1.0, libcudnn_cnn.so.9.1, and libcudnn_cnn.so
# Creating symlinks ensures PyTorch can find the libraries regardless of which name it searches for
RUN CUDNN_LIB_DIR="/usr/local/lib/python3.12/dist-packages/nvidia/cudnn/lib" && \
    if [ -f "${CUDNN_LIB_DIR}/libcudnn_cnn.so.9" ]; then \
        cd "${CUDNN_LIB_DIR}" && \
        ln -sf libcudnn_cnn.so.9 libcudnn_cnn.so.9.1.0 2>/dev/null || true && \
        ln -sf libcudnn_cnn.so.9 libcudnn_cnn.so.9.1 2>/dev/null || true && \
        ln -sf libcudnn_cnn.so.9 libcudnn_cnn.so 2>/dev/null || true && \
        echo "Created cuDNN symlinks for PyTorch compatibility"; \
    else \
        echo "Warning: libcudnn_cnn.so.9 not found, skipping symlink creation"; \
    fi

# Copy application code
COPY app/ .

# Expose API port
EXPOSE 8000

# Run the API with production settings
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]

