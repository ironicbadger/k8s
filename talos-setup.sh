#!/bin/bash
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

CLUSTER_NAME="talos-cluster"

# Talos installer image with qemu-guest-agent
# Generate at: https://factory.talos.dev/?arch=amd64&extensions=siderolabs%2Fqemu-guest-agent&version=1.11.5
TALOS_VERSION="v1.11.5"
INSTALL_IMAGE="factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:$TALOS_VERSION"

# Network configuration
GATEWAY="10.42.0.254"
SUBNET_MASK="24"
NAMESERVERS=("10.42.0.253" "1.1.1.1")

# Output directory for generated configs
OUTPUT_DIR="_out"

# =============================================================================
# Get IPs from Terraform
# =============================================================================

echo "=== Talos Cluster Setup ==="
echo ""
echo "Refreshing Terraform state to get VM IPs..."
terraform -chdir=terraform refresh -input=false -var-file="secrets.tfvars" > /dev/null

# Parse IPs from terraform output
CP_IPS=($(terraform -chdir=terraform output -json control_plane_vms | jq -r '.[].ip'))
WORKER_IPS=($(terraform -chdir=terraform output -json worker_vms | jq -r '.[].ip'))

if [ -z "${CP_IPS[0]}" ] || [ "${CP_IPS[0]}" == "null" ]; then
  echo "Error: Could not get control plane IPs from Terraform"
  echo "Make sure VMs are running and guest agent is reporting"
  exit 1
fi

echo "Cluster: $CLUSTER_NAME"
echo "Control Plane: ${CP_IPS[*]}"
echo "Workers: ${WORKER_IPS[*]}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Use first control plane IP as cluster endpoint
CLUSTER_ENDPOINT="https://${CP_IPS[0]}:6443"

# Build nameservers JSON array
NS_JSON=$(printf '"%s",' "${NAMESERVERS[@]}" | sed 's/,$//')

# Generate base configuration with custom installer image
echo "Generating Talos configuration..."
talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" \
  --output-dir "$OUTPUT_DIR" \
  --install-image "$INSTALL_IMAGE" \
  --force

echo ""
echo "=== Applying Control Plane Configuration ==="

for i in "${!CP_IPS[@]}"; do
  IP="${CP_IPS[$i]}"
  HOSTNAME="talos-cp$((i + 1))"

  echo "Waiting for $HOSTNAME ($IP) to be reachable..."
  until talosctl get disks --insecure --nodes "$IP" &>/dev/null; do
    sleep 5
  done

  echo "Applying config to $HOSTNAME ($IP)..."
  talosctl apply-config \
    --insecure \
    --nodes "$IP" \
    --file "$OUTPUT_DIR/controlplane.yaml" \
    --config-patch "{
        \"machine\": {
          \"network\": {
            \"hostname\": \"$HOSTNAME\",
            \"interfaces\": [{
              \"interface\": \"eth0\",
              \"addresses\": [\"$IP/$SUBNET_MASK\"],
              \"routes\": [{
                \"network\": \"0.0.0.0/0\",
                \"gateway\": \"$GATEWAY\"
              }]
            }],
            \"nameservers\": [$NS_JSON]
          },
          \"install\": {
            \"disk\": \"/dev/sda\",
            \"image\": \"$INSTALL_IMAGE\"
          }
        }
      }"

  echo "$HOSTNAME configured"
done

echo ""
echo "=== Applying Worker Configuration ==="

for i in "${!WORKER_IPS[@]}"; do
  IP="${WORKER_IPS[$i]}"
  HOSTNAME="talos-worker$((i + 1))"

  echo "Waiting for $HOSTNAME ($IP) to be reachable..."
  until talosctl get disks --insecure --nodes "$IP" &>/dev/null; do
    sleep 5
  done

  echo "Applying config to $HOSTNAME ($IP)..."
  talosctl apply-config \
    --insecure \
    --nodes "$IP" \
    --file "$OUTPUT_DIR/worker.yaml" \
    --config-patch "{
        \"machine\": {
          \"network\": {
            \"hostname\": \"$HOSTNAME\",
            \"interfaces\": [{
              \"interface\": \"eth0\",
              \"addresses\": [\"$IP/$SUBNET_MASK\"],
              \"routes\": [{
                \"network\": \"0.0.0.0/0\",
                \"gateway\": \"$GATEWAY\"
              }]
            }],
            \"nameservers\": [$NS_JSON]
          },
          \"install\": {
            \"disk\": \"/dev/sda\",
            \"image\": \"$INSTALL_IMAGE\"
          }
        }
      }"

  echo "$HOSTNAME configured"
done

echo ""
echo "=== Setting up talosctl ==="

export TALOSCONFIG="$OUTPUT_DIR/talosconfig"
talosctl config endpoint "${CP_IPS[0]}"
talosctl config node "${CP_IPS[0]}"

echo ""
echo "=== Bootstrapping Cluster ==="
echo "Waiting for control plane to be ready..."
sleep 30

talosctl bootstrap

echo ""
echo "=== Retrieving Kubeconfig ==="
talosctl kubeconfig "$OUTPUT_DIR/kubeconfig"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Talos config: $OUTPUT_DIR/talosconfig"
echo "Kubeconfig:   $OUTPUT_DIR/kubeconfig"
echo ""
echo "Usage:"
echo "  export TALOSCONFIG=$PWD/$OUTPUT_DIR/talosconfig"
echo "  export KUBECONFIG=$PWD/$OUTPUT_DIR/kubeconfig"
echo "  kubectl get nodes"
