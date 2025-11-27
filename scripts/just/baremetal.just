# Bare metal Talos cluster management
# Usage: just bm <command>
# No nuke command - too dangerous for physical hardware

set shell := ["bash", "-euo", "pipefail", "-c"]

# Bare metal cluster (hardcoded - not using parent's $cluster)
bm_cluster := "m720q"

# Generate Talos configs
[no-cd]
genconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    if [[ ! -f "${TALOS_DIR}/talsecret.sops.yaml" ]]; then
        # Generate secret and encrypt with sops (use filename for path matching)
        talhelper gensecret > "${TALOS_DIR}/talsecret.yaml"
        sops -e "${TALOS_DIR}/talsecret.yaml" > "${TALOS_DIR}/talsecret.sops.yaml"
        rm "${TALOS_DIR}/talsecret.yaml"
        echo "Generated encrypted talsecret.sops.yaml"
    fi
    cd "${TALOS_DIR}"
    talhelper genconfig
    echo ""
    echo "Configs generated. Next steps:"
    echo "  1. Boot nodes via PiKVM with Talos ISO"
    echo "  2. Run: just bm apply <node> (name defined in talconfig.yaml)"

# Apply config to a single node (safer than bulk apply)
[no-cd]
apply node:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    cd "${TALOS_DIR}"
    IP=$(yq -r ".nodes[] | select(.hostname == \"{{node}}\") | .ipAddress" talconfig.yaml)
    if [[ -z "$IP" || "$IP" == "null" ]]; then
        echo "Error: Node '{{node}}' not found in talconfig.yaml"
        exit 1
    fi
    echo "Applying config to {{node}} (${IP})..."
    talosctl apply-config --insecure --nodes "${IP}" \
        --file "clusterconfig/talos-{{bm_cluster}}-{{node}}.yaml"
    echo "Config applied. Node will reboot and install Talos."

# Apply config to all nodes
[no-cd]
apply-all:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    cd "${TALOS_DIR}"
    for node in $(yq -r '.nodes[].hostname' talconfig.yaml); do
        IP=$(yq -r ".nodes[] | select(.hostname == \"${node}\") | .ipAddress" talconfig.yaml)
        echo "Applying config to ${node} (${IP})..."
        talosctl apply-config --insecure --nodes "${IP}" \
            --file "clusterconfig/talos-{{bm_cluster}}-${node}.yaml"
    done
    echo ""
    echo "All configs applied. Next: just bm bootstrap"

# Bootstrap etcd on first control plane
[no-cd]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    cd "${TALOS_DIR}"
    FIRST_CP=$(yq -r '.nodes[] | select(.controlPlane == true) | .ipAddress' talconfig.yaml | head -1)
    echo "Bootstrapping etcd on ${FIRST_CP}..."
    talosctl bootstrap --nodes "${FIRST_CP}" \
        --talosconfig clusterconfig/talosconfig
    echo ""
    echo "Bootstrap initiated. Wait ~60s then run: just bm kubeconfig"

# Fetch kubeconfig
[no-cd]
kubeconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    cd "${TALOS_DIR}"
    FIRST_CP=$(yq -r '.nodes[] | select(.controlPlane == true) | .ipAddress' talconfig.yaml | head -1)
    talosctl kubeconfig --nodes "${FIRST_CP}" \
        --talosconfig clusterconfig/talosconfig \
        clusterconfig/kubeconfig
    echo ""
    echo "Kubeconfig saved. To use:"
    echo "  export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig"

# Show cluster status
[no-cd]
status:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{bm_cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just bm kubeconfig"
        exit 1
    fi
    echo "Cluster: {{bm_cluster}}"
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get nodes -o wide
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get pods -A

# Watch cluster (nodes + pods + events)
[no-cd]
watch:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{bm_cluster}}/talos/clusterconfig/kubeconfig"
    export KUBECONFIG
    watch -n 2 'echo "=== NODES ===" && kubectl get nodes -o wide && echo "" && echo "=== PODS (kube-system) ===" && kubectl get pods -n kube-system -o wide && echo "" && echo "=== RECENT EVENTS ===" && kubectl get events -A --sort-by=.lastTimestamp | tail -10'

# Talos dashboard for a node
[no-cd]
dashboard node="m720q-1":
    #!/usr/bin/env bash
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    IP=$(yq -r ".nodes[] | select(.hostname == \"{{node}}\") | .ipAddress" "${TALOS_DIR}/talconfig.yaml")
    talosctl dashboard --nodes "${IP}" \
        --talosconfig "${TALOS_DIR}/clusterconfig/talosconfig"

# Upgrade Talos on a single node (use with caution)
[no-cd]
[confirm("This will upgrade Talos on {{node}}. The node will reboot. Continue?")]
upgrade node version:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    IP=$(yq -r ".nodes[] | select(.hostname == \"{{node}}\") | .ipAddress" "${TALOS_DIR}/talconfig.yaml")
    echo "Upgrading {{node}} (${IP}) to {{version}}..."
    talosctl upgrade --nodes "${IP}" \
        --talosconfig "${TALOS_DIR}/clusterconfig/talosconfig" \
        --image "factory.talos.dev/installer/{{version}}"
