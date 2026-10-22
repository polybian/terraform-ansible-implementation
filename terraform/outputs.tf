# Outputs for the terraform-ansible-implementation deployment.
# Handy glue: ansible can consume these (terraform output -json) to build a
# dynamic inventory instead of hardcoding IPs — see docs/iac-workflow.md.

output "resource_group_name" {
  description = "Name of the demo resource group."
  value       = azurerm_resource_group.demo.name
}

output "vnet_id" {
  description = "ID of the demo virtual network."
  value       = azurerm_virtual_network.demo.id
}

output "subnet_id" {
  description = "ID of the demo subnet."
  value       = azurerm_subnet.demo.id
}

output "nsg_id" {
  description = "ID of the demo network security group."
  value       = azurerm_network_security_group.demo.id
}

output "vm_name" {
  description = "Name of the demo VM."
  value       = azurerm_linux_virtual_machine.demo.name
}

output "vm_public_ip" {
  description = "Public IP of the demo VM (Static SKU)."
  value       = azurerm_public_ip.demo.ip_address
}
