# Bare Metal Cluster Bootstrap Guide

Step-by-step guide for bootstrapping the m720q bare metal Talos cluster from freshly wiped disks.

## Prerequisites

- Talos ISO available (boot via PiKVM)
- DHCP configured to assign expected IPs (10.42.0.101-103 for m720q)
- SOPS age key available (`$SOPS_AGE_KEY_FILE`)
- Tools installed: `talosctl`, `talhelper`, `kubectl`, `helm`, `flux`, `just`, `yq`, `sops`

## Bootstrap Steps

### 1. Set Cluster Context

```bash
export JUST_BM_CLUSTER=m720q
```

### 2. Generate Configs

```bash
just bm confgen
```

This generates:
- `talsecret.sops.yaml` (encrypted cluster secrets, if not already present)
- Per-node Talos configs in `clusterconfig/`

### 3. Boot Nodes from Talos ISO

Via PiKVM:
1. Mount Talos ISO
2. Boot each node
3. Wait for nodes to get DHCP addresses

Verify nodes are reachable:
```bash
ping 10.42.0.101
ping 10.42.0.102
ping 10.42.0.103
```

### 4. Apply Configs

> **Important**: Use `--insecure` for fresh nodes that don't have certificates yet.

```bash
just bm apply-all --insecure
```

Or apply to individual nodes:
```bash
just bm apply m720q-1 --insecure
just bm apply m720q-2 --insecure
just bm apply m720q-3 --insecure
```

Nodes will reboot and apply their configuration.

### 5. Bootstrap etcd

> **Important**: Only run this on the first control plane. Other nodes join automatically.

```bash
just bm bootstrap
```

Wait ~60 seconds for the Kubernetes API server to start.

### 6. Fetch Kubeconfig

```bash
just bm kubeconfig
```

Verify nodes are visible (they will show `NotReady` - this is expected):
```bash
KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig kubectl get nodes
```

### 7. Install Cilium CNI

> **Important**: Nodes won't become `Ready` without a CNI. Flux needs `Ready` nodes to deploy, creating a chicken-and-egg problem. Install Cilium manually first.

```bash
just bm cilium
```

Wait for nodes to become `Ready`:
```bash
KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig kubectl get nodes -w
```

### 8. Approve Kubelet CSRs

You may see TLS errors in dmesg:
```
tls: internal error
```

This indicates pending Certificate Signing Requests. Check and approve them:

```bash
KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig kubectl get csr
```

Approve pending CSRs:
```bash
KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig kubectl certificate approve <csr-name-1> <csr-name-2> ...
```

> **Note**: After Flux deploys `kubelet-csr-approver`, future CSRs will be auto-approved.

### 9. Bootstrap Flux

```bash
export KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig
just flux bootstrap
```

Flux will:
- Install itself
- Deploy all infrastructure components
- Take over Cilium management (via HelmRelease)

### 10. Verify

```bash
just flux status
just k watch
```

## Command Reference

| Command | Description |
|---------|-------------|
| `just bm confgen` | Generate Talos configs from talconfig.yaml |
| `just bm apply <node> --insecure` | Apply config to fresh node |
| `just bm apply-all --insecure` | Apply to all fresh nodes |
| `just bm bootstrap` | Bootstrap etcd (first control plane only) |
| `just bm kubeconfig` | Fetch kubeconfig from cluster |
| `just bm cilium` | Install Cilium CNI (pre-Flux) |
| `just flux bootstrap` | Bootstrap Flux GitOps |

## Gotchas

| Issue | Solution |
|-------|----------|
| `--insecure` flag forgotten | Required for fresh nodes without certificates |
| etcd bootstrap on wrong node | Only run on first control plane; others join automatically |
| Kubeconfig not found | Run `just bm kubeconfig` after bootstrap |
| `export KUBECONFIG` not working | Use inline: `KUBECONFIG=path kubectl ...` |
| Nodes stuck in `NotReady` | Install Cilium CNI first |
| TLS errors in dmesg | Approve pending CSRs |
| Flux won't deploy | Nodes must be `Ready` first (install Cilium) |

## Troubleshooting

### Check Talos health
```bash
TALOSCONFIG=clusters/m720q/talos/clusterconfig/talosconfig talosctl -n 10.42.0.101 health
```

### Watch Talos logs
```bash
TALOSCONFIG=clusters/m720q/talos/clusterconfig/talosconfig talosctl -n 10.42.0.101 dmesg -f
```

### Check etcd status
```bash
TALOSCONFIG=clusters/m720q/talos/clusterconfig/talosconfig talosctl -n 10.42.0.101 etcd members
```

### Check Cilium status
```bash
KUBECONFIG=clusters/m720q/talos/clusterconfig/kubeconfig kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
```
