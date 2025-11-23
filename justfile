# Multi-Cluster Kubernetes Infrastructure Management
# Default cluster (override with: just cluster=prod <command>)
cluster := "homelab"

# Helper: Get cluster directory
_cluster_dir cluster=cluster:
    @echo "clusters/{{cluster}}"

# Helper: Run terraform command with S3 backend credentials
_tf cluster=cluster *args:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER_DIR="clusters/{{cluster}}/terraform"
    if [[ ! -d "${CLUSTER_DIR}" ]]; then
        echo "Error: Cluster '{{cluster}}' not found. Run: just confgen cluster={{cluster}}"
        exit 1
    fi
    cd "${CLUSTER_DIR}"
    [[ -f .envrc ]] && source .envrc
    tofu {{args}}

# List available clusters
list:
    @ls -1 clusters/ 2>/dev/null || echo "No clusters found. Run 'just confgen' to create from cluster.yaml"

# Generate cluster configuration from cluster.yaml
confgen cluster=cluster:
    @./scripts/confgen.sh {{cluster}}
    @echo "Next: just create"

# Initialize Terraform for cluster (first time only)
init cluster=cluster:
    just _tf {{cluster}} init

# Show Terraform plan
plan cluster=cluster:
    just _tf {{cluster}} plan -var-file=secrets.tfvars

# Create/update VMs with Terraform
create cluster=cluster:
    just _tf {{cluster}} apply -auto-approve -var-file=secrets.tfvars
    @echo "Next: just talgen"

# Refresh Terraform state
refresh cluster=cluster:
    just _tf {{cluster}} refresh -var-file=secrets.tfvars

# Generate Talos configs (syncs IPs from Terraform, then generates configs)
talgen cluster=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{cluster}}/talos"

    ./scripts/sync-ips.sh {{cluster}}

    if [[ ! -f "${TALOS_DIR}/talsecret.yaml" ]]; then
        talhelper gensecret > "${TALOS_DIR}/talsecret.yaml"
        echo "Generated talsecret.yaml - keep this file safe!"
    fi

    cd "${TALOS_DIR}"
    talhelper genconfig
    echo "Next: just bootstrap"

# Bootstrap Talos cluster
talos cluster=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ROOT="$(pwd)"
    TALOS_DIR="clusters/{{cluster}}/talos"

    if [[ ! -d "${TALOS_DIR}/clusterconfig" ]]; then
        echo "Error: Talos configs not found. Run: just talgen cluster={{cluster}}"
        exit 1
    fi

    cd "${TALOS_DIR}"
    "${PROJECT_ROOT}/scripts/talos-apply.sh"

    echo "export TALOSCONFIG=$(pwd)/clusterconfig/talosconfig"
    echo "export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig"

# Alias for talos
alias bootstrap := talos

# Destroy cluster infrastructure
nuke cluster=cluster all="false":
    #!/usr/bin/env bash
    set -euo pipefail

    # Parse arguments: handle -a as both cluster name and delete-all flag
    CLUSTER="{{cluster}}"
    DELETE_ALL="{{all}}"
    if [ "${CLUSTER}" = "-a" ]; then
        CLUSTER="{{cluster}}"  # Use default cluster variable
        DELETE_ALL="true"
    fi

    # Confirm destruction
    read -p "Destroy cluster '${CLUSTER}'? (yes/no): " confirm
    [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }

    # Stop and destroy VMs
    just _tf ${CLUSTER} "apply -auto-approve -var-file=secrets.tfvars -var=force_stop=true" 2>/dev/null || true
    just _tf ${CLUSTER} "destroy -auto-approve -var-file=secrets.tfvars -var=force_stop=true"

    # Clean up generated configs
    TALOS_DIR="clusters/${CLUSTER}/talos"
    rm -rf ${TALOS_DIR}/clusterconfig ${TALOS_DIR}/talconfig.yaml

    # Optionally delete secrets
    if [ "${DELETE_ALL}" = "true" ] || [ "${DELETE_ALL}" = "-a" ]; then
        rm -rf ${TALOS_DIR}/talsecret.yaml
        echo "Destroyed everything including secrets"
    else
        echo "Destroyed (talsecret.yaml preserved - use 'just nuke -a' to delete)"
    fi

# Watch cluster nodes (during bootstrap)
watch cluster=cluster:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just talos cluster={{cluster}}"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" watch -n 2 kubectl get nodes

# Show cluster status
status cluster=cluster:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: Cluster {{cluster}} not bootstrapped"
        exit 1
    fi
    echo "Cluster: {{cluster}}"
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get nodes
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get pods -A

# Full workflow guide
workflow cluster=cluster:
    @echo "Workflow for cluster: {{cluster}}"
    @echo ""
    @echo "1. Edit: clusters/{{cluster}}/cluster.yaml"
    @echo "2. Generate: just confgen cluster={{cluster}}"
    @echo "3. Deploy: just create cluster={{cluster}}"
    @echo "4. Configure: just talgen cluster={{cluster}}"
    @echo "5. Bootstrap: just bootstrap cluster={{cluster}}"
    @echo "6. Verify: just status cluster={{cluster}}"
    @echo ""
    @echo "First time: just init cluster={{cluster}} (before create)"
    @echo "          : cp terraform/secrets.tfvars clusters/{{cluster}}/terraform/"
    @echo ""
    @echo "Destroy: just nuke cluster={{cluster}} (or 'just nuke -a' to delete secrets)"

# Show help
help:
    @echo "Kubernetes Multi-Cluster Infrastructure"
    @echo ""
    @echo "Typical workflow:"
    @echo "  just confgen      Generate configs from cluster.yaml"
    @echo "  just create       Deploy VMs"
    @echo "  just talgen       Generate Talos configs"
    @echo "  just bootstrap    Bootstrap Kubernetes"
    @echo "  just status       Verify cluster"
    @echo ""
    @echo "Other commands:"
    @echo "  list              List clusters"
    @echo "  init              Initialize Terraform (first time only)"
    @echo "  plan              Show Terraform plan"
    @echo "  watch             Watch nodes"
    @echo "  nuke [-a]         Destroy cluster (-a deletes secrets)"
    @echo "  workflow          Show detailed workflow"
    @echo ""
    @echo "Default cluster: {{cluster}}"
    @echo "Override with: just cluster=NAME <command>"
