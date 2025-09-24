output "subnet_id_app" {
  value       = azurerm_subnet.subnet_app.id
  description = "The resource id of the app subnet"
}

output "subnet_name_app" {
  value       = azurerm_subnet.subnet_app.name
  description = "The resource name of the app subnet"
}

output "subnet_id_svc" {
  value       = azurerm_subnet.subnet_svc.id
  description = "The resource id of the service subnet"
}

output "subnet_name_svc" {
  value       = azurerm_subnet.subnet_svc.name
  description = "The resource name of the service subnet"
}

output "vm_managed_identity" {
  value       = azurerm_user_assigned_identity.umi.principal_id
  description = "The managed identity ID of the VM"
}

output "workload_vnet_id" {
  value       = azurerm_virtual_network.vnet.id
  description = "The id of the workload virtual network"
}


