#!/usr/bin/env bash
set -euo pipefail

# Tailscale device cleanup script
# Removes Tailscale devices matching a hostname pattern for cluster teardown
#
# Usage:
#   ./scripts/tailscale-cleanup.sh <cluster-name> [--yes]
#
# Options:
#   --yes    Skip confirmation prompt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER="${1:-}"
SKIP_CONFIRM="${2:-}"

if [[ -z "${CLUSTER}" ]]; then
    echo "Usage: $0 <cluster-name> [--yes]"
    exit 1
fi

# Get OAuth credentials from the SOPS-encrypted Kubernetes secret
get_credentials() {
    local secret_file="${PROJECT_ROOT}/infrastructure/core/overlays/homelab/tailscale-secret.sops.yaml"

    if [[ ! -f "${secret_file}" ]]; then
        echo "Error: Tailscale secret not found at ${secret_file}" >&2
        return 1
    fi

    local decrypted
    decrypted=$(sops -d "${secret_file}" 2>/dev/null) || {
        echo "Error: Failed to decrypt ${secret_file}" >&2
        return 1
    }

    CLIENT_ID=$(echo "${decrypted}" | grep 'client_id:' | awk '{print $2}')
    CLIENT_SECRET=$(echo "${decrypted}" | grep 'client_secret:' | awk '{print $2}')

    if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" ]]; then
        echo "Error: Could not extract OAuth credentials from secret" >&2
        return 1
    fi
}

# Get OAuth access token
get_access_token() {
    local response
    response=$(curl -s -X POST "https://api.tailscale.com/api/v2/oauth/token" \
        -d "client_id=${CLIENT_ID}" \
        -d "client_secret=${CLIENT_SECRET}" \
        -d "grant_type=client_credentials") || {
        echo "Error: Failed to get access token" >&2
        return 1
    }

    ACCESS_TOKEN=$(echo "${response}" | jq -r '.access_token // empty')

    if [[ -z "${ACCESS_TOKEN}" ]]; then
        echo "Error: Failed to get access token. Response: ${response}" >&2
        return 1
    fi
}

# List devices matching the cluster pattern
list_devices() {
    local response
    response=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://api.tailscale.com/api/v2/tailnet/-/devices") || {
        echo "Error: Failed to list devices" >&2
        return 1
    }

    # Filter devices by hostname containing cluster name
    # Returns: id, hostname, name (MagicDNS name), addresses
    echo "${response}" | jq -r --arg cluster "${CLUSTER}" '
        .devices[]
        | select(.hostname | test($cluster; "i"))
        | [.id, .hostname, .name, (.addresses[0] // "no-ip")]
        | @tsv'
}

# Delete a device by ID
delete_device() {
    local device_id="$1"

    curl -s -X DELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://api.tailscale.com/api/v2/device/${device_id}" || {
        echo "Warning: Failed to delete device ${device_id}" >&2
        return 1
    }
}

main() {
    echo "Tailscale Cleanup for cluster: ${CLUSTER}"
    echo ""

    # Get credentials
    echo "Loading credentials..."
    get_credentials || exit 1

    # Get access token
    echo "Authenticating with Tailscale API..."
    get_access_token || exit 1

    # List matching devices
    echo "Searching for devices matching '${CLUSTER}'..."
    echo ""

    local devices
    devices=$(list_devices)

    if [[ -z "${devices}" ]]; then
        echo "No Tailscale devices found matching '${CLUSTER}'"
        exit 0
    fi

    # Display devices
    echo "Found devices:"
    echo "----------------------------------------"
    printf "%-20s %-30s %-15s\n" "HOSTNAME" "MAGICNS NAME" "IP"
    echo "----------------------------------------"
    while IFS=$'\t' read -r id hostname name ip; do
        printf "%-20s %-30s %-15s\n" "${hostname}" "${name}" "${ip}"
    done <<< "${devices}"
    echo "----------------------------------------"
    echo ""

    # Count devices
    local count
    count=$(echo "${devices}" | wc -l | tr -d ' ')
    echo "Total: ${count} device(s) will be deleted"
    echo ""

    # Confirm unless --yes flag
    if [[ "${SKIP_CONFIRM}" != "--yes" ]]; then
        read -p "Delete these devices? (yes/no): " confirm
        if [[ "${confirm}" != "yes" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Delete devices
    echo ""
    echo "Deleting devices..."
    while IFS=$'\t' read -r id hostname name ip; do
        echo "  Deleting ${hostname} (${id})..."
        delete_device "${id}" && echo "    Done" || echo "    Failed"
    done <<< "${devices}"

    echo ""
    echo "Tailscale cleanup complete."
}

main
