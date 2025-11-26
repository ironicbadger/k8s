#!/usr/bin/env bash
set -euo pipefail

# Tailscale cleanup script
# Removes Tailscale devices and services matching a cluster name pattern
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
    # Returns: id, hostname, name (MagicDNS name), addresses, lastSeen, online status
    # lastSeen is only present when device is offline (connectedToControl=false)
    echo "${response}" | jq -r --arg cluster "${CLUSTER}" '
        .devices[]
        | select(.hostname | test($cluster; "i"))
        | [.id, .hostname, .name, (.addresses[0] // "no-ip"), (.lastSeen // "online"), (if .lastSeen then "offline" else "online" end)]
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

# List services matching the cluster pattern
list_services() {
    local response
    response=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://api.tailscale.com/api/v2/tailnet/-/services") || {
        echo "Error: Failed to list services" >&2
        return 1
    }

    # Filter vipServices by name containing cluster name
    # Service names have "svc:" prefix (e.g., "svc:homelab-k8s-api")
    # Returns: name (with svc: prefix), comment
    echo "${response}" | jq -r --arg cluster "${CLUSTER}" '
        .vipServices // [] | .[]
        | select(.name | test($cluster; "i"))
        | [.name, (.comment // "")]
        | @tsv' 2>/dev/null || true
}

# Delete a service by name
delete_service() {
    local service_name="$1"

    curl -s -X DELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://api.tailscale.com/api/v2/tailnet/-/services/${service_name}" || {
        echo "Warning: Failed to delete service ${service_name}" >&2
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
    local devices
    devices=$(list_devices)

    # List matching services
    echo "Searching for services matching '${CLUSTER}'..."
    local services
    services=$(list_services)
    echo ""

    # Check if anything to clean up
    if [[ -z "${devices}" && -z "${services}" ]]; then
        echo "No Tailscale devices or services found matching '${CLUSTER}'"
        exit 0
    fi

    # Display devices
    if [[ -n "${devices}" ]]; then
        echo "Found devices:"
        echo "--------------------------------------------------------------------------------"
        printf "%-20s %-25s %-15s %-8s %s\n" "HOSTNAME" "MAGICDNS NAME" "IP" "STATUS" "LAST SEEN"
        echo "--------------------------------------------------------------------------------"
        local stale_count=0
        local now_epoch
        now_epoch=$(date +%s)
        local twelve_hours=$((12 * 60 * 60))

        while IFS=$'\t' read -r id hostname name ip last_seen status; do
            local last_seen_display=""
            local is_stale=""

            if [[ "${status}" == "online" ]]; then
                last_seen_display="now"
            else
                # Parse ISO 8601 timestamp and calculate age
                local last_seen_epoch
                last_seen_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_seen}" +%s 2>/dev/null || \
                                  date -d "${last_seen}" +%s 2>/dev/null || echo "0")

                if [[ "${last_seen_epoch}" != "0" ]]; then
                    local age_seconds=$((now_epoch - last_seen_epoch))

                    if [[ ${age_seconds} -gt ${twelve_hours} ]]; then
                        is_stale="*"
                        ((stale_count++)) || true
                    fi

                    # Format age as human readable
                    if [[ ${age_seconds} -lt 60 ]]; then
                        last_seen_display="${age_seconds}s ago"
                    elif [[ ${age_seconds} -lt 3600 ]]; then
                        last_seen_display="$((age_seconds / 60))m ago"
                    elif [[ ${age_seconds} -lt 86400 ]]; then
                        last_seen_display="$((age_seconds / 3600))h ago"
                    else
                        last_seen_display="$((age_seconds / 86400))d ago"
                    fi
                else
                    last_seen_display="${last_seen}"
                fi
            fi

            if [[ -n "${is_stale}" ]]; then
                # Highlight stale devices with asterisk
                printf "%-20s %-25s %-15s %-8s %s %s\n" "${hostname}" "${name}" "${ip}" "${status}" "${last_seen_display}" "[STALE]"
            else
                printf "%-20s %-25s %-15s %-8s %s\n" "${hostname}" "${name}" "${ip}" "${status}" "${last_seen_display}"
            fi
        done <<< "${devices}"
        echo "--------------------------------------------------------------------------------"
        local device_count
        device_count=$(echo "${devices}" | wc -l | tr -d ' ')
        echo "Total: ${device_count} device(s)"
        if [[ ${stale_count} -gt 0 ]]; then
            echo ""
            echo "⚠️  ${stale_count} device(s) marked [STALE] - inactive for >12 hours"
            echo "   These are candidates for cleanup."
        fi
        echo ""
    fi

    # Display services
    if [[ -n "${services}" ]]; then
        echo "Found services:"
        echo "----------------------------------------"
        printf "%-30s %s\n" "SERVICE NAME" "COMMENT"
        echo "----------------------------------------"
        while IFS=$'\t' read -r name comment; do
            printf "%-30s %s\n" "${name}" "${comment:-}"
        done <<< "${services}"
        echo "----------------------------------------"
        local service_count
        service_count=$(echo "${services}" | wc -l | tr -d ' ')
        echo "Total: ${service_count} service(s)"
        echo ""
    fi

    # Confirm unless --yes flag
    if [[ "${SKIP_CONFIRM}" != "--yes" ]]; then
        read -p "Delete these devices and services? (yes/no): " confirm
        if [[ "${confirm}" != "yes" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Delete devices
    if [[ -n "${devices}" ]]; then
        echo ""
        echo "Deleting devices..."
        while IFS=$'\t' read -r id hostname name ip last_seen status; do
            echo "  Deleting ${hostname} (${id})..."
            delete_device "${id}" && echo "    Done" || echo "    Failed"
        done <<< "${devices}"
    fi

    # Delete services
    if [[ -n "${services}" ]]; then
        echo ""
        echo "Deleting services..."
        while IFS=$'\t' read -r name comment; do
            echo "  Deleting service ${name}..."
            delete_service "${name}" && echo "    Done" || echo "    Failed"
        done <<< "${services}"
    fi

    echo ""
    echo "Tailscale cleanup complete."
}

main
