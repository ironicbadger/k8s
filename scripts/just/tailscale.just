# Tailscale management recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

# List Tailscale devices matching pattern (defaults to cluster name)
[no-cd]
list search="":
    #!/usr/bin/env bash
    set -euo pipefail
    pattern="${cluster}"
    if [[ -n "{{search}}" ]]; then
        pattern="{{search}}"
    fi
    # Just list, don't delete (script will exit after listing if no confirmation)
    ./scripts/tailscale-cleanup.sh "${pattern}" <<< "no" || true

# Clean up Tailscale devices (optional search pattern, shows stale devices >12h inactive)
[no-cd]
cleanup search="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{search}}" ]]; then
        ./scripts/tailscale-cleanup.sh "{{search}}"
    else
        ./scripts/tailscale-cleanup.sh "${cluster}"
    fi

# Show Tailscale operator and proxy status in cluster
[no-cd]
status:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just c bootstrap"
        exit 1
    fi
    export KUBECONFIG
    echo "=== Tailscale Operator ==="
    kubectl get pods -n tailscale
    echo ""
    echo "=== ProxyGroup Status ==="
    kubectl get proxygroup -n tailscale 2>/dev/null || echo "No ProxyGroups found (CRD may not be installed yet)"
    echo ""
    echo "=== To configure kubectl for Tailscale access ==="
    echo "  tailscale configure kubeconfig ${cluster}-k8s-api"
