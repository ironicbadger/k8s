# Headlamp OIDC Authentication

Headlamp is configured with OIDC authentication using Tailscale's built-in Identity Provider (IDP).

## Overview

Users authenticate via Tailscale IDP (`idp.ktz.ts.net`) which is exposed via Tailscale Funnel. After authentication, the Kubernetes API server validates the OIDC token and maps the user's email to RBAC permissions.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Browser   │────▶│     Headlamp     │────▶│  K8s API Server │
└─────────────┘     └──────────────────┘     └─────────────────┘
       │                    │                        │
       │                    │                        │
       ▼                    ▼                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale IDP                            │
│                  (idp.ktz.ts.net)                           │
│                                                             │
│  1. User clicks "Sign in" in Headlamp                       │
│  2. Redirects to Tailscale IDP for authentication           │
│  3. IDP returns OIDC token with user claims                 │
│  4. Headlamp passes token to K8s API                        │
│  5. API server validates token (configured via Talos)       │
│  6. RBAC determines user permissions based on email         │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Components

### 1. Kubernetes API Server OIDC (Talos)

The API server must be configured to accept tokens from the Tailscale IDP. This is done in `clusters/m720q/talos/talconfig.yaml`:

```yaml
controlPlane:
  patches:
    - |-
      cluster:
        apiServer:
          extraArgs:
            oidc-issuer-url: https://idp.ktz.ts.net
            oidc-client-id: <client-id-from-tailscale>
            oidc-username-claim: email
            oidc-groups-claim: tags
```

After modifying, regenerate and apply configs:
```bash
export JUST_BM_CLUSTER=m720q
just bm confgen
just bm apply-all
# Reboot nodes for API server to pick up changes
talosctl -n 10.42.0.101 reboot
talosctl -n 10.42.0.102 reboot
talosctl -n 10.42.0.103 reboot
```

### 2. Headlamp HelmRelease

Base config in `infrastructure/core/base/headlamp/helmrelease.yaml`:
- OIDC issuer URL
- OIDC scopes
- External secret reference

Overlay config in `helmrelease-patch.yaml`:
- Callback URL specific to this cluster

### 3. OIDC Secret (SOPS Encrypted)

`headlamp-oidc-secret.sops.yaml` contains:
- `OIDC_CLIENT_ID` - From Tailscale admin console
- `OIDC_CLIENT_SECRET` - From Tailscale admin console
- `OIDC_ISSUER_URL` - https://idp.ktz.ts.net
- `OIDC_SCOPES` - openid profile email
- `OIDC_CALLBACK_URL` - https://m720q-headlamp.ktz.ts.net/oidc-callback

To create/update the secret:
```bash
sops infrastructure/core/overlays/m720q/core/headlamp/headlamp-oidc-secret.sops.yaml
```

### 4. RBAC ClusterRoleBinding

`oidc-rbac.yaml` grants permissions to authenticated users:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: user@example.com  # Email from OIDC token
```

## Tailscale IDP Claims

The Tailscale IDP provides these claims in the OIDC token:

| Claim | Description | Example |
|-------|-------------|---------|
| `email` | User's email (used as username) | `user@example.com` |
| `username` | Tailscale username | `user` |
| `user` | User identifier | `user@example.com` |
| `tags` | Tailscale ACL tags | `["tag:admin"]` |
| `tailnet` | Tailnet name | `example.com` |
| `node` | Node information | Node details |
| `uid` | User ID | Unique identifier |

**Note**: Tailscale IDP does not provide a `groups` claim. Use `tags` for group-based RBAC if needed.

## Adding New Users

1. Ensure the user is part of your Tailnet
2. Add a ClusterRoleBinding for their email in `oidc-rbac.yaml`:

```yaml
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: existinguser@example.com
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: newuser@example.com  # Add new user
```

3. Commit and push - Flux will apply the changes

For more granular permissions, create additional RoleBindings or ClusterRoleBindings with different ClusterRoles.

## Troubleshooting

### "You don't have permissions to view this resource"

The user authenticated successfully but lacks RBAC permissions. Add their email to `oidc-rbac.yaml`.

### Login redirects back to sign-in page

1. **Check API server OIDC config**:
   ```bash
   kubectl get pod kube-apiserver-m720q-1 -n kube-system -o yaml | grep oidc
   ```
   Should show `--oidc-issuer-url`, `--oidc-client-id`, etc.

2. **Verify IDP is reachable from cluster**:
   ```bash
   kubectl run oidc-test --rm -it --restart=Never --image=curlimages/curl -- \
     curl -s https://idp.ktz.ts.net/.well-known/openid-configuration
   ```

3. **Check Headlamp logs**:
   ```bash
   kubectl logs -n headlamp -l app.kubernetes.io/name=headlamp
   ```

### "failed to append ca cert to pool" error

This is benign - Headlamp tries to load a custom CA file that doesn't exist. The Let's Encrypt certificates from Tailscale Funnel are trusted by default.

### Token validation fails

Ensure the `oidc-client-id` in both Talos config and Headlamp secret match exactly.

## Files in This Directory

| File | Purpose |
|------|---------|
| `kustomization.yaml` | Kustomize config referencing all resources |
| `helmrelease-patch.yaml` | Cluster-specific Helm values (callback URL) |
| `headlamp-oidc-secret.sops.yaml` | SOPS-encrypted OIDC credentials |
| `ingress.yaml` | Tailscale Ingress for Headlamp |
| `oidc-rbac.yaml` | RBAC bindings for OIDC users |
