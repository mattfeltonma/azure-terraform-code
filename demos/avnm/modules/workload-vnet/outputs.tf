output "workload_vnet_id" {
  value       = azurerm_virtual_network.workload_vnet.id
  description = "The id of the workload virtual network"
}

output "route_table_id_app" {
  value       = azurerm_route_table.rt_app.id
  description = "The id of the route table associated with the app subnet"
}

output "route_table_name_app" {
  value       = azurerm_route_table.rt_app.name
  description = "The resource name of the route table associated with the app subnet"
}

output "route_table_id_data" {
  value       = azurerm_route_table.rt_data.id
  description = "The resource name of the route table associated with the data subnet"
}

output "route_table_name_data" {
  value       = azurerm_route_table.rt_data.name
  description = "The resource name of the route table associated with the data subnet"
}

output "subnet_id_app" {
  value       = azurerm_subnet.subnet_app.id
  description = "The resource id of the app subnet"
}

output "subnet_name_app" {
  value       = azurerm_subnet.subnet_app.name
  description = "The resource name of the app subnet"
}

output "subnet_id_data" {
  value       = azurerm_subnet.subnet_data.id
  description = "The resource id of the data subnet"
}

output "subnet_name_data" {
  value       = azurerm_subnet.subnet_data.name
  description = "The resource name of the data subnet"
}

output "subnet_id_svc" {
  value       = azurerm_subnet.subnet_svc.id
  description = "The resource id of the service subnet"
}

output "subnet_name_svc" {
  value       = azurerm_subnet.subnet_svc.name
  description = "The resource name of the service subnet"
}