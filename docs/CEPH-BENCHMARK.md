# Ceph Storage Benchmark

**Cluster:** m720q (3-node Talos Linux)
**Date:** 2025-11-29

## Cluster Configuration

| Component | Configuration |
|-----------|---------------|
| Ceph Version | Reef v18.2.4 |
| Nodes | 3 (m720q-1, m720q-2, m720q-3) |
| OSDs | 3x Samsung NVMe 512GB (970 PRO) |
| Total Raw | 1.4 TiB |
| Replication | 3x (host failure domain) |
| Usable Capacity | ~450 GiB |
| MONs | 3 |
| MGRs | 2 |

### Storage Class

- **Name:** `ceph-block` (default)
- **Pool:** `replicapool` (3x replicated)
- **Filesystem:** ext4
- **Volume Expansion:** Enabled

## Benchmark Results

**Test Parameters:** 1GB test file, direct I/O, libaio engine

| Test | Bandwidth | IOPS | Avg Latency | P99 Latency |
|------|-----------|------|-------------|-------------|
| Sequential Read (1M, qd16) | **784 MB/s** | 785 | 20 ms | 60 ms |
| Sequential Write (1M, qd16) | **380 MB/s** | 380 | 42 ms | 74 ms |
| Random Read 4K (qd64) | 126 MB/s | **32,308** | 2 ms | 6 ms |
| Random R/W 4K 70/30 (qd32) | R: 16 MB/s, W: 7 MB/s | R: 4,066, W: 1,745 | R: 2.6 ms, W: 12.2 ms | R: 18 ms, W: 31 ms |

## Analysis

**Strengths:**
- Excellent random read IOPS (~32K) - suitable for database read workloads
- Strong sequential read throughput (~784 MB/s)
- Low read latencies (2ms average for 4K random)

**Considerations:**
- Write latency higher (~12ms for random writes) due to 3x replication
- Sequential write at 380 MB/s is expected for replicated writes across network

## Running Benchmarks

Deploy a temporary fio pod:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fio-bench
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: fio-bench
spec:
  containers:
  - name: fio
    image: ljishen/fio
    command: ["tail", "-f", "/dev/null"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: fio-bench
EOF
```

Run tests:

```bash
# Random 4K read (IOPS)
kubectl exec fio-bench -- fio --name=randread --ioengine=libaio --direct=1 \
  --bs=4k --iodepth=64 --size=1G --rw=randread --directory=/data

# Sequential write (throughput)
kubectl exec fio-bench -- fio --name=seqwrite --ioengine=libaio --direct=1 \
  --bs=1m --iodepth=16 --size=1G --rw=write --directory=/data

# Mixed workload (database-like)
kubectl exec fio-bench -- fio --name=randrw --ioengine=libaio --direct=1 \
  --bs=4k --iodepth=32 --size=1G --rw=randrw --rwmixread=70 --directory=/data
```

Cleanup:

```bash
kubectl delete pod fio-bench && kubectl delete pvc fio-bench
```
