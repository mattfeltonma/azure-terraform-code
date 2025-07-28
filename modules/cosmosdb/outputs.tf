output "endpoint" {
  value       = azurerm_cosmosdb_account.cosmosdb.endpoint
  description = "The endpoint of the CosmosDB instance"
}

output "id" {
  value       = azurerm_cosmosdb_account.cosmosdb.id
  description = "The resource id of the CosmosDB instance"
}

output "location" {
  value       = azurerm_cosmosdb_account.cosmosdb.location
  description = "The location of the CosmosDB instance"
}

output "name" {
  value       = azurerm_cosmosdb_account.cosmosdb.name
  description = "The name of the CosmosDB instance"
}

