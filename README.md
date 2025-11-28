# Kubernetes Multi-Cluster Infrastructure

Infrastructure-as-code for managing multiple Kubernetes clusters using Talos Linux on both Proxmox VMs and bare metal.

## Overview

This repository supports two deployment types:

| Type | Source of Truth | Use Case |
|------|-----------------|----------|
| **Proxmox** | `clusters/<name>/cluster.yaml` | Virtualized clusters on Proxmox |
| **Bare Metal** | `clusters/<name>/talos/talconfig.yaml` | Physical hardware (e.g., M720q nodes) |

## Directory Structure

```
.
├── clusters/                    # Per-cluster configurations
│   ├── homelab/                 # Proxmox cluster
│   │   ├── cluster.yaml         # ← Source of truth (Proxmox)
│   │   ├── terraform/           # Generated Terraform configs
│   │   └── talos/               # Generated Talos configs
│   └── m720q/                   # Bare metal cluster
│       └── talos/
│           └── talconfig.yaml   # ← Source of truth (bare metal)
│
├── modules/                     # Reusable Terraform modules
│   └── talos-proxmox/           # Proxmox VM module for Talos
│
├── infrastructure/              # Shared Kubernetes addons (Flux/Kustomize)
│   ├── sources/                 # Helm repos
│   └── core/                    # Required components
│       ├── base/                # Shared components
│       └── overlays/            # Cluster-specific overrides
│
├── scripts/                     # Automation scripts
│   └── just/                    # Just modules
│
└── justfile                     # Command runner
```

## Quick Start

### Proxmox Clusters

```bash
# Deploy a new Proxmox cluster
just px fromscratch

# Or step by step:
just px confgen      # Generate configs from cluster.yaml
just px init         # Initialize Terraform
just px create       # Deploy VMs
just px talgen       # Generate Talos configs (syncs IPs)
just px bootstrap    # Bootstrap Kubernetes
```

### Bare Metal Clusters

```bash
# Set cluster context
export JUST_BM_CLUSTER=m720q

# Generate configs and apply
just bm confgen              # Generate Talos configs
just bm apply m720q-1        # Apply to single node
just bm bootstrap            # Bootstrap etcd
just bm kubeconfig           # Fetch kubeconfig
```

## Commands

Run `just help` for a complete overview.

### Modules

| Module | Alias | Description |
|--------|-------|-------------|
| `just proxmox <cmd>` | `just px` | Proxmox VM provisioning |
| `just baremetal <cmd>` | `just bm` | Bare metal cluster management |
| `just talos <cmd>` | - | Talos (talosctl) operations |
| `just kubectl <cmd>` | `just k` | Kubernetes (kubectl) operations |
| `just flux <cmd>` | - | GitOps/Flux operations |
| `just tailscale <cmd>` | `just ts` | Tailscale device management |

### Proxmox Commands (`just px`)

```bash
just px confgen       # Generate configs from cluster.yaml
just px create        # Create/update VMs with Terraform
just px talgen        # Generate Talos configs
just px bootstrap     # Bootstrap Kubernetes cluster
just px fromscratch   # Full build (all above steps)
just px statesync     # Sync state on new machine
just px nuke          # Destroy cluster
```

### Bare Metal Commands (`just bm`)

Requires `JUST_BM_CLUSTER` environment variable:

```bash
export JUST_BM_CLUSTER=m720q

just bm confgen           # Generate Talos configs
just bm apply <node>      # Apply config to node
just bm apply-all         # Apply to all nodes
just bm bootstrap         # Bootstrap etcd
just bm kubeconfig        # Fetch kubeconfig
just bm upgrade <node> <version>  # Upgrade Talos
```

### Shared Commands

```bash
# Talos operations (uses $cluster variable)
just talos dashboard <node>   # Open Talos dashboard
just talos health             # Check cluster health
just talos nodes              # List nodes from talconfig

# Kubectl operations (uses $cluster variable)
just k status                 # Recent pods (newest 15)
just k nodes                  # Show nodes
just k watch                  # Watch nodes/pods
just k pods                   # All pods

# Flux operations
just flux bootstrap           # Bootstrap Flux
just flux status              # Show Flux status
```

### Multi-cluster

Proxmox clusters support the `cluster` variable:
```bash
cluster=prod just px status
cluster=dev just k nodes
```

Bare metal uses `JUST_BM_CLUSTER`:
```bash
JUST_BM_CLUSTER=m720q just bm confgen
```

## New Machine Setup

### Proxmox Clusters

```bash
# 1. Import GPG key (see Secrets section)
# 2. Sync local state from remote
just px statesync
```

### Bare Metal Clusters

```bash
# 1. Import GPG key
# 2. Generate configs (talconfig.yaml is already in git)
export JUST_BM_CLUSTER=m720q
just bm confgen
```

## Secrets Management

All secrets encrypted with [SOPS](https://github.com/mozilla/sops) using GPG.

**Encrypted files:**
- `secrets.sops.yaml` - Proxmox API tokens, S3 credentials
- `clusters/*/talos/talsecret.sops.yaml` - Talos cluster secrets

### Setting up GPG

```bash
# Import key on new system
gpg --import key.asc
gpg --edit-key <KEY_ID>
gpg> trust → 5 (ultimate) → quit

# Test decryption
sops -d secrets.sops.yaml
```

## Requirements

- [OpenTofu](https://opentofu.org/), [talhelper](https://github.com/budimanjojo/talhelper), [talosctl](https://www.talos.dev/), [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [just](https://github.com/casey/just), [jq](https://stedolan.github.io/jq/), [yq](https://github.com/mikefarah/yq), [sops](https://github.com/mozilla/sops)

## Details

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed documentation.
