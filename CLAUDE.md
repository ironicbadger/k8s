# Project Memory

## GitOps Workflow

- This repo uses **Flux** for GitOps, not raw kustomize
- Do NOT run `kustomize build` to verify changes - push and let Flux reconcile
- Force reconcile with: `flux reconcile kustomization <name> -n flux-system`

## Cluster Info

- **m720q**: Bare metal Talos Linux cluster with 3 nodes (m720q-1, m720q-2, m720q-3)
- **homelab**: Separate cluster

## Conventions

- `infrastructure/core/base/` - Cluster-agnostic base configs
- `infrastructure/core/overlays/<cluster>/` - Cluster-specific overrides
- Hardware-specific configs (disk paths, node names) belong in overlays, not base
