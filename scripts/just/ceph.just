# Ceph monitoring commands
# Usage: just ceph <command>
# For bare metal: export JUST_BM_CLUSTER=m720q

set shell := ["bash", "-euo", "pipefail", "-c"]

_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# Show cluster status (health, capacity, versions)
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
    STATUS=$(kubectl -n rook-ceph get cephcluster rook-ceph -o json)

    echo "=== Ceph Cluster Status ==="
    echo ""
    HEALTH=$(echo "$STATUS" | jq -r '.status.ceph.health')
    STATE=$(echo "$STATUS" | jq -r '.status.state')
    PHASE=$(echo "$STATUS" | jq -r '.status.phase')
    echo "Health: $HEALTH"
    echo "State:  $STATE ($PHASE)"
    echo ""

    echo "=== Capacity ==="
    TOTAL=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesTotal')
    USED=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesUsed')
    AVAIL=$(echo "$STATUS" | jq -r '.status.ceph.capacity.bytesAvailable')
    printf "Total: %s\n" "$(numfmt --to=iec-i --suffix=B $TOTAL 2>/dev/null || echo "${TOTAL} bytes")"
    printf "Used:  %s\n" "$(numfmt --to=iec-i --suffix=B $USED 2>/dev/null || echo "${USED} bytes")"
    printf "Avail: %s\n" "$(numfmt --to=iec-i --suffix=B $AVAIL 2>/dev/null || echo "${AVAIL} bytes")"
    echo ""

    echo "=== Components ==="
    echo "$STATUS" | jq -r '.status.ceph.versions | to_entries[] | select(.key != "overall") | "\(.key): \(.value | keys[0] | split(" ")[2])"'

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
