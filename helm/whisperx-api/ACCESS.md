# WhisperX API Access Guide

Quick reference for accessing your deployed WhisperX API.

---

## 🔍 Find Your API Endpoint

### Option 1: Via Ingress (Production)

If you enabled ingress in your values:

```bash
# Get ingress details
kubectl get ingress -n ai-services

# Output example:
# NAME           CLASS   HOSTS                    ADDRESS          PORTS
# whisperx-api   nginx   whisperx.yourdomain.com  10.20.30.40      80, 443
```

**Your API endpoint:**
```
https://whisperx.yourdomain.com
```

**Test it:**
```bash
curl https://whisperx.yourdomain.com/health
```

---

### Option 2: Via Service (Internal)

If using ClusterIP service (default):

```bash
# Get service details
kubectl get svc -n ai-services

# Output example:
# NAME           TYPE        CLUSTER-IP      PORT(S)
# whisperx-api   ClusterIP   10.96.100.50    8000/TCP
```

**From inside cluster:**
```
http://whisperx-api.ai-services.svc.cluster.local:8000
```

---

### Option 3: Via Port Forward (Testing)

For local testing/development:

```bash
# Forward port 8000 to your local machine
kubectl port-forward -n ai-services svc/whisperx-api 8000:8000

# Now access at:
# http://localhost:8000
```

**Test it:**
```bash
curl http://localhost:8000/health
```

---

## 🔑 API Keys & Secrets

### Hugging Face Token (HF_TOKEN)

The HF token is stored as a Kubernetes secret.

**View secret name:**
```bash
kubectl get secrets -n ai-services

# Output:
# NAME           TYPE     DATA   AGE
# whisperx-api   Opaque   1      10m
```

**Get the token (if needed):**
```bash
kubectl get secret whisperx-api -n ai-services -o jsonpath='{.data.hf-token}' | base64 -d
```

**Update the token:**
```bash
# Option 1: Using kubectl
kubectl create secret generic whisperx-api \
  --from-literal=hf-token=hf_new_token_here \
  --dry-run=client -o yaml | kubectl apply -n ai-services -f -

# Option 2: Using Helm upgrade
helm upgrade whisperx-api ./whisperx-api \
  -f values-production.yaml \
  --set whisperx.hfToken=hf_new_token_here \
  -n ai-services
```

---

## 📡 API Endpoints

Once deployed, these endpoints are available:

### Health Check
```bash
GET /health

# Returns:
{
  "status": "healthy",
  "cuda_available": true,
  "device": "cuda",
  "model_loaded": true,
  "diarization_available": true
}
```

### Root/Info
```bash
GET /

# Returns API information
```

### Transcribe (Basic)
```bash
POST /transcribe/

# Parameters:
# - file: audio file (required)
# - align: enable alignment (default: true)
# - diarize: enable speaker diarization (default: false)
# - language: force language (optional)
```

### Transcribe (Batch)
```bash
POST /transcribe/batch/

# Parameters:
# - files: multiple audio files
# - align: enable alignment
# - diarize: enable speaker diarization
```

### Interactive Documentation
```bash
# Swagger UI
GET /docs

# ReDoc
GET /redoc
```

---

## 🧪 Testing Your Deployment

### 1. Check Pod Status
```bash
kubectl get pods -n ai-services

# Should show:
# NAME                            READY   STATUS    RESTARTS   AGE
# whisperx-api-5d8f7b6c9d-xyz     1/1     Running   0          5m
```

### 2. Check Logs
```bash
kubectl logs -n ai-services -l app.kubernetes.io/name=whisperx-api -f

# Look for:
# Loading WhisperX model 'large-v3' on device: cuda
# Model loaded successfully!
```

### 3. Test Health Endpoint
```bash
# Via port-forward
kubectl port-forward -n ai-services svc/whisperx-api 8000:8000 &
curl http://localhost:8000/health
```

### 4. Test Transcription
```bash
# Prepare test audio file
curl -X POST "http://localhost:8000/transcribe/?align=true" \
  -F "file=@test-audio.mp3" \
  -H "Content-Type: multipart/form-data"
```

---

## 🌐 Complete Access Examples

### Example 1: Internal Kubernetes Service

From another pod in the same cluster:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-client
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: 
      - curl
      - http://whisperx-api.ai-services.svc.cluster.local:8000/health
```

### Example 2: External via Ingress

From anywhere on the internet (if ingress is public):

```bash
curl -X POST "https://whisperx.yourdomain.com/transcribe/" \
  -F "file=@audio.mp3"
```

### Example 3: Port Forward from Local Machine

```bash
# Terminal 1: Setup port forward
kubectl port-forward -n ai-services svc/whisperx-api 8000:8000

# Terminal 2: Use the API
curl http://localhost:8000/docs
# Open browser: http://localhost:8000/docs
```

---

## 📊 Get Full Deployment Info

Run this command to get all details at once:

```bash
cat << 'EOF' > check-whisperx.sh
#!/bin/bash
NS="ai-services"
APP="whisperx-api"

echo "=== WhisperX API Deployment Info ==="
echo ""

echo "📦 Pods:"
kubectl get pods -n $NS -l app.kubernetes.io/name=$APP
echo ""

echo "🌐 Service:"
kubectl get svc -n $NS $APP
echo ""

echo "🚪 Ingress:"
kubectl get ingress -n $NS $APP 2>/dev/null || echo "No ingress configured"
echo ""

echo "🔑 Secrets:"
kubectl get secret -n $NS $APP
echo ""

echo "📊 Pod Status:"
kubectl describe pod -n $NS -l app.kubernetes.io/name=$APP | grep -A 5 "Status:"
echo ""

echo "🔗 Endpoints:"
CLUSTER_IP=$(kubectl get svc -n $NS $APP -o jsonpath='{.spec.clusterIP}')
INGRESS_HOST=$(kubectl get ingress -n $NS $APP -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)

echo "  Internal: http://$APP.$NS.svc.cluster.local:8000"
echo "  ClusterIP: http://$CLUSTER_IP:8000"
if [ ! -z "$INGRESS_HOST" ]; then
  echo "  External: https://$INGRESS_HOST"
fi
echo ""

echo "🧪 Quick Test:"
echo "  kubectl port-forward -n $NS svc/$APP 8000:8000"
echo "  curl http://localhost:8000/health"
EOF

chmod +x check-whisperx.sh
./check-whisperx.sh
```

---

## 🔒 Security Notes

### Production Checklist

- ✅ HF_TOKEN stored as Kubernetes secret (not in values files)
- ✅ Ingress uses TLS/HTTPS (via cert-manager)
- ✅ Service is ClusterIP (not exposed directly)
- ⚠️ **Add authentication** if exposing publicly (not included by default)
- ⚠️ **Add rate limiting** via ingress annotations
- ⚠️ **Network policies** to restrict pod-to-pod traffic

### Recommended: Add Basic Auth to Ingress

```yaml
# For nginx ingress
ingress:
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: whisperx-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"

# Create auth secret:
# htpasswd -c auth username
# kubectl create secret generic whisperx-basic-auth --from-file=auth -n ai-services
```

---

## 📝 Environment Variables

The deployed containers use these environment variables:

| Variable | Source | Purpose |
|----------|--------|---------|
| `HF_TOKEN` | Secret | Hugging Face token for diarization |
| `WHISPER_MODEL` | ConfigMap | Model name (e.g., large-v3) |
| `BATCH_SIZE` | ConfigMap | Batch size for processing |
| `COMPUTE_TYPE` | ConfigMap | Compute type (float16/int8) |
| `CUDA_VISIBLE_DEVICES` | Deployment | GPU device selection |

**View current config:**
```bash
kubectl get configmap whisperx-api -n ai-services -o yaml
```

---

## 🆘 Troubleshooting

### Can't access the API

```bash
# Check if pods are running
kubectl get pods -n ai-services

# Check pod logs
kubectl logs -n ai-services -l app.kubernetes.io/name=whisperx-api

# Check service endpoints
kubectl get endpoints -n ai-services whisperx-api
```

### Ingress not working

```bash
# Check ingress status
kubectl describe ingress -n ai-services whisperx-api

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### GPU not detected

```bash
# Check GPU allocation
kubectl describe pod -n ai-services -l app.kubernetes.io/name=whisperx-api | grep -A 5 "nvidia.com/gpu"

# Check from inside pod
kubectl exec -it -n ai-services <pod-name> -- nvidia-smi
```

---

## 📱 Quick Reference Card

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃         WhisperX API Quick Access        ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Health Check:                            ┃
┃   GET /health                            ┃
┃                                          ┃
┃ Transcribe:                              ┃
┃   POST /transcribe/                      ┃
┃   Body: file=audio.mp3                   ┃
┃                                          ┃
┃ Docs:                                    ┃
┃   GET /docs (Swagger)                    ┃
┃                                          ┃
┃ Port Forward:                            ┃
┃   kubectl port-forward -n ai-services \  ┃
┃     svc/whisperx-api 8000:8000           ┃
┃                                          ┃
┃ Check Status:                            ┃
┃   kubectl get pods,svc,ingress \         ┃
┃     -n ai-services                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

**Need more help?** Check the main [README.md](README.md) or [DEPLOYMENT.md](../../DEPLOYMENT.md)

