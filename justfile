# Multi-Cluster Kubernetes Infrastructure Management
# Uses unified cluster.yaml as single source of truth

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
        echo "❌ Error: Cluster '{{cluster}}' not found or not synced"
        echo "Run: just sync cluster={{cluster}}"
        exit 1
    fi
    cd "${CLUSTER_DIR}"
    if [[ -f .envrc ]]; then
        source .envrc
    fi
    tofu {{args}}

# List available clusters
list:
    @echo "Available clusters:"
    @ls -1 clusters/ 2>/dev/null || echo "  (none - run 'just sync' to create from cluster.yaml)"

# Sync cluster configuration from cluster.yaml (generates Terraform + Talos config templates)
sync cluster=cluster:
    @echo "🔄 Syncing cluster: {{cluster}}"
    @./scripts/sync-cluster.sh {{cluster}}

# Sync all clusters
sync-all:
    #!/usr/bin/env bash
    for cluster_dir in clusters/*/; do
        cluster=$(basename "$cluster_dir")
        echo "🔄 Syncing ${cluster}..."
        just sync cluster="${cluster}"
        echo ""
    done

# Initialize Terraform for cluster
init cluster=cluster: (sync cluster)
    just _tf {{cluster}} init

# Show Terraform plan
plan cluster=cluster:
    just _tf {{cluster}} plan -var-file=secrets.tfvars

# Create/update VMs with Terraform
apply cluster=cluster:
    @echo "📦 Deploying cluster: {{cluster}}"
    just _tf {{cluster}} apply -auto-approve -var-file=secrets.tfvars
    @echo ""
    @echo "✅ VMs created successfully!"
    @echo ""
    @echo "Next step: just sync-ips cluster={{cluster}}"

# Alias for apply
alias create := apply

# Refresh Terraform state
refresh cluster=cluster:
    just _tf {{cluster}} refresh -var-file=secrets.tfvars

# Sync IP addresses from Terraform state to talconfig.yaml
sync-ips cluster=cluster:
    @./scripts/sync-ips.sh {{cluster}}

# Generate talhelper configs (after sync-ips)
talgen cluster=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{cluster}}/talos"

    if [[ ! -f "${TALOS_DIR}/talconfig.yaml" ]]; then
        echo "❌ Error: talconfig.yaml not found"
        echo "Run: just sync-ips cluster={{cluster}}"
        exit 1
    fi

    # Generate secrets if needed
    if [[ ! -f "${TALOS_DIR}/talsecret.yaml" ]]; then
        echo "🔐 Generating talhelper secrets..."
        talhelper gensecret > "${TALOS_DIR}/talsecret.yaml"
        echo "   ✅ Generated talsecret.yaml - keep this file safe!"
        echo ""
    fi

    echo "⚙️  Generating Talos configs..."
    cd "${TALOS_DIR}"
    talhelper genconfig
    echo ""
    echo "✅ Generated configs in ${TALOS_DIR}/clusterconfig/"
    echo ""
    echo "Next step: just talos cluster={{cluster}}"

# Apply Talos configuration and bootstrap cluster
talos cluster=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{cluster}}/talos"

    if [[ ! -d "${TALOS_DIR}/clusterconfig" ]]; then
        echo "❌ Error: Talos configs not found"
        echo "Run: just talgen cluster={{cluster}}"
        exit 1
    fi

    echo "🚀 Bootstrapping Talos cluster: {{cluster}}"
    cd "${TALOS_DIR}"

    # Use the existing talos-apply.sh script (relative to project root)
    ../../scripts/talos-apply.sh

    echo ""
    echo "✅ Cluster bootstrap complete!"
    echo ""
    echo "Export config:"
    echo "  export TALOSCONFIG=$(pwd)/clusterconfig/talosconfig"
    echo "  export KUBECONFIG=$(pwd)/clusterconfig/kubeconfig"

# Destroy cluster infrastructure
nuke cluster=cluster *args:
    @echo "💣 Destroying cluster: {{cluster}}"
    @echo ""
    @read -p "Are you sure you want to destroy cluster '{{cluster}}'? (yes/no): " confirm; \
    if [ "$confirm" != "yes" ]; then \
        echo "Aborted."; \
        exit 1; \
    fi
    @echo ""
    @echo "💣 Forcing shutdown of all VMs..."
    -just _tf {{cluster}} "apply -auto-approve -var-file=secrets.tfvars -var=force_stop=true" 2>/dev/null || true
    @echo "🗑️  Destroying infrastructure..."
    just _tf {{cluster}} "destroy -auto-approve -var-file=secrets.tfvars -var=force_stop=true"
    @echo ""
    @if echo "{{args}}" | grep -qE "(--all|-a)"; then \
        echo "🧹 Cleaning up ALL configs including secrets..."; \
        rm -rf clusters/{{cluster}}/talos/clusterconfig clusters/{{cluster}}/talos/talconfig.yaml clusters/{{cluster}}/talos/talsecret.yaml; \
        echo "✅ Everything destroyed - full clean slate!"; \
    else \
        echo "🧹 Cleaning up generated configs..."; \
        rm -rf clusters/{{cluster}}/talos/clusterconfig clusters/{{cluster}}/talos/talconfig.yaml; \
        echo "✅ Infrastructure destroyed and configs cleaned up"; \
        echo ""; \
        echo "Note: talsecret.yaml was preserved - use 'just nuke cluster={{cluster}} --all' to delete it too"; \
    fi

# Watch cluster nodes (during bootstrap)
watch cluster=cluster:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "❌ Error: kubeconfig not found"
        echo "Run 'just talos cluster={{cluster}}' first to bootstrap the cluster"
        exit 1
    fi
    echo "👀 Watching cluster nodes (Ctrl+C to stop)..."
    KUBECONFIG="${KUBECONFIG}" watch -n 2 kubectl get nodes

# Show cluster status
status cluster=cluster:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/{{cluster}}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "❌ Error: kubeconfig not found"
        echo "Cluster {{cluster}} is not bootstrapped yet"
        exit 1
    fi
    echo "Cluster: {{cluster}}"
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get nodes
    echo ""
    KUBECONFIG="${KUBECONFIG}" kubectl get pods -A

# Full workflow guide
workflow cluster=cluster:
    @echo "Complete workflow for cluster: {{cluster}}"
    @echo ""
    @echo "1. Edit cluster configuration:"
    @echo "   vim clusters/{{cluster}}/cluster.yaml"
    @echo ""
    @echo "2. Sync configuration (generates Terraform + Talos templates):"
    @echo "   just sync cluster={{cluster}}"
    @echo ""
    @echo "3. Copy secrets (first time only):"
    @echo "   cp terraform/secrets.tfvars clusters/{{cluster}}/terraform/"
    @echo ""
    @echo "4. Deploy infrastructure:"
    @echo "   just init cluster={{cluster}}      # Initialize Terraform"
    @echo "   just apply cluster={{cluster}}     # Create VMs"
    @echo ""
    @echo "5. Configure Kubernetes:"
    @echo "   just sync-ips cluster={{cluster}}  # Sync IPs from Terraform"
    @echo "   just talgen cluster={{cluster}}    # Generate Talos configs"
    @echo "   just talos cluster={{cluster}}     # Bootstrap cluster"
    @echo ""
    @echo "6. Verify cluster:"
    @echo "   just status cluster={{cluster}}    # Show nodes and pods"
    @echo "   just watch cluster={{cluster}}     # Watch nodes"
    @echo ""
    @echo "To destroy:"
    @echo "   just nuke cluster={{cluster}}      # Destroy (keep secrets)"
    @echo "   just nuke cluster={{cluster}} -a   # Destroy everything"

# Show help
help:
    @echo "Kubernetes Multi-Cluster Infrastructure Manager"
    @echo ""
    @echo "Single source of truth: clusters/<name>/cluster.yaml"
    @echo ""
    @echo "Commands:"
    @echo "  just list                          List available clusters"
    @echo "  just sync [cluster=NAME]           Sync cluster config from cluster.yaml"
    @echo "  just init [cluster=NAME]           Initialize Terraform"
    @echo "  just apply [cluster=NAME]          Create/update VMs"
    @echo "  just sync-ips [cluster=NAME]       Sync IPs to Talos config"
    @echo "  just talgen [cluster=NAME]         Generate Talos configs"
    @echo "  just talos [cluster=NAME]          Bootstrap Talos cluster"
    @echo "  just status [cluster=NAME]         Show cluster status"
    @echo "  just watch [cluster=NAME]          Watch cluster nodes"
    @echo "  just nuke [cluster=NAME] [--all]   Destroy cluster"
    @echo "  just workflow [cluster=NAME]       Show complete workflow"
    @echo ""
    @echo "Default cluster: {{cluster}}"
    @echo ""
    @echo "Examples:"
    @echo "  just sync                          Sync homelab cluster"
    @echo "  just cluster=prod apply            Deploy prod cluster"
    @echo "  just cluster=dev status            Check dev cluster status"
