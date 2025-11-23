# Infrastructure Components

This directory contains Flux/Kustomize configurations for cluster infrastructure components.

## Structure

```
infrastructure/
├── sources/              # Helm repositories and other sources
│   ├── jetstack.yaml
│   ├── ingress-nginx.yaml
│   └── kustomization.yaml
│
├── core/                 # Core cluster components (required)
│   ├── base/             # Base configurations
│   │   ├── cert-manager/
│   │   └── ingress-nginx/
│   └── overlays/         # Environment-specific customizations
│       ├── homelab/      # Homelab cluster (minimal resources)
│       ├── dev/          # Development cluster
│       └── prod/         # Production cluster (HA, more replicas)
│
└── optional/             # Optional components
    └── base/
        ├── external-dns/
        ├── sealed-secrets/
        └── ...
```

## Usage

### With Flux (GitOps)

Flux automatically applies these configurations when you bootstrap it to your cluster.

Configure in your cluster's flux bootstrap configuration:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-sources
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/sources
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-core
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/core/overlays/homelab
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure-sources
```

### Manual Application

You can also apply these configurations manually:

```bash
# Apply sources first
kubectl apply -k infrastructure/sources

# Then apply core components for your cluster
kubectl apply -k infrastructure/core/overlays/homelab
```

## Adding New Components

1. Create base configuration in `core/base/` or `optional/base/`
2. Add environment-specific overlays in `overlays/<cluster-name>/`
3. Reference in your cluster's flux configuration

## Environment Overlays

- **homelab**: Minimal resources, single replica, suitable for home labs
- **dev**: Low resources, good for development/testing
- **prod**: High availability, multiple replicas, production-ready
