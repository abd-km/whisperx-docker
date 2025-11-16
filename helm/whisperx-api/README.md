# WhisperX API Helm Chart

Production-ready Helm chart for deploying WhisperX API with H200 GPU optimization.

## Features

- 🎯 **GPU Support**: Optimized for NVIDIA H200 (141GB HBM3)
- 🚀 **Auto-scaling**: Support for HPA and pod disruption budgets
- 💾 **Persistent Cache**: Model caching for faster startup
- 🔒 **Security**: Secret management for HF tokens
- 📊 **High Availability**: Anti-affinity and replica management
- ⚙️ **Configurable**: Extensive values for customization

---

## Prerequisites

- Kubernetes 1.20+
- Helm 3.0+
- NVIDIA GPU Operator installed
- Storage class for persistent volumes
- Hugging Face token ([Get one here](https://huggingface.co/settings/tokens))

---

## Quick Start

### 1. Build and Push Docker Image

```bash
# From the root of the repository
docker build -t your-registry/whisperx-api:latest .
docker push your-registry/whisperx-api:latest
```

### 2. Install with Default Values

```bash
helm install whisperx-api ./helm/whisperx-api \
  --set image.repository=your-registry/whisperx-api \
  --set whisperx.hfToken=hf_your_token_here \
  --namespace ai-services \
  --create-namespace
```

### 3. Install with H200 Optimization

```bash
helm install whisperx-api ./helm/whisperx-api \
  -f ./helm/whisperx-api/values.yaml \
  -f ./helm/whisperx-api/values-h200.yaml \
  --set image.repository=your-registry/whisperx-api \
  --set whisperx.hfToken=hf_your_token_here \
  --namespace ai-services \
  --create-namespace
```

---

## Configuration

### Essential Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Docker image repository | `whisperx-api` |
| `image.tag` | Docker image tag | `latest` |
| `whisperx.hfToken` | Hugging Face token (required) | `""` |
| `whisperx.model.name` | WhisperX model | `large-v3` |
| `whisperx.model.batchSize` | Batch size for processing | `16` |
| `gpu.enabled` | Enable GPU support | `true` |
| `gpu.count` | GPUs per pod | `1` |
| `persistence.enabled` | Enable model cache | `true` |
| `persistence.size` | Cache volume size | `50Gi` |

### H200-Specific Parameters

| Parameter | H200 Value | Why |
|-----------|------------|-----|
| `whisperx.model.batchSize` | `64` | Leverage 141GB memory |
| `resources.requests.memory` | `64Gi` | Utilize H200 bandwidth |
| `resources.limits.memory` | `128Gi` | Allow memory headroom |
| `persistence.storageClass` | `fast-ssd` | Match PCIe Gen5 speed |
| `persistence.accessMode` | `ReadWriteMany` | Share cache across pods |

---

## Installation Examples

### Development Environment

```bash
helm install whisperx-dev ./helm/whisperx-api \
  --set image.repository=whisperx-api \
  --set whisperx.hfToken=hf_token \
  --set replicaCount=1 \
  --set whisperx.model.name=base \
  --set resources.requests.memory=8Gi
```

### Production with H200

```bash
helm install whisperx-prod ./helm/whisperx-api \
  -f values-h200.yaml \
  --set image.repository=my-registry/whisperx-api:v1.0.0 \
  --set whisperx.hfToken=hf_token \
  --set ingress.hosts[0].host=whisperx.company.com \
  --set persistence.storageClass=nvme-ssd \
  --namespace production
```

### Using Existing Secret

```bash
# Create secret first
kubectl create secret generic whisperx-secret \
  --from-literal=hf-token=hf_your_token_here \
  -n ai-services

# Install with existing secret
helm install whisperx-api ./helm/whisperx-api \
  --set whisperx.existingSecret=whisperx-secret \
  --namespace ai-services
```

---

## Verification

### Check Deployment Status

```bash
# Watch pods
kubectl get pods -n ai-services -w

# Check GPU allocation
kubectl describe pod -n ai-services -l app.kubernetes.io/name=whisperx-api

# View logs
kubectl logs -n ai-services -l app.kubernetes.io/name=whisperx-api -f
```

### Test the API

```bash
# Port forward
kubectl port-forward -n ai-services svc/whisperx-api 8000:8000

# Test health endpoint
curl http://localhost:8000/health

# View Swagger docs
open http://localhost:8000/docs
```

### GPU Utilization

```bash
# Check GPU usage from inside pod
kubectl exec -it -n ai-services <pod-name> -- nvidia-smi

# Expected output: GPU utilization, 141GB memory for H200
```

---

## Upgrading

```bash
# Upgrade with new values
helm upgrade whisperx-api ./helm/whisperx-api \
  -f values-h200.yaml \
  --set image.tag=v1.1.0 \
  --namespace ai-services

# Rollback if needed
helm rollback whisperx-api -n ai-services
```

---

## Uninstallation

```bash
helm uninstall whisperx-api -n ai-services

# Optional: Delete PVC (model cache)
kubectl delete pvc -n ai-services whisperx-api
```

---

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check events
kubectl describe pod -n ai-services <pod-name>

# Common issues:
# - No GPU nodes available
# - PVC not bound
# - Resource limits too high
```

### GPU Not Detected

```bash
# Verify GPU operator is running
kubectl get pods -n gpu-operator

# Check node labels
kubectl get nodes -o json | jq '.items[].metadata.labels | with_entries(select(.key | contains("nvidia")))'
```

### Out of Memory

```bash
# Check actual usage
kubectl top pod -n ai-services

# Solutions:
# - Reduce batch size: --set whisperx.model.batchSize=32
# - Increase memory limits: --set resources.limits.memory=256Gi
# - Use smaller model: --set whisperx.model.name=medium
```

---

## Advanced Configuration

### Multiple GPU Support

```yaml
gpu:
  count: 2  # Use 2 H200 GPUs per pod
resources:
  limits:
    nvidia.com/gpu: 2
```

### Custom Storage Class

```yaml
persistence:
  storageClass: "ceph-nvme"
  accessMode: ReadWriteMany
  size: 200Gi
```

### Node Affinity for Specific Racks

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: rack
          operator: In
          values:
          - rack-1
          - rack-2
```

---

## Performance Tuning

### H200 Optimization Checklist

- ✅ Use `float16` compute type
- ✅ Set batch size to 64-128
- ✅ Use fast NVMe storage (PCIe Gen5)
- ✅ Enable ReadWriteMany for shared cache
- ✅ Set memory requests to 64Gi+
- ✅ Use pod anti-affinity to spread across nodes
- ✅ Enable pod disruption budgets

### Expected Performance

| Model | H200 Throughput | Latency (1min audio) |
|-------|----------------|---------------------|
| base | ~10x realtime | ~6s |
| small | ~5x realtime | ~12s |
| medium | ~3x realtime | ~20s |
| large-v3 | ~1x realtime | ~60s |

---

## Support

- **Documentation**: See main [README.md](../../README.md)
- **Deployment Guide**: See [DEPLOYMENT.md](../../DEPLOYMENT.md)
- **GitHub**: https://github.com/abd-km/whisperx-docker

---

## License

See main repository for license information.

