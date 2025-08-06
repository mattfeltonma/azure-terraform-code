output "name" {
  value       = azurerm_key_vault.kv.name
  description = "The name of the Azure Key Vault instance"
}

output "id" {
  value       = azurerm_key_vault.kv.id
  description = "The resource id of the Azure Key Vault instance"
}

output "vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "The URI of the Azure Key Vault instance"
}