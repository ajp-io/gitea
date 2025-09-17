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
  --config-values /tmp/config.yaml \
  --admin-console-password "TestAdminPassword123!" \
  -y

echo "Installation complete! Verifying cluster and pods..."

# Run kubectl commands via the shell (non-interactive)
echo "Checking cluster status..."
sudo ./gitea-mastodon shell -c "kubectl get nodes"

echo "Checking all pods across namespaces..."
sudo ./gitea-mastodon shell -c "kubectl get pods -A"

echo "Waiting for Gitea pods to be ready..."
sudo ./gitea-mastodon shell -c "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gitea -n default --timeout=300s"

echo "Checking Gitea service..."
sudo ./gitea-mastodon shell -c "kubectl get svc -l app.kubernetes.io/name=gitea"

echo "Cluster verification complete!"

echo "=== Gitea Embedded Cluster Installation Test PASSED ==="
echo "Completed at: $(date)"