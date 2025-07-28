output "id" {
  value       = azapi_resource.ai_search.id
  description = "The resource id of the AI Search instance"
}

output "managed_identity_principal_id" {
  value       = azapi_resource.ai_search.output.identity.principalId
  description = "The principal id of the managed identity of the AI Search instance"
}

output "location" {
  value       = azapi_resource.ai_search.location
  description = "The location of the AI Search instance"
}

output "name" {
  value       = azapi_resource.ai_search.name
  description = "The name of the AI Search instance"
}

