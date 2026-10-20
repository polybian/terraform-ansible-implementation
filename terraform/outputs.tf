# Outputs for the terraform-ansible-lab (LAB) deployment.
# Handy glue: ansible can consume these (terraform output -json) to build a
# dynamic inventory instead of hardcoding IPs — see docs/iac-workflow.md.

output "resource_group_name" {
  description = "Name of the lab resource group."
  value       = azurerm_resource_group.lab.name
}

output "vnet_id" {
  description = "ID of the lab virtual network."
  value       = azurerm_virtual_network.lab.id
}

output "subnet_id" {
  description = "ID of the lab subnet."
  value       = azurerm_subnet.lab.id
}

output "nsg_id" {
  description = "ID of the lab network security group."
  value       = azurerm_network_security_group.lab.id
}

output "vm_name" {
  description = "Name of the lab VM."
  value       = azurerm_linux_virtual_machine.lab.name
}

output "vm_public_ip" {
  description = "Public IP of the lab VM (Static SKU)."
  value       = azurerm_public_ip.lab.ip_address
}
