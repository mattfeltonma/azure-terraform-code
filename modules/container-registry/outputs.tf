output "name" {
  value       = azurerm_container_registry.acr.name
  description = "The name of the Azure Container Registry"
}

output "id" {
  value       = azurerm_container_registry.acr.id
  description = "The resource id of the Azure Container Registry"
}