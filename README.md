# Kubernetes Multi-Cluster Infrastructure

Unified infrastructure-as-code for managing multiple Kubernetes clusters on Proxmox using Talos Linux.

## Overview

**Single Source of Truth**: `clusters/<name>/cluster.yaml`

Define node counts, resources, Proxmox settings, and Talos config in one YAML file. Scripts auto-generate Terraform and Talos configurations. All secrets encrypted with SOPS.

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
│   ├── confgen.sh               # Generate configs from cluster.yaml
│   ├── gen-talconfig.sh         # Generate talconfig.yaml from cluster.yaml + Terraform IPs
│   └── talos-apply.sh           # Bootstrap Talos cluster
│
└── justfile                     # Command runner (just <command>)
```

## Quick Start

```bash
# 1. Edit cluster configuration
vim clusters/homelab/cluster.yaml

# 2. Ensure secrets.sops.yaml exists in repo root (encrypted with SOPS)

# 3. Deploy everything
just fromscratch

# Or step by step:
just confgen      # Generate configs from cluster.yaml
just init         # Initialize Terraform
just create       # Deploy VMs
just talgen       # Generate Talos configs (syncs IPs)
just bootstrap    # Bootstrap Kubernetes
```

## Commands

**Core Workflow:**
- `just fromscratch` - Build cluster from scratch (all steps)
- `just confgen` - Generate Terraform/Talos configs from cluster.yaml
- `just create` - Deploy VMs with Terraform
- `just talgen` - Generate Talos machine configs (syncs IPs)
- `just bootstrap` - Bootstrap Kubernetes cluster

**Management:**
- `just status` - Show cluster status
- `just watch` - Watch nodes
- `just plan` - Show Terraform plan
- `just nuke [all=true]` - Destroy cluster (all=true deletes secrets)

**Multi-cluster:**
All commands support `cluster=<name>` parameter (default: homelab):
```bash
just cluster=prod fromscratch
just cluster=dev status
```

Run `just help` for complete list.

## Multi-Cluster

Create a new cluster by copying the homelab template:
```bash
cp -r clusters/homelab clusters/prod
vim clusters/prod/cluster.yaml  # Update name, VM IDs, node counts
just cluster=prod fromscratch
```

## Secrets Management

All secrets encrypted with SOPS (GPG key: `6636CBF9CE1DE1A8`):
- `secrets.sops.yaml` - Proxmox API tokens, S3 credentials
- `clusters/*/talos/talsecret.sops.yaml` - Talos cluster secrets

Scripts automatically decrypt during operations.

## Requirements

- [OpenTofu](https://opentofu.org/), [talhelper](https://github.com/budimanjojo/talhelper), [talosctl](https://www.talos.dev/), [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [just](https://github.com/casey/just), [jq](https://stedolan.github.io/jq/), [yq](https://github.com/mikefarah/yq), [sops](https://github.com/mozilla/sops)

## Details

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed documentation on the unified cluster configuration system.
