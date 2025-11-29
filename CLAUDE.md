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

## Tailscale Tagging

All Tailscale resources (Ingresses, ProxyGroups, operator defaultTags) **must** have:
1. `tag:k8s` - generic tag for all Kubernetes-originated nodes
2. `tag:k8s-<cluster-name>` - cluster-specific tag (e.g., `tag:k8s-m720q`, `tag:k8s-homelab`)

**IMPORTANT**: Never remove existing tags like `tag:k8s-operator` or `tag:k8s-funnel` - these are required by Tailscale. Always ADD the required tags alongside existing ones.

Example for Ingress annotation:
```yaml
annotations:
  tailscale.com/tags: "tag:k8s,tag:k8s-m720q"
```

Example for ProxyGroup or operator defaultTags (note: preserve tag:k8s-operator):
```yaml
tags:
  - "tag:k8s"
  - "tag:k8s-operator"
  - "tag:k8s-m720q"
```
