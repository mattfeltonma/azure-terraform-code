output "name" {
  value       = azurerm_application_gateway.agw.name
  description = "The name of the Application Gateway instance"
}

output "id" {
  value       = azurerm_application_gateway.agw.id
  description = "The id of the Application Gateway instance"
}