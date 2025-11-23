# OpenTofu + Talos cluster commands

# Run tofu command with S3 backend credentials loaded
_tf *args:
    #!/usr/bin/env bash
    cd terraform
    source .envrc
    tofu {{args}}

# Initialize OpenTofu with Garage S3 backend
init: (_tf "init")

# Show plan
plan: (_tf "plan -var-file=secrets.tfvars")

# Create VMs
apply: (_tf "apply -auto-approve -var-file=secrets.tfvars")
    @echo ""
    @echo "✅ VMs created successfully!"
    @echo ""
    @echo "Next step: just talgen"

# Alias for apply
alias create := apply

# Refresh state
refresh: (_tf "refresh -var-file=secrets.tfvars")

# Apply talhelper configs and bootstrap cluster
talos:
    ./scripts/talos-apply.sh

# Generate talhelper configs (syncs IPs from Terraform, generates secrets if needed, then configs)
talgen:
    @echo "Syncing IP addresses from Terraform state..."
    @./scripts/talhelper-sync-ip-info.sh
    @echo ""
    @if [ ! -f talsecret.yaml ]; then \
        echo "Generating talhelper secrets..."; \
        talhelper gensecret > talsecret.yaml; \
        echo "Generated talsecret.yaml - keep this file safe!"; \
        echo ""; \
    fi
    @echo "⚙️  Generating Talos configs..."
    @talhelper genconfig
    @echo ""
    @echo "✅ Generated configs in clusterconfig/ directory"
    @echo ""
    @echo "Next step: just talos"

# Destroy infrastructure (force stop VMs). Use 'just nuke --all' to also delete secrets
nuke *args:
    @echo "💣 Forcing shutdown of all VMs..."
    -just _tf "apply -auto-approve -var-file=secrets.tfvars -var=force_stop=true -target=module.control_plane -target=module.workers" 2>/dev/null || true
    @echo "🗑️  Destroying infrastructure..."
    just _tf "destroy -auto-approve -var-file=secrets.tfvars -var=force_stop=true"
    @echo ""
    @if echo "{{args}}" | grep -qE "(--all|-a)"; then \
        echo "🧹 Cleaning up ALL configs including secrets..."; \
        rm -rf _out clusterconfig talconfig.yaml talsecret.yaml; \
        echo "✅ Everything destroyed - full clean slate!"; \
    else \
        echo "🧹 Cleaning up generated configs..."; \
        rm -rf _out clusterconfig talconfig.yaml; \
        echo "✅ Infrastructure destroyed and configs cleaned up"; \
        echo ""; \
        echo "Note: talsecret.yaml was preserved - use 'just nuke --all' to delete it too"; \
    fi

# Export environment variables - copy and run: eval "$(just env)"
export:
    @echo 'Run this command to export the variables:'
    @echo ''
    @echo 'eval "$(just env)"'

# Output export commands (used by: eval "$(just env)")
env:
    @echo 'export TALOSCONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/talosconfig'
    @echo 'export KUBECONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/kubeconfig'

# Show cluster status
status:
    TALOSCONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/talosconfig \
    KUBECONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/kubeconfig \
    kubectl get nodes

# Watch nodes during cluster bootstrapping
watch:
    @if [ ! -f clusterconfig/kubeconfig ]; then \
        echo "❌ Error: clusterconfig/kubeconfig not found"; \
        echo "Run 'just talos' first to bootstrap the cluster"; \
        exit 1; \
    fi
    @echo "Watching cluster nodes (Ctrl+C to stop)..."
    @KUBECONFIG=clusterconfig/kubeconfig watch -n 2 kubectl get nodes

# Full workflow hint
cluster:
    @echo "Workflow:"
    @echo "  1. just apply  - Create VMs with Terraform"
    @echo "  2. just talgen - Sync IPs & generate Talos configs"
    @echo "  3. just talos  - Configure Talos & bootstrap cluster"