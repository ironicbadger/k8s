# Kubectl operations
# Usage: just kubectl <command> or just k <command>
# Works with both Proxmox and bare metal clusters
#
# For bare metal: export JUST_BM_CLUSTER=m720q
# For Proxmox: uses $cluster variable (default: homelab)

set shell := ["bash", "-euo", "pipefail", "-c"]

# Resolve cluster: JUST_BM_CLUSTER takes precedence, then $cluster
_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# Show pods sorted by age, limited to 15
[no-cd]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    echo "Cluster: ${CLUSTER}"
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get pods -A \
        --sort-by='.metadata.creationTimestamp' \
        | tail -n +2 | tail -15 | tac
    echo ""
    echo "(showing 15 most recent pods, newest first)"

# Show nodes
[no-cd]
nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" kubectl get nodes -o wide

# Watch nodes, pods, and events
[no-cd]
watch:
    #!/usr/bin/env bash
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG
    watch -n 2 'echo "=== NODES ===" && kubectl get nodes -o wide && echo "" && echo "=== PODS (kube-system) ===" && kubectl get pods -n kube-system -o wide && echo "" && echo "=== RECENT EVENTS ===" && kubectl get events -A --sort-by=.lastTimestamp | tail -10'

# Get all pods
[no-cd]
pods namespace="-A":
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" kubectl get pods {{namespace}} -o wide

# Copy kubeconfig export to clipboard
[no-cd]
config:
    @echo "export KUBECONFIG=clusters/{{_cluster}}/talos/clusterconfig/kubeconfig" | pbcopy
    @echo "Copied to clipboard: export KUBECONFIG=clusters/{{_cluster}}/talos/clusterconfig/kubeconfig"

# Get Ceph dashboard admin password and copy to clipboard
[no-cd]
ceph-password:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    PASSWORD=$(KUBECONFIG="${KUBECONFIG}" kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
    echo "$PASSWORD" | pbcopy
    echo "Copied to clipboard: $PASSWORD"
