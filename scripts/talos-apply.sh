#!/usr/bin/env bash
set -euo pipefail

# Apply talhelper-generated configs to Talos nodes and bootstrap cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTERCONFIG_DIR="${PROJECT_ROOT}/clusterconfig"
TALOSCONFIG="${CLUSTERCONFIG_DIR}/talosconfig"

# Check if talhelper configs exist
if [[ ! -d "${CLUSTERCONFIG_DIR}" ]]; then
  echo "❌ Error: clusterconfig/ directory not found."
  echo "Please run 'just talhelper-gen' first to generate configs."
  exit 1
fi

echo "=== Applying Talhelper-Generated Configs ==="
echo ""

# Apply configs using talhelper in insecure mode (nodes have default certs initially)
echo "🔧 Applying configurations to nodes (insecure mode for initial setup)..."
talhelper gencommand apply --extra-flags=--insecure | bash

echo ""
echo "=== Bootstrapping Cluster ==="
echo ""

# Wait for nodes to be ready and time to sync
echo "⏳ Waiting for nodes to sync time and be ready..."
echo "   (This can take 1-2 minutes for NTP sync)"
sleep 60

# Bootstrap the cluster using the first control plane node with retries
echo "🚀 Bootstrapping cluster..."
export TALOSCONFIG="${TALOSCONFIG}"

BOOTSTRAP_CMD=$(talhelper gencommand bootstrap)
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if eval "$BOOTSTRAP_CMD"; then
    echo "✅ Bootstrap successful!"
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "⚠️  Bootstrap failed (attempt $RETRY_COUNT/$MAX_RETRIES). Waiting 30s for time sync..."
      sleep 30
    else
      echo "❌ Bootstrap failed after $MAX_RETRIES attempts"
      exit 1
    fi
  fi
done

echo ""
echo "=== Retrieving Kubeconfig ==="
echo ""

# Get kubeconfig
talhelper gencommand kubeconfig | bash

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Talosconfig: ${TALOSCONFIG}"
echo "Kubeconfig:  ${CLUSTERCONFIG_DIR}/kubeconfig"
echo ""
echo "Export these to use the cluster:"
echo "  export TALOSCONFIG=${TALOSCONFIG}"
echo "  export KUBECONFIG=${CLUSTERCONFIG_DIR}/kubeconfig"
echo "  kubectl get nodes"
