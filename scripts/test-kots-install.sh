#!/bin/bash
set -euo pipefail

echo "=== Gitea KOTS Installation Test ==="
echo "Starting at: $(date)"

# Configuration
CUSTOMER_ID="32nCUsAp1lNpmF8o33nxDTpGGPz"
NAMESPACE="gitea-mastodon"
APP_NAME="gitea-mastodon"
SHARED_PASSWORD="TestAdminPassword123!"

# Validate required environment variables
if [[ -z "${TEST_VERSION:-}" ]]; then
    echo "❌ TEST_VERSION environment variable is required"
    exit 1
fi

if [[ -z "${REPLICATED_API_TOKEN:-}" ]]; then
    echo "❌ REPLICATED_API_TOKEN environment variable is required"
    exit 1
fi

echo "Installing KOTS for version: ${TEST_VERSION}"

# Install KOTS CLI
echo "Installing KOTS CLI..."
curl https://kots.io/install | bash

# Verify KOTS installation
echo "Verifying KOTS installation..."
kubectl kots version

# Download license using Replicated CLI (more reliable than curl API)
echo "Downloading license for customer ID: ${CUSTOMER_ID}..."
replicated customer download-license --customer "${CUSTOMER_ID}" > /tmp/license.yaml

echo "License downloaded successfully"

# Verify config values file exists
if [[ ! -f "/tmp/config-values.yaml" ]]; then
    echo "❌ Config values file not found at /tmp/config-values.yaml"
    exit 1
fi

echo "Config values file verified"

# Note: KOTS will create the namespace automatically, so we don't need to create it manually

# Install application using KOTS
echo "Installing ${APP_NAME} with KOTS..."
echo "This may take several minutes..."

kubectl kots install ${APP_NAME} \
  --shared-password "${SHARED_PASSWORD}" \
  --license-file /tmp/license.yaml \
  --config-values /tmp/config-values.yaml \
  --namespace ${NAMESPACE} \
  --no-port-forward \
  --wait-duration 10m

echo "KOTS installation complete! Verifying deployments..."

# Wait for PostgreSQL StatefulSet first (dependencies)
echo "Waiting for PostgreSQL StatefulSet to have ready replicas..."
kubectl wait statefulset/gitea-postgresql --for=jsonpath='{.status.readyReplicas}'=1 -n ${NAMESPACE} --timeout=300s

echo "Waiting for Valkey StatefulSet to have ready replicas..."
kubectl wait statefulset/gitea-valkey-primary --for=jsonpath='{.status.readyReplicas}'=1 -n ${NAMESPACE} --timeout=300s

# Wait for Deployments (Gitea depends on database/cache)
echo "Waiting for Gitea deployment to be available..."
kubectl wait deployment/gitea --for=condition=available -n ${NAMESPACE} --timeout=300s

echo "Waiting for Gitea SDK deployment to be available..."
kubectl wait deployment/gitea-sdk --for=condition=available -n ${NAMESPACE} --timeout=300s

# Wait for Services to have endpoints (confirms they have healthy backends)
echo "Waiting for PostgreSQL service to have endpoints..."
kubectl wait --for=jsonpath='{.subsets}' endpoints/gitea-postgresql -n ${NAMESPACE} --timeout=300s

echo "Waiting for Valkey service to have endpoints..."
kubectl wait --for=jsonpath='{.subsets}' endpoints/gitea-valkey-primary -n ${NAMESPACE} --timeout=300s

echo "Waiting for Gitea HTTP service to have endpoints..."
kubectl wait --for=jsonpath='{.subsets}' endpoints/gitea-http -n ${NAMESPACE} --timeout=300s

echo "Waiting for Gitea SSH service to have endpoints..."
kubectl wait --for=jsonpath='{.subsets}' endpoints/gitea-ssh -n ${NAMESPACE} --timeout=300s

echo "Waiting for Gitea SDK service to have endpoints..."
kubectl wait --for=jsonpath='{.subsets}' endpoints/gitea-sdk -n ${NAMESPACE} --timeout=300s

echo "All resources verified and ready!"

# Show final status
echo "Checking final deployment status..."
kubectl get deployment,statefulset,service -n ${NAMESPACE} | grep gitea

echo "Cluster verification complete!"

echo "=== Gitea KOTS Installation Test PASSED ==="
echo "Completed at: $(date)"