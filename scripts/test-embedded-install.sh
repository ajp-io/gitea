#!/bin/bash
set -euo pipefail

echo "=== Gitea Embedded Cluster Installation Test ==="
echo "Starting at: $(date)"

echo "Downloading Embedded Cluster installation assets..."
curl -f "https://updates.alexparker.info/embedded/gitea-mastodon/unstable" \
  -H "Authorization: 3ZnCUpJuy9TUwE8CYdvS2KIIFy9" \
  -o gitea-mastodon-unstable.tgz

echo "Extracting installation assets..."
tar -xzf gitea-mastodon-unstable.tgz

echo "Verifying extracted files..."
ls -la

echo "Installing Gitea Enterprise with Embedded Cluster..."
echo "This may take several minutes..."

# This command blocks until installation completes
sudo ./gitea-mastodon install \
  --config-values /tmp/config.yaml \
  --admin-console-password "TestAdminPassword123!"

echo "Installation complete! Verifying cluster and pods..."

# Use shell with heredoc to run kubectl commands
sudo gitea-mastodon shell << 'EOF'
echo "Checking cluster status..."
kubectl get nodes

echo "Checking all pods across namespaces..."
kubectl get pods -A

echo "Waiting for Gitea pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gitea -n default --timeout=300s

echo "Checking Gitea service..."
kubectl get svc -l app.kubernetes.io/name=gitea

echo "Cluster verification complete!"
exit
EOF

echo "=== Gitea Embedded Cluster Installation Test PASSED ==="
echo "Completed at: $(date)"