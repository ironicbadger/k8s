provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent = true
  }
}

# Control Plane Nodes
resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.cp_count

  name        = "talos-cp${count.index + 1}"
  description = "Talos Kubernetes Control Plane Node"
  tags        = []

  node_name = var.proxmox_node
  vm_id     = var.vm_id_base + count.index

  on_boot         = false
  started         = true
  stop_on_destroy = var.force_stop

  cpu {
    cores = var.control_plane.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.control_plane.memory
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.control_plane.disk
    file_format  = "raw"
  }

  cdrom {
    file_id   = var.talos_iso
    interface = "ide2"
  }

  boot_order = ["scsi0", "ide2"]

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "45s"
  }

  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }
}

# Worker Nodes
resource "proxmox_virtual_environment_vm" "worker" {
  count = var.worker_count

  name        = "talos-worker${count.index + 1}"
  description = "Talos Kubernetes Worker Node"
  tags        = []

  node_name = var.proxmox_node
  vm_id     = var.vm_id_base + 10 + count.index

  on_boot         = false
  started         = true
  stop_on_destroy = var.force_stop

  cpu {
    cores = var.worker.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.worker.memory
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.worker.disk
    file_format  = "raw"
  }

  cdrom {
    file_id   = var.talos_iso
    interface = "ide2"
  }

  boot_order = ["scsi0", "ide2"]

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "45s"
  }

  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }
}
