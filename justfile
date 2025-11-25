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
    PROJECT_ROOT="$(pwd)"
    CLUSTER_DIR="clusters/{{cluster}}/terraform"
    if [[ ! -d "${CLUSTER_DIR}" ]]; then
        echo "Error: Cluster '{{cluster}}' not found. Run: just confgen cluster={{cluster}}"
        exit 1
    fi
    cd "${CLUSTER_DIR}"

    # Generate secrets.tfvars and set S3 backend credentials from encrypted secrets.sops.yaml
    if [[ -f "${PROJECT_ROOT}/secrets.sops.yaml" ]]; then
        SECRETS_JSON=$(sops -d --output-type json "${PROJECT_ROOT}/secrets.sops.yaml")

        # Generate secrets.tfvars for Terraform variables
        echo "$SECRETS_JSON" | jq -r '
            to_entries |
            map("\(.key) = \"\(.value)\"") |
            join("\n")
        ' > secrets.tfvars

        # Export S3 backend credentials for Terraform
        export AWS_ACCESS_KEY_ID=$(echo "$SECRETS_JSON" | jq -r '.terraform_garage_s3_keyid')
        export AWS_SECRET_ACCESS_KEY=$(echo "$SECRETS_JSON" | jq -r '.terraform_garage_s3_secretkey')
    fi

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

    ./scripts/gen-talconfig.sh {{cluster}}

    if [[ ! -f "${TALOS_DIR}/talsecret.sops.yaml" ]]; then
        talhelper gensecret | sops -e /dev/stdin > "${TALOS_DIR}/talsecret.sops.yaml"
        echo "Generated encrypted talsecret.sops.yaml"
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
nuke all="false":
    #!/usr/bin/env bash
    set -euo pipefail

    CLUSTER="{{cluster}}"
    DELETE_ALL="{{all}}"

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
    if [ "${DELETE_ALL}" = "true" ]; then
        rm -rf ${TALOS_DIR}/talsecret.sops.yaml
        echo "Destroyed everything including secrets"
    else
        echo "Destroyed (talsecret.sops.yaml preserved - use 'just nuke all=true' to delete)"
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

# Build cluster from scratch (all steps in one command)
fromscratch cluster=cluster:
    just cluster={{cluster}} confgen
    just cluster={{cluster}} init
    just cluster={{cluster}} create
    just cluster={{cluster}} talgen
    just cluster={{cluster}} bootstrap

# Show help
help:
    @echo "Kubernetes Multi-Cluster Infrastructure"
    @echo ""
    @echo "Typical workflow:"
    @echo "  just fromscratch  Build cluster from scratch (all steps)"
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
    @echo "  nuke [all=true]   Destroy cluster (all=true deletes secrets)"
    @echo "  workflow          Show detailed workflow"
    @echo ""
    @echo "Default cluster: {{cluster}}"
    @echo "Override with: just cluster=NAME <command>"
