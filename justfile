# Multi-Cluster Kubernetes Infrastructure
# Override with: cluster=m720q just <command>
export cluster := env_var_or_default("cluster", "homelab")

mod cluster "scripts/just/cluster.just"
mod flux "scripts/just/flux.just"
mod baremetal "scripts/just/baremetal.just"
mod tailscale "scripts/just/tailscale.just"

# Shorthand wrappers (can't alias modules directly)
c *args:
    @just cluster {{args}}

bm *args:
    @just baremetal {{args}}

ts *args:
    @just tailscale {{args}}

# List available clusters
list:
    @ls -1 clusters/ 2>/dev/null || echo "No clusters found"

# Show help
help:
    @echo "Modules:"
    @echo "  just cluster <cmd>   - Cluster provisioning (Proxmox VMs)"
    @echo "  just baremetal <cmd> - Bare metal cluster management"
    @echo "  just flux <cmd>      - GitOps/Flux operations"
    @echo "  just tailscale <cmd> - Tailscale device management"
    @echo ""
    @echo "Aliases: c -> cluster, bm -> baremetal, ts -> tailscale"
    @echo ""
    @echo "Run 'just --list cluster' or 'just --list flux' to see commands"
    @echo ""
