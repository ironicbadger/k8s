#!/usr/bin/env bash
set -euo pipefail

# Sync cluster configuration
# Generates Terraform tfvars and talconfig.yaml from cluster.yaml (single source of truth)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse arguments
CLUSTER_NAME="${1:-homelab}"
CLUSTER_DIR="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"
CLUSTER_YAML="${CLUSTER_DIR}/cluster.yaml"

if [[ ! -f "${CLUSTER_YAML}" ]]; then
  echo "❌ Error: cluster.yaml not found at ${CLUSTER_YAML}"
  echo "Available clusters:"
  ls -1 "${PROJECT_ROOT}/clusters/" 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "🔄 Syncing configuration for cluster: ${CLUSTER_NAME}"
echo "   Source: ${CLUSTER_YAML}"
echo ""

# Ensure required tools are installed
for cmd in yq jq; do
  if ! command -v $cmd &> /dev/null; then
    echo "❌ Error: $cmd is not installed. Please install it first."
    exit 1
  fi
done

# Read values from cluster.yaml using yq (supports both mikefarah/yq and kislyuk/yq)
read_config() {
  # Try mikefarah/yq syntax first (yq eval '.path' file)
  if yq eval "$1" "${CLUSTER_YAML}" 2>/dev/null; then
    return 0
  fi
  # Fall back to kislyuk/yq syntax (yq '.path' file)
  yq -r "$1" "${CLUSTER_YAML}" 2>/dev/null || echo ""
}

# Extract configuration
METADATA_NAME=$(read_config '.metadata.name')
METADATA_ENV=$(read_config '.metadata.environment')

TALOS_VERSION=$(read_config '.cluster.talos.version')
TALOS_CLUSTER_NAME=$(read_config '.cluster.talos.clusterName')
TALOS_SCHEMATIC=$(read_config '.cluster.talos.factorySchematic')
TALOS_INSTALL_DISK=$(read_config '.cluster.talos.installDisk')

CP_COUNT=$(read_config '.cluster.topology.controlPlane.count')
CP_CORES=$(read_config '.cluster.topology.controlPlane.resources.cores')
CP_MEMORY=$(read_config '.cluster.topology.controlPlane.resources.memory')
CP_DISK=$(read_config '.cluster.topology.controlPlane.resources.disk')

WORKER_COUNT=$(read_config '.cluster.topology.workers.count')
WORKER_CORES=$(read_config '.cluster.topology.workers.resources.cores')
WORKER_MEMORY=$(read_config '.cluster.topology.workers.resources.memory')
WORKER_DISK=$(read_config '.cluster.topology.workers.resources.disk')

PROXMOX_ENDPOINT=$(read_config '.proxmox.endpoint')
PROXMOX_NODE=$(read_config '.proxmox.node')
PROXMOX_INSECURE=$(read_config '.proxmox.insecure')
PROXMOX_STORAGE=$(read_config '.proxmox.storage.datastore')
PROXMOX_ISO=$(read_config '.proxmox.storage.isoPath')
PROXMOX_BRIDGE=$(read_config '.proxmox.network.bridge')
PROXMOX_VM_ID_BASE=$(read_config '.proxmox.vm.idBase')
PROXMOX_CPU_TYPE=$(read_config '.proxmox.vm.cpuType')
PROXMOX_ON_BOOT=$(read_config '.proxmox.vm.onBoot')
PROXMOX_FORCE_STOP=$(read_config '.proxmox.vm.forceStop')

# Generate Terraform tfvars
TERRAFORM_DIR="${CLUSTER_DIR}/terraform"
TFVARS_FILE="${TERRAFORM_DIR}/terraform.tfvars"

mkdir -p "${TERRAFORM_DIR}"

echo "📝 Generating Terraform configuration..."
cat > "${TFVARS_FILE}" <<EOF
# Auto-generated from ${CLUSTER_YAML}
# DO NOT EDIT MANUALLY - run 'just sync cluster=${CLUSTER_NAME}' to regenerate

cluster_name = "${METADATA_NAME}"
environment  = "${METADATA_ENV}"

# Proxmox connection
proxmox_endpoint = "${PROXMOX_ENDPOINT}"
proxmox_insecure = ${PROXMOX_INSECURE}
proxmox_node     = "${PROXMOX_NODE}"

# Storage and network
storage        = "${PROXMOX_STORAGE}"
network_bridge = "${PROXMOX_BRIDGE}"
talos_iso      = "${PROXMOX_ISO}"

# Node counts
cp_count     = ${CP_COUNT}
worker_count = ${WORKER_COUNT}

# Control plane resources
control_plane = {
  cores  = ${CP_CORES}
  memory = ${CP_MEMORY}
  disk   = ${CP_DISK}
}

# Worker resources
worker = {
  cores  = ${WORKER_CORES}
  memory = ${WORKER_MEMORY}
  disk   = ${WORKER_DISK}
}

# VM settings
cpu_type   = "${PROXMOX_CPU_TYPE}"
vm_id_base = ${PROXMOX_VM_ID_BASE}
on_boot    = ${PROXMOX_ON_BOOT}
force_stop = ${PROXMOX_FORCE_STOP}
EOF

echo "   ✅ Created: ${TFVARS_FILE}"

# Copy .envrc if it doesn't exist in cluster terraform dir
if [[ ! -f "${TERRAFORM_DIR}/.envrc" ]] && [[ -f "${PROJECT_ROOT}/terraform/.envrc" ]]; then
  cp "${PROJECT_ROOT}/terraform/.envrc" "${TERRAFORM_DIR}/.envrc"
  echo "   ✅ Copied: ${TERRAFORM_DIR}/.envrc"
fi

# Generate talconfig.yaml template (IPs will be synced after terraform apply)
TALOS_DIR="${CLUSTER_DIR}/talos"
TALCONFIG_FILE="${TALOS_DIR}/talconfig.yaml"

mkdir -p "${TALOS_DIR}"

FACTORY_IMAGE="factory.talos.dev/installer/${TALOS_SCHEMATIC}:${TALOS_VERSION}"

echo "📝 Generating Talos configuration template..."
cat > "${TALCONFIG_FILE}" <<EOF
# Auto-generated from ${CLUSTER_YAML}
# IPs will be synced from Terraform state after 'terraform apply'

clusterName: ${TALOS_CLUSTER_NAME}
talosVersion: ${TALOS_VERSION}
endpoint: https://PENDING:6443
talosImageURL: ${FACTORY_IMAGE}

nodes: []
# Run 'just sync-ips cluster=${CLUSTER_NAME}' after terraform apply to populate nodes
EOF

echo "   ✅ Created: ${TALCONFIG_FILE}"
echo ""
echo "✅ Configuration sync complete!"
echo ""
echo "Next steps:"
echo "  1. Copy secrets.tfvars to ${TERRAFORM_DIR}/"
echo "  2. just cluster=${CLUSTER_NAME} init     # Initialize Terraform"
echo "  3. just cluster=${CLUSTER_NAME} apply    # Create VMs"
echo "  4. just cluster=${CLUSTER_NAME} sync-ips # Sync IPs to talconfig.yaml"
echo "  5. just cluster=${CLUSTER_NAME} talgen   # Generate Talos configs"
echo "  6. just cluster=${CLUSTER_NAME} talos    # Bootstrap cluster"
