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
        echo "❌ Error: Cluster '{{cluster}}' not found or configs not generated"
        echo "Run: just confgen cluster={{cluster}}"
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
    @ls -1 clusters/ 2>/dev/null || echo "  (none - run 'just confgen' to create from cluster.yaml)"

# Generate cluster configuration from cluster.yaml (generates Terraform + Talos config templates)
confgen cluster=cluster:
    @echo "🔄 Generating configs for cluster: {{cluster}}"
    @./scripts/confgen.sh {{cluster}}

# Initialize Terraform for cluster
init cluster=cluster:
    just _tf {{cluster}} init

# Show Terraform plan
plan cluster=cluster:
    just _tf {{cluster}} plan -var-file=secrets.tfvars

# Create/update VMs with Terraform
create cluster=cluster:
    @echo "📦 Creating cluster: {{cluster}}"
    just _tf {{cluster}} apply -auto-approve -var-file=secrets.tfvars
    @echo ""
    @echo "✅ VMs created successfully!"
    @echo ""
    @echo "Next step: just talgen cluster={{cluster}}"

# Refresh Terraform state
refresh cluster=cluster:
    just _tf {{cluster}} refresh -var-file=secrets.tfvars

# Generate Talos configs (syncs IPs from Terraform, then generates configs)
talgen cluster=cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    TALOS_DIR="clusters/{{cluster}}/talos"

    # First, sync IPs from Terraform state
    echo "🔄 Syncing IP addresses from Terraform state..."
    ./scripts/sync-ips.sh {{cluster}}
    echo ""

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
    echo "Next step: just bootstrap cluster={{cluster}}"

# Bootstrap Talos cluster
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

# Alias for talos
alias bootstrap := talos

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
    @echo "2. Copy secrets (first time only):"
    @echo "   cp terraform/secrets.tfvars clusters/{{cluster}}/terraform/"
    @echo ""
    @echo "3. Generate configs from cluster.yaml:"
    @echo "   just confgen cluster={{cluster}}"
    @echo ""
    @echo "4. Initialize Terraform (first time only):"
    @echo "   just init cluster={{cluster}}"
    @echo ""
    @echo "5. Deploy infrastructure:"
    @echo "   just create cluster={{cluster}}"
    @echo ""
    @echo "6. Generate Talos configs and bootstrap:"
    @echo "   just talgen cluster={{cluster}}      # Syncs IPs + generates configs"
    @echo "   just bootstrap cluster={{cluster}}   # Bootstrap Kubernetes"
    @echo ""
    @echo "7. Verify cluster:"
    @echo "   just status cluster={{cluster}}      # Show nodes and pods"
    @echo "   just watch cluster={{cluster}}       # Watch nodes"
    @echo ""
    @echo "To destroy:"
    @echo "   just nuke cluster={{cluster}}        # Destroy (keep secrets)"
    @echo "   just nuke cluster={{cluster}} -a     # Destroy everything"

# Show help
help:
    @echo "Kubernetes Multi-Cluster Infrastructure Manager"
    @echo ""
    @echo "Single source of truth: clusters/<name>/cluster.yaml"
    @echo ""
    @echo "Commands:"
    @echo "  just list                            List available clusters"
    @echo "  just confgen [cluster=NAME]          Generate configs from cluster.yaml"
    @echo "  just init [cluster=NAME]             Initialize Terraform"
    @echo "  just create [cluster=NAME]           Create/update VMs"
    @echo "  just talgen [cluster=NAME]           Generate Talos configs (syncs IPs)"
    @echo "  just bootstrap [cluster=NAME]        Bootstrap Kubernetes cluster"
    @echo "  just status [cluster=NAME]           Show cluster status"
    @echo "  just watch [cluster=NAME]            Watch cluster nodes"
    @echo "  just nuke [cluster=NAME] [--all]     Destroy cluster"
    @echo "  just workflow [cluster=NAME]         Show complete workflow"
    @echo ""
    @echo "Default cluster: {{cluster}}"
    @echo ""
    @echo "Examples:"
    @echo "  just confgen                         Generate homelab configs"
    @echo "  just cluster=prod create             Deploy prod cluster"
    @echo "  just cluster=dev status              Check dev cluster status"
