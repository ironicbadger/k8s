# Bare metal Talos cluster management
# Usage: export JUST_BM_CLUSTER=m720q && just bm <command>
# No nuke command - too dangerous for physical hardware

set shell := ["bash", "-euo", "pipefail", "-c"]

# Cluster name from environment variable
bm_cluster := env_var_or_default("JUST_BM_CLUSTER", "")

# Guard: check cluster is set
[private]
[no-cd]
_check_cluster:
    #!/usr/bin/env bash
    if [[ -z "{{bm_cluster}}" ]]; then
        echo "Error: JUST_BM_CLUSTER not set"
        echo ""
        echo "Set it with:"
        echo "  export JUST_BM_CLUSTER=m720q"
        exit 1
    fi
    if [[ ! -d "clusters/{{bm_cluster}}" ]]; then
        echo "Error: Cluster directory not found: clusters/{{bm_cluster}}"
        exit 1
    fi

# Generate Talos configs from talconfig.yaml
[no-cd]
confgen: _check_cluster
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

# Apply config to a single node
# Pass --insecure for initial install on fresh nodes
[no-cd]
apply node *args: _check_cluster
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
    if [[ "{{args}}" == *"--insecure"* ]]; then
        talosctl apply-config --insecure --nodes "${IP}" \
            --file "clusterconfig/talos-{{bm_cluster}}-{{node}}.yaml"
    else
        talosctl apply-config --nodes "${IP}" \
            --talosconfig clusterconfig/talosconfig \
            --file "clusterconfig/talos-{{bm_cluster}}-{{node}}.yaml"
    fi
    echo "Config applied."

# Apply config to all nodes
# Pass --insecure for initial install on fresh nodes
[no-cd]
apply-all *args: _check_cluster
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{bm_cluster}}/talos"
    cd "${TALOS_DIR}"

    if [[ "{{args}}" == *"--insecure"* ]]; then
        AUTH_ARGS="--insecure"
        echo "Applying configs for initial install..."
    else
        AUTH_ARGS="--talosconfig clusterconfig/talosconfig"
        echo "Applying configs to running cluster..."
    fi

    for node in $(yq -r '.nodes[].hostname' talconfig.yaml); do
        IP=$(yq -r ".nodes[] | select(.hostname == \"${node}\") | .ipAddress" talconfig.yaml)
        echo "Applying config to ${node} (${IP})..."
        talosctl apply-config ${AUTH_ARGS} --nodes "${IP}" \
            --file "clusterconfig/talos-{{bm_cluster}}-${node}.yaml"
    done
    echo "All configs applied."

# Bootstrap etcd on first control plane
[no-cd]
bootstrap: _check_cluster
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
kubeconfig: _check_cluster
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

# Install Cilium CNI (required before Flux bootstrap)
[no-cd]
cilium: _check_cluster
    #!/usr/bin/env bash
    set -euo pipefail
    KUBECONFIG="clusters/{{bm_cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "$KUBECONFIG" ]]; then
        echo "Error: kubeconfig not found. Run 'just bm kubeconfig' first."
        exit 1
    fi
    export KUBECONFIG
    helm repo add cilium https://helm.cilium.io/
    helm repo update cilium
    echo "Installing Cilium..."
    helm install cilium cilium/cilium --version 1.16.4 --namespace kube-system \
      --set ipam.mode=kubernetes \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost=127.0.0.1 \
      --set k8sServicePort=7445 \
      --set cgroup.autoMount.enabled=false \
      --set cgroup.hostRoot=/sys/fs/cgroup \
      --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
      --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    echo ""
    echo "Cilium installed. Wait for nodes to become Ready:"
    echo "  kubectl get nodes -w"