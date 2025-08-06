output "current_client_id" {
  value = data.azurerm_client_config.identity_config.client_id
}

output "current_object_id" {
  value = data.azurerm_client_config.identity_config.object_id
}