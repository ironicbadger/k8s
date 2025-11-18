# Proxmox Connection
proxmox_endpoint = "https://px.wd.ktz.me/"
proxmox_insecure = false

# Proxmox Node
proxmox_node   = "ms01"
storage        = "local"
network_bridge = "vmbr0"

# Talos ISO - Update filename to match your ISO
talos_iso = "c137-isos:iso/talos-1.11.5-qemuguest-metal-amd64.iso"

# Node Counts - Adjust to scale cluster
cp_count     = 1
worker_count = 1

# Control Plane Configuration
control_plane = {
  cores  = 4
  memory = 8192  # 8 GB
  disk   = 32    # GB
}

# Worker Configuration
worker = {
  cores  = 8
  memory = 16384  # 32 GB
  disk   = 100    # GB
}

# VM Settings
cpu_type   = "x86-64-v2-AES"
vm_id_base = 800

# Network Configuration (used by talos-setup.sh)
control_plane_ips = ["10.42.5.10"]
worker_ips        = ["10.42.5.20"]
gateway           = "10.42.0.254"
subnet_mask       = "24"
