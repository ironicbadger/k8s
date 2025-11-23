output "control_plane_vms" {
  description = "Control plane VM information"
  value = {
    for i, vm in proxmox_virtual_environment_vm.control_plane : vm.name => {
      id   = vm.vm_id
      name = vm.name
      ip   = try([for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
    }
  }
}

output "worker_vms" {
  description = "Worker VM information"
  value = {
    for i, vm in proxmox_virtual_environment_vm.worker : vm.name => {
      id   = vm.vm_id
      name = vm.name
      ip   = try([for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
    }
  }
}

output "all_vm_ids" {
  description = "All VM IDs for reference"
  value = concat(
    [for vm in proxmox_virtual_environment_vm.control_plane : vm.vm_id],
    [for vm in proxmox_virtual_environment_vm.worker : vm.vm_id]
  )
}

output "control_plane_ips" {
  description = "List of control plane IP addresses"
  value = [
    for vm in proxmox_virtual_environment_vm.control_plane :
    try([for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
  ]
}

output "worker_ips" {
  description = "List of worker IP addresses"
  value = [
    for vm in proxmox_virtual_environment_vm.worker :
    try([for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
  ]
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (first control plane IP)"
  value       = try([for ip in flatten(proxmox_virtual_environment_vm.control_plane[0].ipv4_addresses) : ip if ip != "127.0.0.1"][0], "")
}
