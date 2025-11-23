#!/usr/bin/env bash
set -euo pipefail

# Sync IP addresses from Terraform state to talconfig.yaml
# This script updates talconfig.yaml with actual VM IPs after terraform apply

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse arguments
CLUSTER_NAME="${1:-homelab}"
CLUSTER_DIR="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"
TERRAFORM_DIR="${CLUSTER_DIR}/terraform"
TALOS_DIR="${CLUSTER_DIR}/talos"
CLUSTER_YAML="${CLUSTER_DIR}/cluster.yaml"
TALCONFIG_FILE="${TALOS_DIR}/talconfig.yaml"

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
  echo "❌ Error: Terraform directory not found: ${TERRAFORM_DIR}"
  echo "Run 'just sync cluster=${CLUSTER_NAME}' first"
  exit 1
fi

if [[ ! -f "${CLUSTER_YAML}" ]]; then
  echo "❌ Error: cluster.yaml not found: ${CLUSTER_YAML}"
  exit 1
fi

echo "🔄 Syncing IP addresses from Terraform state..."
echo "   Cluster: ${CLUSTER_NAME}"
echo ""

# Source S3 backend credentials if .envrc exists
if [[ -f "${TERRAFORM_DIR}/.envrc" ]]; then
  cd "${TERRAFORM_DIR}"
  source .envrc
  cd "${PROJECT_ROOT}"
fi

# Refresh Terraform state to get latest IPs
echo "🔄 Refreshing Terraform state..."
VAR_FILE_ARGS=()
if [[ -f "${TERRAFORM_DIR}/secrets.tfvars" ]]; then
  VAR_FILE_ARGS+=("-var-file=secrets.tfvars")
fi
if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
  VAR_FILE_ARGS+=("-var-file=terraform.tfvars")
fi

if ! tofu -chdir="${TERRAFORM_DIR}" refresh "${VAR_FILE_ARGS[@]}" > /dev/null 2>&1; then
  echo "⚠️  Warning: Terraform refresh failed. Using existing state..."
fi

# Extract VM information from Terraform outputs
echo "📊 Extracting VM information..."
TF_OUTPUT=$(tofu -chdir="${TERRAFORM_DIR}" output -json)

# Extract node data
CP_NODES=$(echo "$TF_OUTPUT" | jq -r '.control_plane_vms.value | to_entries | map({name: .key, ip: .value.ip}) | .[]' | jq -s '.')
WORKER_NODES=$(echo "$TF_OUTPUT" | jq -r '.worker_vms.value | to_entries | map({name: .key, ip: .value.ip}) | .[]' | jq -s '.')

# Get first control plane IP for endpoint
ENDPOINT_IP=$(echo "$CP_NODES" | jq -r '.[0].ip')

if [[ -z "${ENDPOINT_IP}" || "${ENDPOINT_IP}" == "null" ]]; then
  echo "❌ Error: Could not get control plane IP from Terraform state"
  echo "Make sure VMs are running and have IP addresses assigned"
  exit 1
fi

echo "   Control Plane nodes: $(echo "$CP_NODES" | jq -r '.[].name' | tr '\n' ' ')"
echo "   Worker nodes: $(echo "$WORKER_NODES" | jq -r '.[].name' | tr '\n' ' ')"
echo "   Cluster endpoint: ${ENDPOINT_IP}"

# Read Talos config from cluster.yaml (supports both yq versions)
read_config() {
  if yq eval "$1" "${CLUSTER_YAML}" 2>/dev/null; then
    return 0
  fi
  yq -r "$1" "${CLUSTER_YAML}" 2>/dev/null || echo ""
}

TALOS_VERSION=$(read_config '.cluster.talos.version')
TALOS_CLUSTER_NAME=$(read_config '.cluster.talos.clusterName')
TALOS_SCHEMATIC=$(read_config '.cluster.talos.factorySchematic')
TALOS_INSTALL_DISK=$(read_config '.cluster.talos.installDisk')

FACTORY_IMAGE="factory.talos.dev/installer/${TALOS_SCHEMATIC}:${TALOS_VERSION}"

# Generate talconfig.yaml
mkdir -p "${TALOS_DIR}"

echo "📝 Updating talconfig.yaml..."
cat > "${TALCONFIG_FILE}" <<EOF
# Auto-generated from cluster.yaml and Terraform state
# Source: ${CLUSTER_YAML}
# IPs synced from: ${TERRAFORM_DIR}

clusterName: ${TALOS_CLUSTER_NAME}
talosVersion: ${TALOS_VERSION}
endpoint: https://${ENDPOINT_IP}:6443
talosImageURL: ${FACTORY_IMAGE}

nodes:
EOF

# Add control plane nodes
echo "$CP_NODES" | jq -r '.[] | "  - hostname: \(.name)\n    ipAddress: \(.ip)\n    controlPlane: true\n    installDisk: '${TALOS_INSTALL_DISK}'\n    networkInterfaces:\n      - interface: eth0\n        dhcp: true\n"' >> "${TALCONFIG_FILE}"

# Add worker nodes
echo "$WORKER_NODES" | jq -r '.[] | "  - hostname: \(.name)\n    ipAddress: \(.ip)\n    controlPlane: false\n    installDisk: '${TALOS_INSTALL_DISK}'\n    networkInterfaces:\n      - interface: eth0\n        dhcp: true\n"' >> "${TALCONFIG_FILE}"

echo "   ✅ Updated: ${TALCONFIG_FILE}"
echo ""
echo "✅ IP sync complete!"
echo ""
echo "Next steps:"
echo "  just cluster=${CLUSTER_NAME} talgen  # Generate Talos configs"
echo "  just cluster=${CLUSTER_NAME} talos   # Bootstrap cluster"
