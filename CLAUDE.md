# Project Memory

## GitOps Workflow

- This repo uses **Flux** for GitOps, not raw kustomize
- Do NOT run `kustomize build` to verify changes - push and let Flux reconcile
- Force reconcile with: `flux reconcile kustomization <name> -n flux-system`

## Directory Structure

```
k8s/
├── clusters/                    # Per-cluster configurations
│   ├── m720q/                   # Bare metal cluster
│   │   ├── talos/               # Talos machine configs
│   │   └── flux-kustomizations/ # Flux Kustomization CRDs
│   └── homelab/                 # Proxmox VM cluster
│       ├── cluster.yaml         # Single source of truth for homelab
│       ├── talos/               # Generated Talos configs
│       ├── terraform/           # Generated Terraform code
│       └── flux-kustomizations/
├── infrastructure/              # Shared Kubernetes addons
│   ├── core/
│   │   ├── base/                # Cluster-agnostic base configs
│   │   └── overlays/            # Cluster-specific overrides
│   │       ├── m720q/
│   │       └── homelab/
│   └── sources/                 # HelmRepository definitions
├── apps/                        # User applications
│   ├── base/                    # Base app configs
│   └── overlays/                # Cluster-specific app configs
├── modules/                     # Reusable Terraform modules
├── scripts/                     # Automation scripts and just modules
├── justfile                     # Command runner
└── .sops.yaml                   # SOPS encryption rules
```

## Clusters

### m720q (Bare Metal)
- **Type**: 3x Lenovo m720q nodes (all control planes)
- **OS**: Talos Linux v1.11.5, Kubernetes v1.32.0
- **Endpoint**: https://10.42.0.101:6443
- **Node IPs**: 10.42.0.101-103
- **Config Source**: `clusters/m720q/talos/talconfig.yaml`
- **Features**: KubePrism (port 7445), Cilium CNI, no kube-proxy
- **Storage**: Rook Ceph across 3 NVMe drives

### homelab (Proxmox VMs)
- **Type**: Virtualized on Proxmox
- **Config Source**: `clusters/homelab/cluster.yaml` (single source of truth)
- **Topology**: 1 control plane + 1 worker
- **Provisioning**: `just px confgen && just px create && just px bootstrap`

## Flux Configuration

### Understanding Flux vs Kustomize
- `kustomization.yaml` (lowercase) = kustomize manifest (config.k8s.io)
- `Kustomization` CRD = Flux reconciliation resource (kustomize.toolkit.fluxcd.io)

### Flux Kustomization Hierarchy (m720q)
```
flux-system (root)
  └── clusters/m720q/
        ├── flux-kustomizations/
        │   ├── sources.yaml           → HelmRepositories
        │   ├── infrastructure-core.yaml → Cilium, cert-manager, Tailscale, Headlamp
        │   ├── api-proxy.yaml         → Tailscale API proxy (depends: infrastructure-core)
        │   ├── infrastructure.yaml    → Monitoring stack (depends: infrastructure-core)
        │   ├── rook-ceph-operator.yaml
        │   ├── rook-ceph-cluster.yaml
        │   └── smokeping.yaml         → depends on rook-ceph-cluster
```

### Key Flux Commands
```bash
flux reconcile kustomization <name> -n flux-system  # Force reconcile
flux get kustomizations -A                          # List all kustomizations
flux get helmreleases -A                            # List all HelmReleases
flux logs --follow                                  # Watch Flux logs
```

## Infrastructure Components

### Networking
- **Cilium**: CNI with L2 LoadBalancer (IP pool: 10.42.0.110-149)
- **Tailscale Operator**: Ingress via Tailscale, API proxy for HA access

### Storage
- **Rook Ceph**: Distributed storage (m720q only)
  - Storage class: `ceph-block`
  - Dashboard available via Headlamp

### Certificates
- **cert-manager**: Auto TLS certificates

### Monitoring (m720q only)
- **kube-prometheus-stack**: Grafana + Prometheus
- **Smokeping**: Network latency monitoring

### Management
- **Headlamp**: Kubernetes dashboard with OIDC (https://idp.ktz.ts.net)

## Overlay Pattern

Base configs in `infrastructure/core/base/` are extended by overlays in `infrastructure/core/overlays/<cluster>/`.

### Example: Adding cluster-specific config
```yaml
# infrastructure/core/overlays/m720q/core/headlamp/helmrelease-patch.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: headlamp
spec:
  values:
    config:
      oidc:
        callbackURL: https://m720q-headlamp.ktz.ts.net/oidc-callback
```

### Overlay kustomization.yaml pattern
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../base/headlamp        # Reference base
patches:
  - path: helmrelease-patch.yaml     # Apply cluster-specific patches
```

## Tailscale Tagging

All Tailscale resources (Ingresses, ProxyGroups, operator defaultTags) **must** have:
1. `tag:k8s` - generic tag for all Kubernetes-originated nodes
2. `tag:k8s-<cluster-name>` - cluster-specific tag (e.g., `tag:k8s-m720q`, `tag:k8s-homelab`)

**IMPORTANT**: Never remove existing tags like `tag:k8s-operator` or `tag:k8s-funnel` - these are required by Tailscale. Always ADD the required tags alongside existing ones.

### Ingress Example
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    tailscale.com/tags: "tag:k8s,tag:k8s-m720q"
spec:
  ingressClassName: tailscale
```

### ProxyGroup Example
```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
spec:
  tags:
    - "tag:k8s"
    - "tag:k8s-operator"
    - "tag:k8s-m720q"
```

## Secrets Management

### SOPS Encryption
Secrets are encrypted with SOPS using Age keys. Flux decrypts them automatically.

**Secret file patterns**:
- `*.sops.yaml` - SOPS-encrypted files
- `clusters/*/talos/talsecret.sops.yaml` - Talos cluster secrets
- `infrastructure/core/overlays/*/headlamp-oidc-secret.sops.yaml` - OIDC credentials
- `infrastructure/core/overlays/*/tailscale-secret.sops.yaml` - Tailscale OAuth

**Flux decryption config** (in Kustomization CRD):
```yaml
decryption:
  provider: sops
  secretRef:
    name: sops-age
```

## HelmRepositories

Defined in `infrastructure/sources/`:
- **cilium**: https://helm.cilium.io
- **jetstack**: https://charts.jetstack.io (cert-manager)
- **headlamp**: https://headlamp-k8s.github.io/helm-chart
- **tailscale**: https://pkgs.tailscale.com/helmcharts
- **prometheus-community**: Prometheus charts
- **rook**: https://charts.rook.io

## Just Commands

```bash
# Flux
just flux reconcile <name>          # Reconcile kustomization

# Bare metal (m720q)
export JUST_BM_CLUSTER=m720q
just bm confgen                     # Generate Talos configs
just bm apply m720q-1               # Apply to specific node
just bm apply-all                   # Apply to all nodes
just bm bootstrap                   # Bootstrap etcd

# Proxmox (homelab)
just px confgen                     # Generate Terraform + Talos from cluster.yaml
just px create                      # Create VMs
just px bootstrap                   # Bootstrap cluster

# Kubernetes
just k get pods -A                  # kubectl wrapper

# Tailscale
just ts devices                     # List Tailscale devices
```

## Conventions

- `infrastructure/core/base/` - Cluster-agnostic base configs
- `infrastructure/core/overlays/<cluster>/` - Cluster-specific overrides
- Hardware-specific configs (disk paths, node names) belong in overlays, not base
- All ingresses use Tailscale (ingressClassName: tailscale)
- Secrets are SOPS-encrypted with `.sops.yaml` suffix

## File Locations Quick Reference

| What | Where |
|------|-------|
| Flux Kustomizations | `clusters/<cluster>/flux-kustomizations/` |
| HelmRepositories | `infrastructure/sources/` |
| Base HelmReleases | `infrastructure/core/base/<app>/` |
| Cluster patches | `infrastructure/core/overlays/<cluster>/` |
| Encrypted secrets | `*.sops.yaml` files |
| Talos config | `clusters/<cluster>/talos/talconfig.yaml` |
| Homelab source of truth | `clusters/homelab/cluster.yaml` |
| Just modules | `scripts/just/` |

## Namespaces

- `flux-system` - Flux components
- `kube-system` - Cilium
- `cert-manager` - Certificate management
- `tailscale` - Tailscale operator
- `headlamp` - Dashboard
- `rook-ceph` - Storage (m720q)
- `monitoring` - Prometheus/Grafana (m720q)
- `smokeping` - Network monitoring (m720q)
