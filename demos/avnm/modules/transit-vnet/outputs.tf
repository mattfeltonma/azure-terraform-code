output "lb_trusted_ip" {
  value = azurerm_lb.lb_trusted.frontend_ip_configuration[0].private_ip_address
  description = "The IP address of the load balancer in front of the trusted interface of the NVA"
}

output "lb_untrusted_ip" {
  value = azurerm_lb.lb_untrusted.frontend_ip_configuration[0].private_ip_address
  description = "The IP address of the load balancer in front of the untrusted interface of the NVA"
}

output "transit_vnet_id" {
  value       = azurerm_virtual_network.vnet_transit.id
  description = "The id of the transit virtual network"
}

output "route_table_id_gateway" {
  value       = azurerm_route_table.rt_gateway.id
  description = "The id of the route table associated with the GatewaySubnet"
}

output "route_table_name_gateway" {
  value       = azurerm_route_table.rt_gateway.name
  description = "The resource name of the route table associated with the GatewaySubnet"
}

output "route_table_id_firewall_private" {
  value       = azurerm_route_table.rt_private.id
  description = "The id of the route table associated with the NVA private subnet"
}

output "route_table_name_firewall_private" {
  value       = azurerm_route_table.rt_private.name
  description = "The resource name of the route table associated with the NVA private subnet"
}

output "route_table_id_firewall_public" {
  value       = azurerm_route_table.rt_public.id
  description = "The id of the route table associated with the NVA public subnet"
}

output "route_table_name_firewall_public" {
  value       = azurerm_route_table.rt_public.name
  description = "The resource name of the route table associated with the NVA public subnet"
}

output "subnet_id_gateway" {
  value       = azurerm_subnet.subnet_gateway.id
  description = "The resource id of the GatewaySubnet subnet"
}

output "subnet_id_firewall_private" {
  value       = azurerm_subnet.subnet_firewall_private.id
  description = "The resource id of the NVA private subnet"
}

output "subnet_name_firewall_private" {
  value       = azurerm_subnet.subnet_firewall_private.name
  description = "The resource name of the NVA private subnet"
}

output "subnet_id_firewall_public" {
  value       = azurerm_subnet.subnet_firewall_public.id
  description = "The resource id of the NVA public subnet"
}

output "subnet_name_firewall_public" {
  value       = azurerm_subnet.subnet_firewall_public.name
  description = "The resource name of the NVA private subnet"
}