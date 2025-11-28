# Tailscale management recipes
# Usage: just tailscale <command> or just ts <command>
#
# For bare metal: export JUST_BM_CLUSTER=m720q
# For Proxmox: uses $cluster variable (default: homelab)

set shell := ["bash", "-euo", "pipefail", "-c"]

# Resolve cluster: JUST_BM_CLUSTER takes precedence, then $cluster
_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# List Tailscale devices matching pattern (defaults to cluster name)
[no-cd]
list search="":
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    pattern="${CLUSTER}"
    if [[ -n "{{search}}" ]]; then
        pattern="{{search}}"
    fi
    # Just list, dont delete (script will exit after listing if no confirmation)
    ./scripts/tailscale-cleanup.sh "${pattern}" <<< "no" || true

# Clean up Tailscale devices (optional search pattern, shows stale devices >12h inactive)
[no-cd]
cleanup search="":
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    if [[ -n "{{search}}" ]]; then
        ./scripts/tailscale-cleanup.sh "{{search}}"
    else
        ./scripts/tailscale-cleanup.sh "${CLUSTER}"
    fi

# Show Tailscale operator and proxy status in cluster
[no-cd]
status:
    #!/usr/bin/env bash
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
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
    echo "  tailscale configure kubeconfig ${CLUSTER}-k8s-api"
