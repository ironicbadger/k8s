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

# Run intel_gpu_top to monitor Intel GPU usage (for Jellyfin transcoding, etc)
# Optional: specify node name to override auto-detection from jellyfin pod
[no-cd]
gpu-top node="":
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG
    if [[ -n "{{node}}" ]]; then
        NODE="{{node}}"
    else
        NODE=$(kubectl get pods -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].spec.nodeName}')
        if [[ -z "${NODE}" ]]; then
            echo "Error: could not find jellyfin pod, specify node manually: just k gpu-top <node-name>"
            exit 1
        fi
    fi
    echo "Running intel_gpu_top on node: ${NODE}"
    kubectl run gpu-debug -n jellyfin --rm -it --restart=Never \
        --image=ghcr.io/ironicbadger/docker-intel-gpu-tools \
        --overrides="{
            \"spec\": {
                \"nodeName\": \"${NODE}\",
                \"containers\": [{
                    \"name\": \"gpu-debug\",
                    \"image\": \"ghcr.io/ironicbadger/docker-intel-gpu-tools\",
                    \"command\": [\"intel_gpu_top\"],
                    \"stdin\": true,
                    \"tty\": true,
                    \"securityContext\": {\"privileged\": true},
                    \"volumeMounts\": [{\"name\": \"dri\", \"mountPath\": \"/dev/dri\"}]
                }],
                \"volumes\": [{\"name\": \"dri\", \"hostPath\": {\"path\": \"/dev/dri\"}}]
            }
        }"

