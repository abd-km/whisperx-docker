#!/bin/bash

# VARS
export VERSION
export PRODUCT_VERSION
export PRODUCT_NAME

init() {
    VERSION="$(git rev-parse --short HEAD)"
    PRODUCT_VERSION="$(cat ./VERSION)"
    PRODUCT_NAME="whisperx"
}


####################################################################################

build() {
    echo "Building Docker image..."
    docker build  --platform linux/amd64 -t whisperx:latest .
    echo "Docker image built successfully!"
}

tag() {
    echo "Tagging Docker image..."
    docker tag whisperx:latest  europe-west1-docker.pkg.dev/ajgc-ai-app-dev-01/ajnai/whisperx:$1
    echo "Docker image tagged successfully!"
}

push() {
    echo "Pushing Docker image..."
    docker push europe-west1-docker.pkg.dev/ajgc-ai-app-dev-01/ajnai/whisperx:$1
    echo "Docker image pushed successfully!"
}

deploy() {
    echo "Deploying Docker image..."
    helm upgrade --install whisperx ./helm --namespace whisperx --create-namespace --wait --timeout 10m --set image.tag=$PRODUCT_VERSION
}

deploy-test() {
    echo "Deploying Docker image..."
    helm upgrade --install whisperx-test ./helm --namespace whisperx --create-namespace --wait --timeout 10m \
    --set image.tag=$VERSION \
    --values helm/values-test.yaml
}

publish() {
    build
    tag $PRODUCT_VERSION
    push $PRODUCT_VERSION
    deploy whisperx $PRODUCT_VERSION
}

#################################### MAIN ###################################
init
$@
