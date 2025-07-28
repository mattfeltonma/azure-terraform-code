output "id" {
  value       = azapi_resource.ai_foundry_project.id
  description = "The resource id of the AI Services instance"
}

output "managed_identity_principal_id" {
  value       = azapi_resource.ai_foundry_project.output.identity.principalId
  description = "The principal id of the managed identity of the AI Service instance"
}

output "name" {
  value       = azapi_resource.ai_foundry_project.name
  description = "The name of the AI Service instance"
}

