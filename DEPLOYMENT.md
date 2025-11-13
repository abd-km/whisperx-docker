# WhisperX API - DevOps Deployment Guide

This guide is for DevOps teams deploying the WhisperX API to production environments.

---

## 🚀 Quick Deploy

### Option 1: Docker Compose (Recommended for Quick Setup)

```bash
# 1. Clone/copy the project
cd whisperxd

# 2. Set your Hugging Face token
export HF_TOKEN="your_token_here"

# 3. Build and run
docker-compose up -d

# 4. Check status
docker-compose logs -f
```

### Option 2: Docker Run

```bash
# Build
docker build -t whisperx-api:latest .

# Run with GPU
docker run -d \
  --name whisperx-api \
  --gpus all \
  -p 8000:8000 \
  -e HF_TOKEN="your_token_here" \
  -e WHISPER_MODEL="large-v3" \
  --restart unless-stopped \
  whisperx-api:latest

# Check logs
docker logs -f whisperx-api
```

---

## 📋 Prerequisites

### Hardware Requirements

**Minimum (CPU-only):**
- 4 CPU cores
- 8GB RAM
- 10GB disk space

**Recommended (GPU):**
- NVIDIA GPU with 8GB+ VRAM (e.g., T4, V100, A10, RTX 3090)
- 8 CPU cores
- 16GB RAM
- 20GB disk space
- CUDA 11.8+

### Software Requirements

- Docker 20.10+
- Docker Compose 2.0+ (optional)
- NVIDIA Docker runtime (for GPU support)
- Linux kernel 5.0+ (recommended)

### API Keys

- **Hugging Face Token**: Required for speaker diarization
  - Sign up: https://huggingface.co/join
  - Get token: https://huggingface.co/settings/tokens
  - Accept license: https://huggingface.co/pyannote/speaker-diarization-3.1

---

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HF_TOKEN` | Yes* | - | Hugging Face API token (*required for diarization) |
| `WHISPER_MODEL` | No | `large-v3` | Model size: tiny, base, small, medium, large-v2, large-v3 |
| `CUDA_VISIBLE_DEVICES` | No | `0` | GPU device IDs (e.g., `0,1` for multi-GPU) |

### Model Selection Guide

| Model | VRAM | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| `tiny` | ~1GB | Very Fast | Low | Testing, demos |
| `base` | ~1GB | Fast | Medium | Low-latency production |
| `small` | ~2GB | Medium | Good | Balanced production |
| `medium` | ~5GB | Slow | Better | High-accuracy needs |
| `large-v2` | ~10GB | Very Slow | Best | Maximum accuracy |
| `large-v3` | ~10GB | Very Slow | Best | Latest model |

---

## 🏗️ Production Deployment Options

### Option 1: Standalone Server

```bash
# Build image
docker build -t whisperx-api:v1.0.0 .

# Run with resource limits
docker run -d \
  --name whisperx-api \
  --gpus all \
  -p 8000:8000 \
  -e HF_TOKEN="${HF_TOKEN}" \
  -e WHISPER_MODEL="large-v3" \
  --memory="16g" \
  --cpus="8" \
  --restart unless-stopped \
  -v whisperx-models:/root/.cache \
  whisperx-api:v1.0.0
```

### Option 2: Docker Swarm

Create `stack.yml`:

```yaml
version: '3.8'

services:
  whisperx-api:
    image: whisperx-api:v1.0.0
    ports:
      - "8000:8000"
    environment:
      - HF_TOKEN=${HF_TOKEN}
      - WHISPER_MODEL=large-v3
    deploy:
      replicas: 2
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
        limits:
          memory: 16G
      restart_policy:
        condition: on-failure
    volumes:
      - whisperx-models:/root/.cache

volumes:
  whisperx-models:
```

Deploy:
```bash
docker stack deploy -c stack.yml whisperx
```

### Option 3: Kubernetes

#### Deployment Manifest (`deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whisperx-api
  namespace: ai-services
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whisperx-api
  template:
    metadata:
      labels:
        app: whisperx-api
    spec:
      containers:
      - name: whisperx-api
        image: whisperx-api:v1.0.0
        ports:
        - containerPort: 8000
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: whisperx-secrets
              key: hf-token
        - name: WHISPER_MODEL
          value: "large-v3"
        resources:
          requests:
            memory: "8Gi"
            cpu: "4"
            nvidia.com/gpu: "1"
          limits:
            memory: "16Gi"
            cpu: "8"
            nvidia.com/gpu: "1"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        volumeMounts:
        - name: model-cache
          mountPath: /root/.cache
      volumes:
      - name: model-cache
        persistentVolumeClaim:
          claimName: whisperx-models-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: whisperx-api
  namespace: ai-services
spec:
  selector:
    app: whisperx-api
  ports:
  - port: 80
    targetPort: 8000
  type: LoadBalancer
---
apiVersion: v1
kind: Secret
metadata:
  name: whisperx-secrets
  namespace: ai-services
type: Opaque
stringData:
  hf-token: "your_token_here"
```

Deploy:
```bash
kubectl apply -f deployment.yaml
```

### Option 4: AWS ECS (Fargate with GPU)

Task Definition example available upon request.

### Option 5: Azure Container Instances

Deploy via Azure CLI:
```bash
az container create \
  --resource-group myResourceGroup \
  --name whisperx-api \
  --image whisperx-api:v1.0.0 \
  --gpu-count 1 \
  --gpu-sku V100 \
  --cpu 4 \
  --memory 16 \
  --ports 8000 \
  --environment-variables HF_TOKEN="${HF_TOKEN}" WHISPER_MODEL="large-v3"
```

---

## 📊 Monitoring & Observability

### Health Checks

```bash
# Basic health
curl http://localhost:8000/health

# Expected response:
{
  "status": "healthy",
  "cuda_available": true,
  "device": "cuda",
  "model_loaded": true,
  "diarization_available": true
}
```

### Metrics to Monitor

1. **Response Time**: Target < 30s for 1-minute audio
2. **GPU Utilization**: Should be 80-100% during processing
3. **Memory Usage**: Monitor for leaks
4. **Error Rate**: Should be < 1%
5. **Queue Length**: If implementing queue

### Logging

View container logs:
```bash
# Docker
docker logs -f whisperx-api

# Kubernetes
kubectl logs -f deployment/whisperx-api -n ai-services

# Docker Compose
docker-compose logs -f
```

### Prometheus Metrics (Future Enhancement)

Consider adding `/metrics` endpoint with:
- Request duration histogram
- Request count by status code
- GPU memory usage
- Model inference time

---

## 🔒 Security Considerations

### 1. API Authentication

Add authentication layer (not included by default):
- API keys
- OAuth 2.0
- mTLS

### 2. Rate Limiting

Implement reverse proxy with rate limiting:
```nginx
# nginx.conf
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/m;

server {
    location /transcribe/ {
        limit_req zone=api burst=5;
        proxy_pass http://whisperx-api:8000;
    }
}
```

### 3. Network Isolation

- Deploy in private subnet
- Use security groups/firewall rules
- Only expose necessary ports

### 4. Secret Management

- Use secret managers (AWS Secrets Manager, HashiCorp Vault)
- Never commit tokens to git
- Rotate tokens regularly

---

## 🚨 Troubleshooting

### Issue: Out of Memory

**Solution:**
- Reduce model size (use `small` or `base`)
- Reduce batch size in code
- Add more RAM/VRAM

### Issue: GPU Not Detected

**Solution:**
```bash
# Check NVIDIA driver
nvidia-smi

# Verify Docker can access GPU
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

# Install nvidia-docker if missing
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

### Issue: Diarization Fails

**Solution:**
- Verify `HF_TOKEN` is set correctly
- Check you accepted pyannote license
- Test token: `huggingface-cli login --token $HF_TOKEN`

### Issue: Slow Performance

**Solution:**
- Ensure GPU is being used (check logs for "device: cuda")
- Use smaller model for faster inference
- Scale horizontally with multiple instances

---

## 📈 Scaling Strategies

### Horizontal Scaling

Deploy multiple instances behind a load balancer:

```bash
# Docker Swarm
docker service scale whisperx=5

# Kubernetes
kubectl scale deployment whisperx-api --replicas=5 -n ai-services
```

### Vertical Scaling

- Upgrade to larger GPU (V100 → A100)
- Add more CPU cores
- Increase memory allocation

### Queue-Based Architecture

For high-throughput scenarios, consider:
1. API receives request → pushes to queue (Redis/SQS)
2. Worker pods process from queue
3. Store results in S3/database
4. Notify via webhook/callback

---

## 🧪 Testing

### Load Testing

```bash
# Using Apache Bench
ab -n 100 -c 10 -p audio.mp3 -T "multipart/form-data" \
  http://localhost:8000/transcribe/

# Using hey
hey -n 50 -c 5 -m POST -D audio.mp3 \
  http://localhost:8000/transcribe/
```

### Integration Testing

```bash
# Use provided test script
python test_api.py sample_audio.mp3
python test_api.py sample_audio.mp3 --diarize
```

---

## 📦 CI/CD Pipeline Example

### GitLab CI (`.gitlab-ci.yml`)

```yaml
stages:
  - build
  - test
  - deploy

build:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

test:
  stage: test
  script:
    - docker run --rm $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA pytest

deploy:
  stage: deploy
  script:
    - kubectl set image deployment/whisperx-api \
        whisperx-api=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  only:
    - main
```

---

## 💰 Cost Optimization

1. **Use spot instances** for non-critical workloads (50-70% savings)
2. **Auto-scaling**: Scale down during low-traffic periods
3. **Model caching**: Use persistent volumes to avoid re-downloading
4. **Smaller models**: Use `base` or `small` if accuracy allows
5. **Batch processing**: Process multiple files together

---

## 📞 Support & Maintenance

### Regular Maintenance Tasks

- **Weekly**: Review logs for errors
- **Monthly**: Update dependencies (security patches)
- **Quarterly**: Review and optimize resource allocation

### Useful Commands

```bash
# Check resource usage
docker stats whisperx-api

# Update image
docker pull whisperx-api:latest
docker-compose up -d

# Backup model cache
docker run --rm -v whisperx-models:/data -v $(pwd):/backup \
  alpine tar czf /backup/models-backup.tar.gz /data

# Restore model cache
docker run --rm -v whisperx-models:/data -v $(pwd):/backup \
  alpine tar xzf /backup/models-backup.tar.gz -C /
```

---

## 🎯 Success Checklist

Before going live:

- [ ] GPU drivers installed and verified
- [ ] Docker and NVIDIA Docker working
- [ ] HF_TOKEN configured correctly
- [ ] Health endpoint returns 200
- [ ] Test transcription works
- [ ] Monitoring/logging configured
- [ ] Backups configured (if needed)
- [ ] Security measures in place
- [ ] Load testing completed
- [ ] Documentation reviewed by team

---

**Ready for production!** 🚀

For questions or issues, check the main README.md or container logs.

