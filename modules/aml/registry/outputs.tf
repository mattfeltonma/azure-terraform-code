output "name" {
  value       = azapi_resource.registry.name
  description = "The name of the Azure Machine Learning Registry"
}

output "id" {
  value       = azapi_resource.registry.id
  description = "The resource id of the Azure Machine Learning Registry"
}