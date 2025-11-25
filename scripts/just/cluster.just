# Cluster provisioning recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

# Helper: Run terraform command with S3 backend credentials
[private]
[no-cd]
_tf *args:
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ROOT="$(pwd)"
    CLUSTER_DIR="clusters/${cluster}/terraform"
    if [[ ! -d "${CLUSTER_DIR}" ]]; then
        echo "Error: Cluster '${cluster}' not found. Run: just c confgen"
        exit 1
    fi
    cd "${CLUSTER_DIR}"
    if [[ -f "${PROJECT_ROOT}/secrets.sops.yaml" ]]; then
        SECRETS_JSON=$(sops -d --output-type json "${PROJECT_ROOT}/secrets.sops.yaml")
        echo "$SECRETS_JSON" | jq -r 'to_entries | map("\(.key) = \"\(.value)\"") | join("\n")' > secrets.tfvars
        export AWS_ACCESS_KEY_ID=$(echo "$SECRETS_JSON" | jq -r '.terraform_garage_s3_keyid')
        export AWS_SECRET_ACCESS_KEY=$(echo "$SECRETS_JSON" | jq -r '.terraform_garage_s3_secretkey')
    fi
    tofu {{args}}

# Generate cluster configuration from cluster.yaml
[no-cd]
confgen:
    @./scripts/confgen.sh ${cluster}
    @echo "Next: just c create"

# Initialize Terraform (first time only)
[no-cd]
init:
    just cluster::_tf init

# Show Terraform plan
[no-cd]
plan:
    just cluster::_tf plan -var-file=secrets.tfvars

# Create/update VMs with Terraform
[no-cd]
create:
    just cluster::_tf apply -auto-approve -var-file=secrets.tfvars
    @echo "Next: just c talgen"

# Refresh Terraform state
[no-cd]
refresh:
    just cluster::_tf refresh -var-file=secrets.tfvars

# Generate Talos configs
[no-cd]
talgen:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/${cluster}/talos"
    ./scripts/gen-talconfig.sh ${cluster}
    if [[ ! -f "${TALOS_DIR}/talsecret.sops.yaml" ]]; then
        talhelper gensecret | sops -e /dev/stdin > "${TALOS_DIR}/talsecret.sops.yaml"
        echo "Generated encrypted talsecret.sops.yaml"
    fi
    cd "${TALOS_DIR}"
    talhelper genconfig
    echo "Next: just c bootstrap"

# Bootstrap Talos cluster
[no-cd]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ROOT="$(pwd)"
    TALOS_DIR="clusters/${cluster}/talos"
    if [[ ! -d "${TALOS_DIR}/clusterconfig" ]]; then
        echo "Error: Talos configs not found. Run: just c talgen"
        exit 1
    fi
    cd "${TALOS_DIR}"
    "${PROJECT_ROOT}/scripts/talos-apply.sh"
    echo "export TALOSCONFIG=$(pwd)/clusterconfig/talosconfig"
    echo "export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig"
    echo "Next step is to bootstrap flux with 'just flux bootstrap'"

# Destroy cluster infrastructure
[no-cd]
nuke all="false":
    #!/usr/bin/env bash
    set -euo pipefail
    DELETE_ALL="{{all}}"
    read -p "Destroy cluster '${cluster}'? (yes/no): " confirm
    [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }

    # Start Tailscale cleanup in background (has its own confirmation)
    echo ""
    echo "=== Tailscale Cleanup ==="
    ./scripts/tailscale-cleanup.sh "${cluster}" &
    TS_PID=$!

    # Run Terraform destroy in parallel
    echo ""
    echo "=== Proxmox/Terraform Cleanup ==="
    just cluster::_tf "apply -auto-approve -var-file=secrets.tfvars -var=force_stop=true" 2>/dev/null || true
    just cluster::_tf "destroy -auto-approve -var-file=secrets.tfvars -var=force_stop=true"

    # Wait for Tailscale cleanup to complete
    wait $TS_PID || echo "Warning: Tailscale cleanup may have failed"

    # Clean up local configs
    TALOS_DIR="clusters/${cluster}/talos"
    rm -rf ${TALOS_DIR}/clusterconfig ${TALOS_DIR}/talconfig.yaml
    if [ "${DELETE_ALL}" = "true" ]; then
        rm -rf ${TALOS_DIR}/talsecret.sops.yaml
        echo "Destroyed everything including secrets"
    else
        echo "Destroyed (talsecret.sops.yaml preserved)"
    fi

# List Tailscale devices matching cluster
[no-cd]
ts-list:
    #!/usr/bin/env bash
    set -euo pipefail
    # Just list, don't delete (script will exit after listing if no confirmation)
    ./scripts/tailscale-cleanup.sh "${cluster}" <<< "no" || true

# Clean up Tailscale devices for cluster
[no-cd]
ts-cleanup:
    ./scripts/tailscale-cleanup.sh "${cluster}"

# Show Tailscale operator and proxy status
[no-cd]
ts-status:
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

# Watch cluster nodes
[no-cd]
watch:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just c bootstrap"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" watch -n 2 kubectl get nodes

# Show cluster status
[no-cd]
status:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: Cluster ${cluster} not bootstrapped"
        exit 1
    fi
    echo "Cluster: ${cluster}"
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get nodes
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get pods -A

# Build cluster from scratch
[no-cd]
fromscratch:
    @echo "A brand new cluster from scratch you say? Yesssssssssir-y! Can doooooo."
    just cluster confgen
    just cluster init
    just cluster create
    just cluster talgen
    just cluster bootstrap

alias fs := fromscratch
