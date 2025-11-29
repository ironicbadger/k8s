#!/usr/bin/env bash
# Ceph storage benchmark using fio
# Deploys a temporary pod, runs tests, and cleans up
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-}"
if [[ -z "$KUBECONFIG" ]]; then
    echo "Error: KUBECONFIG not set"
    exit 1
fi

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    kubectl delete pod fio-bench --ignore-not-found
    kubectl delete pvc fio-bench --ignore-not-found
}
trap cleanup EXIT

echo "=== Deploying fio benchmark pod ==="
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

echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/fio-bench --timeout=120s

echo ""
echo "=== Sequential Read (1M, qd16) ==="
kubectl exec fio-bench -- fio --name=seqread --ioengine=libaio --direct=1 \
  --bs=1m --iodepth=16 --size=1G --rw=read --directory=/data --output-format=terse | \
  awk -F';' '{printf "Bandwidth: %.0f MB/s, IOPS: %s\n", $7/1024, $8}'

echo ""
echo "=== Sequential Write (1M, qd16) ==="
kubectl exec fio-bench -- fio --name=seqwrite --ioengine=libaio --direct=1 \
  --bs=1m --iodepth=16 --size=1G --rw=write --directory=/data --output-format=terse | \
  awk -F';' '{printf "Bandwidth: %.0f MB/s, IOPS: %s\n", $48/1024, $49}'

echo ""
echo "=== Random Read 4K (qd64) ==="
kubectl exec fio-bench -- fio --name=randread --ioengine=libaio --direct=1 \
  --bs=4k --iodepth=64 --size=1G --rw=randread --directory=/data --output-format=terse | \
  awk -F';' '{printf "Bandwidth: %.0f MB/s, IOPS: %s\n", $7/1024, $8}'

echo ""
echo "=== Mixed Random R/W 4K 70/30 (qd32) ==="
kubectl exec fio-bench -- fio --name=randrw --ioengine=libaio --direct=1 \
  --bs=4k --iodepth=32 --size=1G --rw=randrw --rwmixread=70 --directory=/data --output-format=terse | \
  awk -F';' '{printf "Read:  %.0f MB/s, %s IOPS\nWrite: %.0f MB/s, %s IOPS\n", $7/1024, $8, $48/1024, $49}'

echo ""
echo "=== Benchmark Complete ==="
