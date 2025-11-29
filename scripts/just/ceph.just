# Ceph monitoring commands
# Usage: just ceph <command>
# For bare metal: export JUST_BM_CLUSTER=m720q

set shell := ["bash", "-euo", "pipefail", "-c"]

_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# Show cluster status (health, capacity)
[no-cd]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG

    kubectl -n rook-ceph get cephcluster rook-ceph
    echo ""

    STATUS=$(kubectl -n rook-ceph get cephcluster rook-ceph -o json)
    # Get replication factor from first block pool (default 3)
    REPL=$(kubectl -n rook-ceph get cephblockpool -o jsonpath='{.items[0].spec.replicated.size}' 2>/dev/null || echo "3")

    echo "=== Capacity (${REPL}x replication) ==="
    TOTAL=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesTotal')
    USED=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesUsed')
    AVAIL=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesAvailable')
    USABLE=$((AVAIL / REPL))
    printf "Raw:    %s\n" "$(numfmt --to=iec-i --suffix=B $TOTAL 2>/dev/null || echo "${TOTAL} bytes")"
    printf "Usable: %s\n" "$(numfmt --to=iec-i --suffix=B $USABLE 2>/dev/null || echo "${USABLE} bytes")"
    printf "Used:   %s\n" "$(numfmt --to=iec-i --suffix=B $USED 2>/dev/null || echo "${USED} bytes")"

# Show health warnings/errors
[no-cd]
health:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG
    STATUS=$(kubectl -n rook-ceph get cephcluster rook-ceph -o json)

    HEALTH=$(echo "$STATUS" | jq -r '.status.ceph.health')
    echo "Health: $HEALTH"
    echo ""

    DETAILS=$(echo "$STATUS" | jq -r '.status.ceph.details // empty')
    if [[ -n "$DETAILS" && "$DETAILS" != "null" ]]; then
        echo "=== Issues ==="
        echo "$STATUS" | jq -r '.status.ceph.details | to_entries[] | "[\(.value.severity)] \(.key): \(.value.message)"'
    else
        echo "No health issues detected."
    fi

# Show OSD pods and their status
[no-cd]
osd:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG

    echo "=== OSD Pods ==="
    kubectl -n rook-ceph get pods -l app=rook-ceph-osd -o wide
    echo ""

    echo "=== OSD Storage Info ==="
    kubectl -n rook-ceph get cephcluster rook-ceph -o json | jq -r '.status.storage'

# Get dashboard admin password and copy to clipboard
[no-cd]
password:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    PASSWORD=$(KUBECONFIG="${KUBECONFIG}" kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
    URL=$(KUBECONFIG="${KUBECONFIG}" kubectl -n rook-ceph get ingress ceph-dashboard -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    echo "$PASSWORD" | pbcopy
    if [[ -n "$URL" ]]; then
        echo "Dashboard: https://${URL}"
    fi
    echo "User:      admin"
    echo "Password:  $PASSWORD (copied to clipboard)"

# Run storage benchmark (deploys fio pod, runs tests, cleans up)
[no-cd]
benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG
    exec scripts/ceph-benchmark.sh
