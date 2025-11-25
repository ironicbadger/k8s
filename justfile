# Multi-Cluster Kubernetes Infrastructure
export cluster := "homelab"

mod cluster "scripts/just/cluster.just"
mod flux "scripts/just/flux.just"

# Shorthand wrappers (can't alias modules directly)
c *args:
    @just cluster {{args}}

# List available clusters
list:
    @ls -1 clusters/ 2>/dev/null || echo "No clusters found"

# Show help
help:
    @echo "Modules:"
    @echo "  just cluster <cmd>  - Cluster provisioning"
    @echo "  just flux <cmd>     - GitOps/Flux operations"
    @echo ""
    @echo "Run 'just --list cluster' or 'just --list flux' to see commands"
    @echo ""
