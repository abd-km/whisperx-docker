#!/bin/bash
# Quick installation script for WhisperX API on H200 GPU cluster

set -e

echo "╔════════════════════════════════════════════════════╗"
echo "║  WhisperX API - H200 Helm Installation            ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Configuration
NAMESPACE="${NAMESPACE:-ai-services}"
RELEASE_NAME="${RELEASE_NAME:-whisperx-api}"
IMAGE_REPO="${IMAGE_REPO:-whisperx-api}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HF_TOKEN="${HF_TOKEN:-}"

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v helm &> /dev/null; then
    echo "❌ Error: Helm is not installed"
    echo "   Install from: https://helm.sh/docs/intro/install/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed"
    echo "   Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    echo "   Configure kubectl first"
    exit 1
fi

echo "✅ Helm: $(helm version --short)"
echo "✅ kubectl: $(kubectl version --client --short)"
echo "✅ Cluster: $(kubectl config current-context)"
echo ""

# Check for HF_TOKEN
if [ -z "$HF_TOKEN" ]; then
    echo "⚠️  HF_TOKEN not set"
    read -p "Enter your Hugging Face token (or press Enter to skip): " HF_TOKEN
    if [ -z "$HF_TOKEN" ]; then
        echo "❌ Error: HF_TOKEN is required for diarization"
        echo "   Get your token from: https://huggingface.co/settings/tokens"
        echo "   Then run: export HF_TOKEN=your_token_here"
        exit 1
    fi
fi

# Check for GPU nodes
echo "🔍 Checking for GPU nodes..."
GPU_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name' | wc -l)

if [ "$GPU_NODES" -eq 0 ]; then
    echo "⚠️  Warning: No GPU nodes found in cluster"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✅ Found $GPU_NODES GPU node(s)"
fi

# Check for H200 GPUs specifically
H200_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu.product" == "NVIDIA-H200-Tensor-Core-GPU") | .metadata.name' | wc -l)

if [ "$H200_NODES" -gt 0 ]; then
    echo "✅ Found $H200_NODES H200 GPU node(s)!"
    USE_H200_VALUES=true
else
    echo "⚠️  No H200 GPUs detected. Using default GPU configuration."
    USE_H200_VALUES=false
fi

echo ""
echo "📋 Installation Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Release: $RELEASE_NAME"
echo "   Image: $IMAGE_REPO:$IMAGE_TAG"
echo "   H200 Optimized: $USE_H200_VALUES"
echo ""

read -p "Proceed with installation? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "📦 Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
fi

# Build helm install command
HELM_CMD="helm install $RELEASE_NAME ./whisperx-api"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
HELM_CMD="$HELM_CMD --set image.repository=$IMAGE_REPO"
HELM_CMD="$HELM_CMD --set image.tag=$IMAGE_TAG"
HELM_CMD="$HELM_CMD --set whisperx.hfToken=$HF_TOKEN"

# Add production values for H200
if [ "$USE_H200_VALUES" = true ]; then
    HELM_CMD="$HELM_CMD -f ./whisperx-api/values-production.yaml"
else
    HELM_CMD="$HELM_CMD -f ./whisperx-api/values.yaml"
fi

# Install
echo ""
echo "🚀 Installing WhisperX API..."
cd "$(dirname "$0")"
eval $HELM_CMD

# Wait for deployment
echo ""
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=whisperx-api \
    -n $NAMESPACE \
    --timeout=300s || true

# Show status
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅ Installation Complete!                         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "📊 Deployment Status:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=whisperx-api
echo ""
echo "📡 Service:"
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=whisperx-api
echo ""
echo "🔍 Check logs:"
echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=whisperx-api -f"
echo ""
echo "🧪 Test API:"
echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 8000:8000"
echo "   curl http://localhost:8000/health"
echo ""
echo "📚 View Swagger docs:"
echo "   open http://localhost:8000/docs"
echo ""

