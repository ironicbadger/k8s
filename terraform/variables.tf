# Proxmox Connection
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in format: user@realm!tokenid=token-value"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

# Proxmox Node Configuration
variable "proxmox_node" {
  description = "Proxmox node name for VM placement"
  type        = string
  default     = "ms01"
}

variable "storage" {
  description = "Storage datastore for VM disks"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Network bridge for VM network interfaces"
  type        = string
  default     = "vmbr0"
}

# Talos ISO Configuration
variable "talos_iso" {
  description = "Path to Talos ISO file (datastore:iso/filename)"
  type        = string
  default     = "c137-isos:iso/talos-1.11.5-qemuguest.iso"
}

# Node Counts
variable "cp_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

# Control Plane Configuration
variable "control_plane" {
  description = "Control plane node configuration"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    cores  = 4
    memory = 8192
    disk   = 32
  }
}

# Worker Configuration
variable "worker" {
  description = "Worker node configuration"
  type = object({
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    cores  = 4
    memory = 32768
    disk   = 100
  }
}

# VM Configuration
variable "cpu_type" {
  description = "CPU type for VMs"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "vm_id_base" {
  description = "Base VM ID (control planes start here, workers offset by 10)"
  type        = number
  default     = 800
}

variable "force_stop" {
  description = "Force stop VMs on destroy (use for nuke)"
  type        = bool
  default     = false
}

# Network Configuration (used by talos-setup.sh)
variable "control_plane_ips" {
  description = "Static IPs for control plane nodes"
  type        = list(string)
  default     = ["10.42.5.10"]
}

variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
  default     = ["10.42.5.20"]
}

variable "gateway" {
  description = "Gateway IP for the cluster network"
  type        = string
  default     = "10.42.0.254"
}

variable "subnet_mask" {
  description = "Subnet mask in CIDR notation"
  type        = string
  default     = "24"
}

# Garage S3 Backend Credentials
# These are only used via .envrc for backend authentication
# They are not used in the Terraform configuration itself
variable "terraform_garage_s3_keyid" {
  description = "Garage S3 access key ID (loaded from secrets.tfvars, exported via .envrc)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "terraform_garage_s3_secretkey" {
  description = "Garage S3 secret key (loaded from secrets.tfvars, exported via .envrc)"
  type        = string
  default     = ""
  sensitive   = true
}
