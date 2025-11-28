# Multi-Cluster Kubernetes Infrastructure
# Override with: cluster=m720q just <command>
export cluster := env_var_or_default("cluster", "homelab")

mod proxmox "scripts/just/proxmox.just"
mod baremetal "scripts/just/baremetal.just"
mod talos "scripts/just/talos.just"
mod kubectl "scripts/just/kubectl.just"
mod flux "scripts/just/flux.just"
mod tailscale "scripts/just/tailscale.just"

# Shorthand wrappers (can't alias modules directly)
px *args:
    @just proxmox {{args}}

bm *args:
    @just baremetal {{args}}

k *args:
    @just kubectl {{args}}

ts *args:
    @just tailscale {{args}}

# List available clusters
list:
    @ls -1 clusters/ 2>/dev/null | grep -v common || echo "No clusters found"

# Show help
help:
    @echo "Modules:"
    @echo "  just proxmox <cmd>   - Proxmox VM provisioning (alias: px)"
    @echo "  just baremetal <cmd> - Bare metal cluster management (alias: bm)"
    @echo "  just talos <cmd>     - Talos (talosctl) operations"
    @echo "  just kubectl <cmd>   - Kubernetes (kubectl) operations (alias: k)"
    @echo "  just flux <cmd>      - GitOps/Flux operations"
    @echo "  just tailscale <cmd> - Tailscale device management (alias: ts)"
    @echo ""
    @echo "Current cluster: ${cluster}"
    @echo ""
    @echo "For bare metal, set JUST_BM_CLUSTER:"
    @echo "  export JUST_BM_CLUSTER=m720q"
    @echo ""
    @echo "List commands: just --list <module>"
    @echo "  e.g., just --list baremetal, just --list proxmox"
