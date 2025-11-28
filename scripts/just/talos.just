# Talos (talosctl) operations
# Usage: just talos <command>
# Works with both Proxmox and bare metal clusters
#
# For bare metal: export JUST_BM_CLUSTER=m720q
# For Proxmox: uses $cluster variable (default: homelab)

set shell := ["bash", "-euo", "pipefail", "-c"]

# Resolve cluster: JUST_BM_CLUSTER takes precedence, then $cluster
_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# Talos dashboard for node(s) - supports comma-separated list
[no-cd]
dashboard +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    TALOS_DIR="clusters/${CLUSTER}/talos"
    if [[ ! -f "${TALOS_DIR}/talconfig.yaml" ]]; then
        echo "Error: talconfig.yaml not found for cluster '${CLUSTER}'"
        exit 1
    fi

    # Handle comma-separated or space-separated nodes
    NODES_INPUT="{{nodes}}"
    NODES_INPUT="${NODES_INPUT//,/ }"  # Replace commas with spaces

    IPS=""
    for node in ${NODES_INPUT}; do
        IP=$(yq -r ".nodes[] | select(.hostname == \"${node}\") | .ipAddress" "${TALOS_DIR}/talconfig.yaml")
        if [[ -z "$IP" || "$IP" == "null" ]]; then
            echo "Error: Node '${node}' not found in talconfig.yaml"
            echo ""
            echo "Available nodes:"
            yq -r '.nodes[].hostname' "${TALOS_DIR}/talconfig.yaml" | sed 's/^/  /'
            exit 1
        fi
        if [[ -n "$IPS" ]]; then
            IPS="${IPS},${IP}"
        else
            IPS="${IP}"
        fi
    done

    talosctl dashboard --nodes "${IPS}" \
        --talosconfig "${TALOS_DIR}/clusterconfig/talosconfig"

# Check cluster health
[no-cd]
health:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    TALOS_DIR="clusters/${CLUSTER}/talos"
    if [[ ! -f "${TALOS_DIR}/clusterconfig/talosconfig" ]]; then
        echo "Error: talosconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    FIRST_CP=$(yq -r '.nodes[] | select(.controlPlane == true) | .ipAddress' "${TALOS_DIR}/talconfig.yaml" | head -1)
    talosctl health --nodes "${FIRST_CP}" \
        --talosconfig "${TALOS_DIR}/clusterconfig/talosconfig"

# List nodes from talconfig.yaml
[no-cd]
nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    TALOS_DIR="clusters/${CLUSTER}/talos"
    if [[ ! -f "${TALOS_DIR}/talconfig.yaml" ]]; then
        echo "Error: talconfig.yaml not found for cluster '${CLUSTER}'"
        exit 1
    fi
    echo "Nodes in cluster '${CLUSTER}':"
    echo ""
    yq -r '.nodes[] | "\(.hostname)\t\(.ipAddress)\t\(if .controlPlane then "control-plane" else "worker" end)"' \
        "${TALOS_DIR}/talconfig.yaml" | column -t
