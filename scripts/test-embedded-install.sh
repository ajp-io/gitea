#!/bin/bash
set -euo pipefail

echo "=== Gitea Embedded Cluster Installation Test ==="
echo "Starting at: $(date)"

echo "Downloading Embedded Cluster installation assets for version: ${TEST_VERSION}"
curl -f "https://updates.alexparker.info/embedded/gitea-mastodon/unstable/${TEST_VERSION}" \
  -H "Authorization: 32nCUpJuy9TUwE8CYdvS2KIIFy9" \
  -o gitea-mastodon-unstable.tgz

echo "Extracting installation assets..."
tar -xzf gitea-mastodon-unstable.tgz

echo "Verifying extracted files..."
ls -la

echo "Installing Gitea Enterprise with Embedded Cluster..."
echo "This may take several minutes..."

# This command blocks until installation completes
sudo ./gitea-mastodon install \
  --license license.yaml \
  --config-values /tmp/config-values.yaml \
  --admin-console-password "TestAdminPassword123!" \
  -y

echo "Installation complete! Verifying cluster and pods..."

# Set kubectl path and kubeconfig
KUBECTL="sudo KUBECONFIG=/var/lib/embedded-cluster/k0s/pki/admin.conf /var/lib/embedded-cluster/bin/kubectl"

echo "Checking cluster status..."
$KUBECTL get nodes

echo "Checking all resources..."
$KUBECTL get deployment,statefulset,service -n kotsadm | grep gitea

# Wait for StatefulSets first (dependencies)
echo "Waiting for PostgreSQL StatefulSet to have ready replicas..."
$KUBECTL wait statefulset/gitea-postgresql --for=jsonpath='{.status.readyReplicas}'=1 -n kotsadm --timeout=300s

echo "Waiting for Valkey StatefulSet to have ready replicas..."
$KUBECTL wait statefulset/gitea-valkey-primary --for=jsonpath='{.status.readyReplicas}'=1 -n kotsadm --timeout=300s

# Wait for Deployments (Gitea depends on database/cache)
echo "Waiting for Gitea deployment to be available..."
$KUBECTL wait deployment/gitea --for=condition=available -n kotsadm --timeout=300s

echo "Waiting for Gitea SDK deployment to be available..."
$KUBECTL wait deployment/gitea-sdk --for=condition=available -n kotsadm --timeout=300s

# Wait for Services to have endpoints (confirms they have healthy backends)
echo "Waiting for PostgreSQL service to have endpoints..."
$KUBECTL wait --for=jsonpath='{.subsets}' endpoints/gitea-postgresql -n kotsadm --timeout=300s

echo "Waiting for Valkey service to have endpoints..."
$KUBECTL wait --for=jsonpath='{.subsets}' endpoints/gitea-valkey-primary -n kotsadm --timeout=300s

echo "Waiting for Gitea HTTP service to have endpoints..."
$KUBECTL wait --for=jsonpath='{.subsets}' endpoints/gitea-http -n kotsadm --timeout=300s

echo "Waiting for Gitea SSH service to have endpoints..."
$KUBECTL wait --for=jsonpath='{.subsets}' endpoints/gitea-ssh -n kotsadm --timeout=300s

echo "Waiting for Gitea SDK service to have endpoints..."
$KUBECTL wait --for=jsonpath='{.subsets}' endpoints/gitea-sdk -n kotsadm --timeout=300s

echo "All resources verified and ready!"
echo "Cluster verification complete!"

echo "=== Gitea Embedded Cluster Installation Test PASSED ==="
echo "Completed at: $(date)"