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
