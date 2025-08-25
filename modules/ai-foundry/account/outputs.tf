output "ai_search_id" {
  value       = length(module.ai_search) > 0 ? module.ai_search[0].id : null
  description = "The resource id of the AI Search instance"
}

output "ai_search_name" {
  value       = length(module.ai_search) > 0 ? module.ai_search[0].name : null
  description = "The name of the AI Search instance"
}

output "foundry_account_id" {
  value       = azapi_resource.ai_foundry_account.id
  description = "The resource id of the AI Foundry account"
}

output "foundry_account_name" {
  value       = azapi_resource.ai_foundry_account.name
  description = "The name of the AI Foundry account"
}

output "foundry_project_id" {
  value       = length(module.ai_foundry_project_sample) > 0 ? module.ai_foundry_project_sample[0].id : null
  description = "The resource id of the AI Foundry project"
}

output "storage_account_id" {
  value       = length(module.storage_account) > 0 ? module.storage_account[0].id : null
  description = "The resource id of the storage account"
}

output "storage_account_name" {
  value       = length(module.storage_account) > 0 ? module.storage_account[0].name : null
  description = "The name of the storage account"
}

output "managed_identity_principal_id_ai_search" {
  value       = length(module.ai_search) > 0 ? module.ai_search[0].managed_identity_principal_id : null
  description = "The principal id of the managed identity associated with the AI Search instance"
}

output "managed_identity_principal_id_foundry_project" {
  value       = length(module.ai_foundry_project_sample) > 0 ? module.ai_foundry_project_sample[0].managed_identity_principal_id : null
  description = "The principal id of the managed identity associated with the sample AI Foundry project"
}



