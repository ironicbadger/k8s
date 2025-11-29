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

TODO: Setup PXE booting?

Via PiKVM:
1. Mount Talos ISO
2. Boot each node
3. Wait for nodes to get DHCP addresses

Verify Talos API is reachable on all nodes:
```bash
talosctl -n 10.42.0.101,10.42.0.102,10.42.0.103 version --insecure
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

### 5. Set Talos Config

```bash
export TALOSCONFIG=$(pwd)/clusters/m720q/talos/clusterconfig/talosconfig
```

### 6. Wipe Non-System Disks

> **Important**: If nodes have additional disks (e.g., for Ceph storage), wipe them before use. The `talosctl reset --wipe-mode all` only wipes the system disk, not additional disks.

Wait for nodes to finish booting after config apply, then verify which disks are present:
```bash
talosctl -n 10.42.0.101 get disks
```

Wipe any non-system disks (e.g., NVMe drives for Ceph):
```bash
# Wipe on all nodes (adjust device names as needed)
talosctl -n 10.42.0.101 wipe disk /dev/nvme1n1
talosctl -n 10.42.0.102 wipe disk /dev/nvme1n1
talosctl -n 10.42.0.103 wipe disk /dev/nvme1n1
```

> **Note**: The `wipe disk` command only works on running nodes, not in maintenance mode. It will refuse to wipe disks that are in use as system volumes.

### 7. Bootstrap etcd

> **Important**: Only run this on the first control plane. Other nodes join automatically.

First, verify Talos is ready for bootstrap:
```bash
talosctl -n 10.42.0.101 dmesg | grep -i bootstrap
```

You're ready when you see:
```
user: warning: [...]: [talos] etcd is waiting to join the cluster, if this is the first node please run `talosctl bootstrap`
```

Then run:
```bash
talosctl -n 10.42.0.101 bootstrap
```

Verify etcd is running:
```bash
talosctl -n 10.42.0.101 service
```

You should see `etcd` with `STATE: Running` and `HEALTH: OK`.

> **Tip**: `just bm bootstrap` does the same thing but auto-selects the first control plane IP.

### 8. Fetch Kubeconfig

```bash
talosctl -n 10.42.0.101 kubeconfig clusters/m720q/talos/clusterconfig/kubeconfig
export KUBECONFIG=$(pwd)/clusters/m720q/talos/clusterconfig/kubeconfig
```

Verify nodes are visible (they will show `NotReady` - this is expected):
```bash
kubectl get nodes
```

> **Tip**: `just bm kubeconfig` does the same thing.

### 9. Install Cilium CNI

> **Important**: Nodes won't become `Ready` without a CNI. Flux needs `Ready` nodes to deploy, creating a chicken-and-egg problem. Install Cilium manually first.

```bash
just bm cilium
```

Wait for nodes to become `Ready`:
```bash
kubectl get nodes -w
```

### 10. Approve Kubelet CSRs

You may see TLS errors in dmesg:
```
tls: internal error
```

This indicates pending Certificate Signing Requests. Approve all pending CSRs:

```bash
kubectl get csr --no-headers | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```

> **Note**: After Flux deploys `kubelet-csr-approver`, future CSRs will be auto-approved.

### 11. Bootstrap Flux

```bash
just flux bootstrap
```

Flux will:
- Install itself
- Deploy all infrastructure components
- Take over Cilium management (via HelmRelease)

### 12. Verify

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
| GitHub SSH timeouts in Flux | TODO: Use `ssh.github.com:443` instead of `github.com:22`. Requires adding `[ssh.github.com]:443` to known_hosts in flux-system secret and enabling SOPS decryption on flux-system Kustomization. |
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
talosctl -n 10.42.0.101 health
```

### Watch Talos logs
```bash
talosctl -n 10.42.0.101 dmesg -f
```

### Check etcd status
```bash
talosctl -n 10.42.0.101 etcd members
```

### Check Cilium status
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
```
