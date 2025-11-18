# Talos Kubernetes on Proxmox

Terraform + bash scripts to deploy a Talos Linux Kubernetes cluster on Proxmox VE.

## Prerequisites

- Proxmox VE 8+
- Terraform 1.0+
- talosctl
- jq
- just (optional, for convenience commands)

## Setup

### 1. Download Talos ISO

Download the Talos ISO with QEMU guest agent from:
https://factory.talos.dev/?arch=amd64&extensions=-/official/siderolabs/qemu-guest-agent&version=1.11.5

Upload to your Proxmox ISO storage.

### 2. Configure Terraform

```bash
cd terraform
cp secrets.tfvars.example secrets.tfvars
```

Edit `secrets.tfvars` with your Proxmox API token:
```hcl
proxmox_api_token = "user@realm!tokenid=your-token-here"
```

Edit `terraform.tfvars` to match your environment:
- `proxmox_endpoint` - Your Proxmox API URL
- `proxmox_node` - Target node name
- `talos_iso` - Path to uploaded ISO
- `cp_count` / `worker_count` - Number of nodes

### 3. Initialize Terraform

```bash
just init
```

### 4. Create VMs

```bash
just apply
```

### 5. Configure Talos & Bootstrap

```bash
just talos
```

This will:
- Get VM IPs from Proxmox guest agent
- Generate Talos machine configs
- Apply configs to each node
- Bootstrap the Kubernetes cluster
- Retrieve kubeconfig

### 6. Access Cluster

```bash
export TALOSCONFIG=$PWD/_out/talosconfig
export KUBECONFIG=$PWD/_out/kubeconfig
kubectl get nodes
```

## Commands

| Command | Description |
|---------|-------------|
| `just init` | Initialize Terraform |
| `just plan` | Show Terraform plan |
| `just apply` | Create VMs |
| `just talos` | Configure Talos & bootstrap cluster |
| `just nuke` | Destroy everything |

## Configuration

### Network

Edit `talos-setup.sh` to configure:
- `GATEWAY` - Network gateway
- `SUBNET_MASK` - CIDR notation
- `NAMESERVERS` - DNS servers

### Node Specs

Edit `terraform/terraform.tfvars`:
```hcl
control_plane = {
  cores  = 4
  memory = 8192   # MB
  disk   = 32     # GB
}

worker = {
  cores  = 4
  memory = 32768  # MB
  disk   = 100    # GB
}
```

## License

MIT
