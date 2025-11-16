# Traefik Ingress Configuration for WhisperX API

This guide covers deploying WhisperX API with Traefik ingress controller on H200 GPU clusters.

## Prerequisites

- Traefik ingress controller installed in your cluster
- cert-manager (optional, for automatic TLS)
- DNS configured to point to your Traefik load balancer

---

## Quick Start with Traefik

### Option 1: Using Standard Kubernetes Ingress

```bash
helm install whisperx-api ./helm/whisperx-api \
  -f values.yaml \
  -f values-traefik.yaml \
  --set image.repository=your-registry/whisperx-api \
  --set whisperx.hfToken=hf_your_token \
  --set ingress.hosts[0].host=whisperx.yourdomain.com \
  --namespace ai-services \
  --create-namespace
```

### Option 2: Using Traefik IngressRoute CRD (Advanced)

```bash
helm install whisperx-api ./helm/whisperx-api \
  -f values.yaml \
  -f values-traefik.yaml \
  --set image.repository=your-registry/whisperx-api \
  --set whisperx.hfToken=hf_your_token \
  --set ingress.useIngressRoute=true \
  --set ingress.hosts[0].host=whisperx.yourdomain.com \
  --namespace ai-services
```

---

## Traefik-Specific Features

### 1. **Middleware for Large Audio Files**

The chart includes a Traefik middleware for handling large uploads:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: whisperx-timeout
spec:
  buffering:
    maxRequestBodyBytes: 104857600  # 100MB
```

### 2. **Rate Limiting**

Protect your API from abuse:

```yaml
# Enable in values-traefik.yaml
ingress:
  rateLimit: true
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "ai-services-whisperx-ratelimit@kubernetescrd"
```

### 3. **Custom Headers & CORS**

Security headers are automatically added:
- X-Frame-Options
- X-Content-Type-Options
- CORS headers for API access

---

## Configuration Options

### Basic Traefik Ingress

```yaml
# values-traefik.yaml
ingress:
  enabled: true
  className: "traefik"
  annotations:
    traefik.ingress.kubernetes.io/router.tls: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: whisperx.company.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: whisperx-tls
      hosts:
        - whisperx.company.com
```

### Advanced: IngressRoute with Middlewares

```yaml
# values-traefik.yaml
ingress:
  enabled: true
  className: "traefik"
  useIngressRoute: true  # Use Traefik CRD instead of standard Ingress
  rateLimit: true
  hosts:
    - host: whisperx.company.com
  tls:
    - secretName: whisperx-tls
      hosts:
        - whisperx.company.com
```

---

## Traefik Annotations Reference

| Annotation | Purpose | Example |
|------------|---------|---------|
| `traefik.ingress.kubernetes.io/router.tls` | Enable TLS | `"true"` |
| `traefik.ingress.kubernetes.io/router.entrypoints` | Specify entrypoint | `"websecure"` |
| `traefik.ingress.kubernetes.io/router.middlewares` | Apply middlewares | `"namespace-middleware@kubernetescrd"` |
| `traefik.ingress.kubernetes.io/router.priority` | Route priority | `"10"` |

---

## TLS/SSL Configuration

### Option 1: cert-manager (Recommended)

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: whisperx-tls
      hosts:
        - whisperx.yourdomain.com
```

### Option 2: Manual Certificate

```bash
# Create TLS secret manually
kubectl create secret tls whisperx-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n ai-services
```

### Option 3: Traefik Default Certificate

```yaml
ingress:
  enabled: true
  className: "traefik"
  # No TLS section = uses Traefik's default cert
  hosts:
    - host: whisperx.company.com
```

---

## Advanced Configurations

### 1. Path-Based Routing

Route `/whisperx/*` to the API:

```yaml
ingress:
  hosts:
    - host: api.company.com
      paths:
        - path: /whisperx
          pathType: Prefix
```

### 2. Multiple Domains

```yaml
ingress:
  hosts:
    - host: whisperx.company.com
      paths:
        - path: /
          pathType: Prefix
    - host: api.company.com
      paths:
        - path: /whisperx
          pathType: Prefix
  tls:
    - secretName: whisperx-tls
      hosts:
        - whisperx.company.com
    - secretName: api-tls
      hosts:
        - api.company.com
```

### 3. IP Whitelisting

```yaml
# Create middleware
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: ip-whitelist
spec:
  ipWhiteList:
    sourceRange:
      - 10.0.0.0/8
      - 172.16.0.0/12

# Reference in values
ingress:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "ai-services-ip-whitelist@kubernetescrd"
```

### 4. Sticky Sessions (for multi-replica)

```yaml
ingress:
  annotations:
    traefik.ingress.kubernetes.io/service.sticky.cookie: "true"
    traefik.ingress.kubernetes.io/service.sticky.cookie.name: "whisperx_session"
```

---

## Monitoring with Traefik Dashboard

### Enable Traefik Dashboard

```yaml
# In Traefik deployment
--api.dashboard=true
--api.insecure=false  # Use secure dashboard
```

### View WhisperX Metrics

1. Access Traefik dashboard
2. Navigate to HTTP → Routers
3. Find `whisperx-api` router
4. Monitor:
   - Request rate
   - Response times
   - Error rates
   - Active connections

---

## Load Balancing Strategies

### Round Robin (Default)

```yaml
# No special configuration needed
replicaCount: 3
```

### Weighted Load Balancing

```yaml
# Create TraefikService for weighted distribution
apiVersion: traefik.containo.us/v1alpha1
kind: TraefikService
metadata:
  name: whisperx-weighted
spec:
  weighted:
    services:
      - name: whisperx-api-v1
        weight: 70
        port: 8000
      - name: whisperx-api-v2
        weight: 30
        port: 8000
```

### Mirroring (Traffic Shadowing)

```yaml
# Mirror traffic to new version for testing
apiVersion: traefik.containo.us/v1alpha1
kind: TraefikService
metadata:
  name: whisperx-mirror
spec:
  mirroring:
    name: whisperx-api-stable
    port: 8000
    mirrors:
      - name: whisperx-api-canary
        port: 8000
        percent: 10
```

---

## Performance Tuning

### 1. Connection Settings

```yaml
# Traefik static configuration
--serversTransport.maxIdleConnsPerHost=200
--serversTransport.forwardingTimeouts.dialTimeout=30s
--serversTransport.forwardingTimeouts.responseHeaderTimeout=300s
--serversTransport.forwardingTimeouts.idleConnTimeout=90s
```

### 2. Buffer Sizes

```yaml
# In middleware
spec:
  buffering:
    maxRequestBodyBytes: 209715200   # 200MB
    memRequestBodyBytes: 52428800    # 50MB in memory
```

### 3. Timeouts

```yaml
ingress:
  annotations:
    traefik.ingress.kubernetes.io/router.timeout: "300s"
```

---

## Troubleshooting

### Issue: 413 Request Entity Too Large

**Solution:**
```yaml
# Increase buffer in middleware
spec:
  buffering:
    maxRequestBodyBytes: 209715200  # 200MB
```

### Issue: 504 Gateway Timeout

**Solution:**
```yaml
# Increase timeouts
ingress:
  annotations:
    traefik.ingress.kubernetes.io/router.timeout: "600s"
```

### Issue: TLS Certificate Not Working

**Check:**
```bash
# Verify cert-manager
kubectl get certificate -n ai-services
kubectl describe certificate whisperx-tls -n ai-services

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

---

## Complete Example

### Production Setup with All Features

```bash
# Create namespace
kubectl create namespace ai-services

# Install WhisperX with Traefik
helm install whisperx-api ./helm/whisperx-api \
  -f values.yaml \
  -f values-traefik.yaml \
  --set image.repository=myregistry/whisperx-api:v1.0.0 \
  --set whisperx.hfToken=$HF_TOKEN \
  --set ingress.hosts[0].host=whisperx.company.com \
  --set ingress.rateLimit=true \
  --set persistence.storageClass=fast-ssd \
  --set gpu.nodeSelector.enabled=true \
  --namespace ai-services

# Verify deployment
kubectl get pods,svc,ingress -n ai-services

# Check Traefik routing
kubectl get ingressroute -n ai-services

# Test API
curl -k https://whisperx.company.com/health
```

---

## Comparison: Nginx vs Traefik

| Feature | Nginx | Traefik |
|---------|-------|---------|
| Configuration | Annotations | Annotations + CRDs |
| Dynamic Config | ConfigMap reload | Native |
| Middleware | Limited | Extensive |
| Dashboard | Separate | Built-in |
| Metrics | Prometheus exporter | Native Prometheus |
| Learning Curve | Lower | Higher |
| Best For | Simple use cases | Complex routing |

---

## Next Steps

1. **Monitor Performance**: Use Traefik dashboard and Prometheus
2. **Scale**: Adjust replicas based on load
3. **Optimize**: Tune buffer sizes and timeouts
4. **Secure**: Add IP whitelisting and rate limiting
5. **Backup**: Save TLS certificates and configs

---

For more information:
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Kubernetes CRDs](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- Main [README.md](README.md)

