variable "cluster_name" {
  description = "Name of the cluster (used for VM naming)"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name for VM placement"
  type        = string
}

variable "storage" {
  description = "Storage datastore for VM disks"
  type        = string
}

variable "network_bridge" {
  description = "Network bridge for VM network interfaces"
  type        = string
}

variable "talos_iso" {
  description = "Path to Talos ISO file (datastore:iso/filename)"
  type        = string
}

variable "cp_count" {
  description = "Number of control plane nodes"
  type        = number
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
}

variable "control_plane" {
  description = "Control plane node configuration"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
}

variable "worker" {
  description = "Worker node configuration"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
}

variable "cpu_type" {
  description = "CPU type for VMs"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "vm_id_base" {
  description = "Base VM ID (control planes start here, workers offset by 10)"
  type        = number
}

variable "on_boot" {
  description = "Start VMs on Proxmox boot"
  type        = bool
  default     = false
}

variable "force_stop" {
  description = "Force stop VMs on destroy"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for VMs"
  type        = list(string)
  default     = []
}
