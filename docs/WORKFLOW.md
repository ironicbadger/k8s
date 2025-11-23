# Talos Cluster Workflow

This repository uses a **single source of truth** approach where Terraform defines the cluster topology (node counts, resources) and automatically generates the talhelper configuration.

## Architecture

```
terraform/terraform.tfvars     (Source of Truth)
         ↓
   Terraform Apply (creates VMs with DHCP)
         ↓
   Terraform State (captures actual VM IPs)
         ↓
   sync-talconfig.sh (generates talconfig.yaml)
         ↓
   talhelper (generates Talos configs)
         ↓
   Talos cluster bootstrapped
```

## Key Features

- **Full DHCP**: No hardcoded IPs - VMs get addresses from DHCP
- **Single config file per node type**: Uses talhelper's `ignoreHostname: true` feature
- **Auto-sync**: Script reads Terraform state and generates talconfig.yaml
- **Scale easily**: Just change `cp_count` and `worker_count` in terraform.tfvars

## Workflow

### Initial Setup

1. **Edit cluster topology** in [terraform/terraform.tfvars](terraform/terraform.tfvars):
   ```hcl
   cp_count     = 1  # Number of control plane nodes
   worker_count = 1  # Number of worker nodes
   ```

2. **Initialize Terraform**:
   ```bash
   just init
   ```

### Deploy Cluster

3. **Create VMs with Terraform**:
   ```bash
   just apply
   ```
   This creates the VMs in Proxmox and they get DHCP addresses.

4. **Sync talconfig.yaml from Terraform state**:
   ```bash
   just sync-talconfig
   ```
   This runs [scripts/sync-talconfig.sh](scripts/sync-talconfig.sh) which:
   - Refreshes Terraform state to get latest VM IPs
   - Extracts control plane and worker IPs
   - Generates `talconfig.yaml` with comma-separated IPs

5. **Generate talhelper secrets** (first time only):
   ```bash
   just talhelper-secrets
   ```

6. **Generate Talos configs**:
   ```bash
   just talhelper-gen
   ```

7. **Bootstrap cluster**:
   ```bash
   just talos
   ```

### Scaling

To add/remove nodes:

1. Edit `cp_count` or `worker_count` in [terraform/terraform.tfvars](terraform/terraform.tfvars)
2. Run: `just apply`
3. Run: `just sync-talconfig`
4. Run: `just talhelper-gen`
5. Apply new configs to cluster

### Destroy

```bash
just nuke
```

## Files

- **terraform/terraform.tfvars**: Source of truth for cluster topology
- **scripts/sync-talconfig.sh**: Generates talconfig.yaml from Terraform state
- **talconfig.yaml**: Auto-generated talhelper config (do not edit manually)
- **justfile**: Task runner with all commands

## How It Works

### talhelper's ignoreHostname feature

The generated `talconfig.yaml` uses:

```yaml
nodes:
  - hostname: talos-cp
    ipAddress: 10.42.5.10, 10.42.5.11, 10.42.5.12
    controlPlane: true
    ignoreHostname: true
```

This creates a **single config file** (`talos-cp.yaml`) that applies to all control plane nodes, regardless of their actual hostnames. Same for workers.

### Terraform Outputs

The [terraform/outputs.tf](terraform/outputs.tf) exposes VM information:

```hcl
output "control_plane_vms" {
  value = {
    for vm in proxmox_virtual_environment_vm.control_plane : vm.name => {
      ip = try([for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
    }
  }
}
```

The sync script extracts these IPs and formats them for talhelper.
