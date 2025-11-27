# M720q Cluster - Next Steps

## ~~1. Rook/Ceph Storage~~ ✅ DEPLOYED

**Deployed: 2025-11-27**

### Disk Layout (IMPORTANT)

Device paths (`/dev/nvme0n1`, `/dev/nvme1n1`) are **not consistent** across nodes due to PCIe enumeration order. Use stable identifiers:

| Node | Boot Disk | Boot Model | Ceph Disk | Ceph Model |
|------|-----------|------------|-----------|------------|
| m720q-1 | nvme1n1 | Phison ESMP512GKB4C3-E13TS | nvme0n1 | Samsung MZVKW512HMJP |
| m720q-2 | nvme0n1 | TS512GMTE300S (Transcend) | nvme1n1 | Samsung SSD 970 PRO |
| m720q-3 | nvme0n1 | TS512GMTE300S (Transcend) | nvme1n1 | Samsung SSD 970 PRO |

### Talos installDiskSelector

Use `installDiskSelector` with `model` instead of `installDisk` path in `talconfig.yaml`:

```yaml
installDiskSelector:
  model: "TS512GMTE300S"    # Match by model name
  # wwid: "eui.xxx"         # Or use WWID for uniqueness
```

Get disk info: `talosctl get disks -n <IP>`

### Ceph Per-Node Device Config

Because device paths differ, `ceph-cluster.yaml` uses per-node device config:

```yaml
storage:
  useAllNodes: false
  useAllDevices: false
  nodes:
    - name: m720q-1
      devices:
        - name: nvme0n1  # Samsung
    - name: m720q-2
      devices:
        - name: nvme1n1  # Samsung
    - name: m720q-3
      devices:
        - name: nvme1n1  # Samsung
```

### Ceph Maintenance

Deploy toolbox for ceph CLI access:
```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
```

Remove a failed OSD:
```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd purge <ID> --yes-i-really-mean-it
kubectl -n rook-ceph delete deploy rook-ceph-osd-<ID>
```

---

## ~~2. Test LoadBalancer (L2 Announcements)~~ ✅ PASSED

**Tested: 2025-11-26**

### Results
- ✅ Service assigned IP `10.42.0.110` from `lan-pool`
- ✅ IP reachable via `curl http://10.42.0.110` - nginx responded
- ✅ Cilium L2 announcements working on `enp*` interfaces

### Test Commands Used
```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx  # Got 10.42.0.110
curl http://10.42.0.110  # Success - nginx welcome page
kubectl delete svc nginx && kubectl delete deployment nginx
```

---

## Remaining

1. **Rook/Ceph** - Deploy when persistent storage is needed
