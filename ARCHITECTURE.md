# Architecture Overview

## Design Philosophy

This infrastructure uses a **single source of truth** approach where everything about a cluster is defined in one YAML file: `clusters/<name>/cluster.yaml`

## The Problem We Solved

### Before (investigate-talhelper branch):
- Terraform defines: 3 control planes, 3 workers (in `terraform.tfvars`)
- Talhelper defines: 3 control planes, 3 workers (in `talconfig.yaml`)
- **Problem**: Two sources of truth that can drift apart
- **Result**: Change node counts in Terraform → must manually update talconfig.yaml

### After (unified-cluster-config branch):
- `cluster.yaml` defines: 3 control planes, 3 workers
- Scripts generate both Terraform and Talos configs from this ONE file
- **Benefit**: Change node counts in ONE place
- **Result**: Everything stays in sync automatically

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    cluster.yaml                             │
│            (Single Source of Truth)                         │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├──→ sync-cluster.sh
                  │    ├──→ terraform.tfvars (generated)
                  │    └──→ talconfig.yaml template (generated)
                  │
                  ├──→ terraform apply
                  │    └──→ Creates VMs on Proxmox
                  │
                  ├──→ gen-talconfig.sh
                  │    └──→ Generates talconfig.yaml with IPs from Terraform
                  │
                  └──→ talhelper + talosctl
                       └──→ Bootstraps Kubernetes cluster
```

## Directory Structure Design

### Per-Cluster Isolation

Each cluster lives in its own directory with complete isolation:

```
clusters/
├── homelab/          # Homelab cluster
│   ├── cluster.yaml  # ← Source of truth
│   ├── terraform/    # Generated configs + state
│   └── talos/        # Generated configs + secrets
├── dev/              # Dev cluster
└── prod/             # Prod cluster
```

**Benefits**:
- Independent Terraform state (no conflicts)
- Separate secrets per cluster
- Easy to understand what belongs where
- Can delete entire cluster directory safely

### Shared Infrastructure

Reusable components live at the root:

```
modules/              # Terraform modules (reusable)
infrastructure/       # Kubernetes addons (Flux/Kustomize)
scripts/              # Automation scripts
```

**Benefits**:
- DRY (Don't Repeat Yourself)
- Fix once, fixes everywhere
- Consistent patterns across clusters

## Configuration Flow

### 1. Define Cluster

Edit `clusters/homelab/cluster.yaml`:

```yaml
metadata:
  name: homelab
  environment: dev

cluster:
  topology:
    controlPlane:
      count: 1        # ← Change this number
      resources:
        cores: 4
        memory: 8192
```

### 2. Generate Configs

```bash
just sync
```

This runs `scripts/sync-cluster.sh` which:
- Reads `cluster.yaml` using `yq`
- Generates `terraform/terraform.tfvars`
- Generates `talos/talconfig.yaml` template

### 3. Deploy Infrastructure

```bash
just init   # Initialize Terraform
just apply  # Create VMs
```

Terraform:
- Uses `modules/talos-proxmox` module
- Creates VMs on Proxmox
- Stores state in `clusters/homelab/terraform/`

### 4. Bootstrap Kubernetes

```bash
just talgen    # Generate Talos configs (syncs IPs from Terraform)
just bootstrap # Bootstrap cluster
```

## Multi-Cluster Support

### Same Structure, Different Values

**Homelab** (`clusters/homelab/cluster.yaml`):
```yaml
metadata:
  name: homelab
  environment: dev

cluster:
  topology:
    controlPlane:
      count: 1      # Minimal for homelab
    workers:
      count: 1

proxmox:
  vm:
    idBase: 800     # VMs 800-809
```

**Production** (`clusters/prod/cluster.yaml`):
```yaml
metadata:
  name: prod
  environment: production

cluster:
  topology:
    controlPlane:
      count: 3      # HA for production
    workers:
      count: 5      # More capacity

proxmox:
  vm:
    idBase: 900     # VMs 900-909 (no conflicts)
```

### Independent Operations

```bash
# Deploy homelab
just cluster=homelab apply

# Deploy prod (doesn't affect homelab)
just cluster=prod apply

# Destroy homelab (doesn't affect prod)
just cluster=homelab nuke
```

## GitOps Integration

### Infrastructure as Code Layers

1. **Infrastructure Layer** (This Repo):
   - VMs (Terraform)
   - Kubernetes cluster (Talos)
   - Cluster addons (Flux/Kustomize)

2. **Application Layer** (Separate Repo):
   - Your actual workloads
   - Deployed via Flux

### Infrastructure Components

Located in `infrastructure/`:

```
infrastructure/
├── sources/          # Helm repositories
├── core/             # Required components
│   ├── base/         # Base configs
│   │   ├── cert-manager/
│   │   └── ingress-nginx/
│   └── overlays/     # Per-cluster customization
│       ├── homelab/  # Minimal resources
│       ├── dev/      # Dev settings
│       └── prod/     # HA, more replicas
└── optional/         # Optional components
```

### Environment Customization

**Base** (`infrastructure/core/base/ingress-nginx/`):
```yaml
# Default configuration
controller:
  kind: DaemonSet
```

**Homelab Overlay** (`infrastructure/core/overlays/homelab/`):
```yaml
# Minimal for homelab
patches:
  - target:
      name: ingress-nginx
    patch: |-
      - op: add
        path: /spec/values/controller/replicaCount
        value: 1
```

**Prod Overlay** (`infrastructure/core/overlays/prod/`):
```yaml
# HA for production
patches:
  - target:
      name: ingress-nginx
    patch: |-
      - op: add
        path: /spec/values/controller/replicaCount
        value: 3
```

## Scaling Scenarios

### Scenario 1: Scale from 1 to 3 Control Planes

1. Edit `clusters/homelab/cluster.yaml`:
```yaml
controlPlane:
  count: 3  # Changed from 1
```

2. Apply:
```bash
just confgen   # Regenerates terraform configs
just create    # Terraform creates 2 new VMs
just talgen    # Generates talconfig with 3 nodes
```

### Scenario 2: Add a Dev Cluster

1. Copy homelab:
```bash
cp -r clusters/homelab clusters/dev
```

2. Edit `clusters/dev/cluster.yaml`:
```yaml
metadata:
  name: dev
  environment: development

proxmox:
  vm:
    idBase: 850  # Different VM IDs
```

3. Deploy:
```bash
just cluster=dev sync
just cluster=dev init
just cluster=dev apply
```

### Scenario 3: Different Resources per Environment

**Homelab** (minimal):
```yaml
controlPlane:
  resources:
    cores: 2
    memory: 4096
    disk: 20
```

**Prod** (more power):
```yaml
controlPlane:
  resources:
    cores: 8
    memory: 32768
    disk: 100
```

## Comparison: Old vs New

### Old Structure (investigate-talhelper)

```
terraform/
  terraform.tfvars    # Node counts defined here
  main.tf

talconfig.yaml        # Node counts ALSO defined here
talsecret.yaml
```

**Problems**:
- Two sources of truth
- Manual synchronization required
- Easy to make mistakes
- Hard to manage multiple clusters

### New Structure (unified-cluster-config)

```
clusters/
  homelab/
    cluster.yaml      # ← ONLY place to define node counts
    terraform/        # Generated from cluster.yaml
    talos/            # Generated from cluster.yaml
```

**Benefits**:
- Single source of truth
- Automatic synchronization
- Multi-cluster ready
- Scalable architecture

## Future Enhancements

### Possible Additions:

1. **Terraform State in S3/Garage**: ✅ Already configured
2. **Flux Auto-Bootstrap**: Enable in cluster.yaml → automatic GitOps
3. **Multiple Node Pools**: Different worker types per cluster
4. **Cloud Provider Support**: Extend modules for AWS, Azure, etc.
5. **Automated Testing**: Validate cluster.yaml schema
6. **Prometheus/Grafana**: Add to infrastructure/optional/

## Key Takeaways

1. **cluster.yaml is the source of truth** - Edit this, everything else is generated
2. **Each cluster is independent** - Isolated state, configs, secrets
3. **Modules are reusable** - Same code for all clusters
4. **GitOps ready** - Infrastructure components prepared for Flux
5. **Scales horizontally** - Add clusters by copying directory structure
6. **Scales vertically** - Change node counts in one place
