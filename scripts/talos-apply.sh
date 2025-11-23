#!/usr/bin/env bash
set -euo pipefail

# Apply talhelper-generated configs to Talos nodes and bootstrap cluster
# This script should be run from the cluster's talos directory (clusters/<name>/talos/)

CLUSTERCONFIG_DIR="./clusterconfig"
TALOSCONFIG="${CLUSTERCONFIG_DIR}/talosconfig"

# Check if talhelper configs exist
if [[ ! -d "${CLUSTERCONFIG_DIR}" ]]; then
  echo "❌ Error: clusterconfig/ directory not found in current directory."
  echo "This script should be run from clusters/<name>/talos/"
  echo "Please run 'just talgen' first to generate configs."
  exit 1
fi

# Check if cluster is already bootstrapped by testing connection without --insecure
export TALOSCONFIG="${TALOSCONFIG}"
HEALTH_CHECK=$(talhelper gencommand health 2>/dev/null | sed 's/talosctl health/talosctl version --short/g')

if eval "$HEALTH_CHECK" &>/dev/null; then
  echo "✅ Cluster already bootstrapped"
  SKIP_BOOTSTRAP=true

  # Show cluster status
  if [[ -f "${CLUSTERCONFIG_DIR}/kubeconfig" ]]; then
    export KUBECONFIG="${CLUSTERCONFIG_DIR}/kubeconfig"
    kubectl get nodes 2>/dev/null || true
    echo ""
  fi

  # Update kubeconfig and exit
  KUBECONFIG_CMD=$(talhelper gencommand kubeconfig)
  KUBECONFIG_CMD="${KUBECONFIG_CMD%;}"
  eval "${KUBECONFIG_CMD} --force ${CLUSTERCONFIG_DIR}/kubeconfig" &>/dev/null
  exit 0
else
  echo "🔧 Fresh cluster detected - applying configurations..."
  SKIP_BOOTSTRAP=false
fi

if [ "$SKIP_BOOTSTRAP" = false ]; then
  # Apply configs using talhelper in insecure mode (nodes have default certs initially)
  echo "🔧 Applying configurations to nodes..."
  talhelper gencommand apply --extra-flags=--insecure | bash

  # Wait for nodes to be ready with intelligent health checks
  echo "⏳ Waiting for nodes to be ready..."

  MAX_WAIT=120  # Maximum 2 minutes
  ELAPSED=0
  CHECK_INTERVAL=5

  while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if we can connect to the first control plane node
    if talosctl --talosconfig="${TALOSCONFIG}" version --insecure --nodes=$(talhelper gencommand bootstrap | grep -oP '(?<=--nodes )[^ ]+') &>/dev/null; then
      echo "✅ Nodes responding after ${ELAPSED}s"
      # Give a few more seconds for all services to stabilize
      sleep 5
      break
    fi

    echo -n "."
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
  done

  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo ""
    echo "⚠️  Nodes didn't respond within ${MAX_WAIT}s, proceeding anyway..."
  else
    echo ""
  fi

  # Bootstrap the cluster using the first control plane node with retries
  echo "🚀 Bootstrapping cluster..."

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
        echo "⚠️  Retrying bootstrap (attempt $RETRY_COUNT/$MAX_RETRIES)..."
        sleep 30
      else
        echo "❌ Bootstrap failed after $MAX_RETRIES attempts"
        exit 1
      fi
    fi
  done
fi

# Get kubeconfig with explicit output path
echo "📥 Retrieving kubeconfig..."
KUBECONFIG_CMD=$(talhelper gencommand kubeconfig)
KUBECONFIG_CMD="${KUBECONFIG_CMD%;}"
eval "${KUBECONFIG_CMD} --force ${CLUSTERCONFIG_DIR}/kubeconfig"

echo "✅ Cluster ready!"
