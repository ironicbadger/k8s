# Kubernetes Multi-Cluster Infrastructure

Unified infrastructure-as-code for managing multiple Kubernetes clusters on Proxmox using Talos Linux.

## Architecture

**Single Source of Truth**: `clusters/<name>/cluster.yaml`

This file defines everything about a cluster:
- Node counts (control plane and workers)
- Resource allocations (CPU, memory, disk)
- Proxmox settings
- Talos configuration
- GitOps settings

From this one file, we generate:
- Terraform configurations (for VM provisioning)
- Talos configurations (for Kubernetes bootstrapping)

## Directory Structure

```
.
├── clusters/                    # Per-cluster configurations
│   └── homelab/
│       ├── cluster.yaml         # ← SINGLE SOURCE OF TRUTH
│       ├── terraform/           # Generated Terraform configs
│       └── talos/               # Generated Talos configs
│
├── modules/                     # Reusable Terraform modules
│   └── talos-proxmox/           # Proxmox VM module for Talos
│
├── infrastructure/              # Shared Kubernetes addons (Flux/Kustomize)
│   ├── sources/                 # Helm repos
│   ├── core/                    # Required components (cert-manager, ingress)
│   │   ├── base/
│   │   └── overlays/
│   │       ├── homelab/         # Homelab-specific values
│   │       ├── dev/
│   │       └── prod/
│   └── optional/                # Optional components
│
├── scripts/                     # Automation scripts
│   ├── sync-cluster.sh          # Generate configs from cluster.yaml
│   ├── sync-ips.sh              # Sync IPs from Terraform to Talos
│   └── talos-apply.sh           # Bootstrap Talos cluster
│
└── justfile                     # Command runner (just <command>)
```

## Quick Start

### 1. Create a Cluster Configuration

Edit the cluster definition:

```bash
vim clusters/homelab/cluster.yaml
```

Adjust node counts and resources as needed:

```yaml
cluster:
  topology:
    controlPlane:
      count: 3  # Change to 1 for small homelab
      resources:
        cores: 4
        memory: 8192
        disk: 32
    workers:
      count: 3  # Change to 1 for small homelab
      resources:
        cores: 8
        memory: 16384
        disk: 100
```

### 2. Sync Configuration

Generate Terraform and Talos configs from cluster.yaml:

```bash
just sync
```

### 3. Deploy Infrastructure

```bash
# Copy secrets (first time only)
cp terraform/secrets.tfvars clusters/homelab/terraform/

# Initialize and deploy
just init      # Initialize Terraform
just apply     # Create VMs
```

### 4. Bootstrap Kubernetes

```bash
just sync-ips  # Sync IPs from Terraform to Talos config
just talgen    # Generate Talos configs
just talos     # Bootstrap Kubernetes cluster
```

### 5. Verify

```bash
just status    # Show cluster status
just watch     # Watch nodes come online
```

## Commands

All commands support the `cluster=<name>` parameter (default: homelab):

```bash
just list                          # List available clusters
just sync [cluster=NAME]           # Sync config from cluster.yaml
just init [cluster=NAME]           # Initialize Terraform
just apply [cluster=NAME]          # Create/update VMs
just sync-ips [cluster=NAME]       # Sync IPs to Talos config
just talgen [cluster=NAME]         # Generate Talos configs
just talos [cluster=NAME]          # Bootstrap cluster
just status [cluster=NAME]         # Show cluster status
just watch [cluster=NAME]          # Watch cluster nodes
just nuke [cluster=NAME] [--all]   # Destroy cluster
just workflow [cluster=NAME]       # Show complete workflow
just help                          # Show all commands
```

## Multi-Cluster Usage

### Creating a New Cluster

1. Copy the homelab cluster as a template:
```bash
cp -r clusters/homelab clusters/prod
```

2. Edit the new cluster configuration:
```bash
vim clusters/prod/cluster.yaml
```

3. Update cluster-specific values:
```yaml
metadata:
  name: prod
  environment: production

cluster:
  topology:
    controlPlane:
      count: 3  # HA setup for prod
    workers:
      count: 5  # More workers for prod

proxmox:
  vm:
    idBase: 900  # Different VM IDs than homelab
```

4. Deploy the new cluster:
```bash
just cluster=prod sync
just cluster=prod init
just cluster=prod apply
just cluster=prod sync-ips
just cluster=prod talgen
just cluster=prod talos
```

### Managing Multiple Clusters

```bash
# Deploy to different clusters
just cluster=homelab apply
just cluster=dev apply
just cluster=prod apply

# Check status of all clusters
just cluster=homelab status
just cluster=dev status
just cluster=prod status

# Sync all clusters at once
just sync-all
```

## Scaling a Cluster

Want to change from 1 to 3 control plane nodes?

1. Edit `clusters/homelab/cluster.yaml`:
```yaml
cluster:
  topology:
    controlPlane:
      count: 3  # Changed from 1
```

2. Apply the change:
```bash
just sync           # Regenerate Terraform configs
just apply          # Terraform creates 2 new VMs
just sync-ips       # Update Talos config with new IPs
just talgen         # Regenerate Talos configs
# Apply new configs to cluster...
```

## GitOps Integration (Future)

The `infrastructure/` directory contains Flux/Kustomize configurations for cluster addons.

When enabled in `cluster.yaml`:

```yaml
gitops:
  enabled: true
  flux:
    repository: https://github.com/yourusername/k8s-infrastructure
```

Flux will automatically install:
- cert-manager
- ingress-nginx
- Other infrastructure components

See [infrastructure/README.md](infrastructure/README.md) for details.

## How It Works

### Single Source of Truth Flow

```
cluster.yaml (edit this)
    │
    ├─→ sync-cluster.sh
    │   ├─→ Generates terraform.tfvars
    │   └─→ Generates talconfig.yaml template
    │
    ├─→ terraform apply (creates VMs)
    │
    ├─→ sync-ips.sh
    │   └─→ Updates talconfig.yaml with actual IPs
    │
    └─→ talhelper + talosctl
        └─→ Bootstraps Kubernetes cluster
```

### Key Benefits

1. **One config file to rule them all**: Change node counts in one place
2. **Multi-cluster ready**: Same structure for homelab, dev, staging, prod
3. **Infrastructure separation**: Each cluster has isolated state
4. **GitOps integration**: Ready for Flux when you are
5. **Reusable modules**: Terraform modules shared across clusters

## Requirements

- [OpenTofu](https://opentofu.org/) or Terraform
- [talhelper](https://github.com/budimanjojo/talhelper)
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [just](https://github.com/casey/just)
- [yq](https://github.com/mikefarah/yq)
- [jq](https://stedolan.github.io/jq/)

## Migrating from Old Structure

If you have an existing setup in the root `terraform/` directory:

1. Your current work is preserved in the `investigate-talhelper` branch
2. This new structure is on the `unified-cluster-config` branch
3. To migrate: Copy `terraform/secrets.tfvars` to `clusters/homelab/terraform/`

## License

See [LICENSE](LICENSE)
