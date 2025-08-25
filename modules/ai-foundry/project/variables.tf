variable "ai_foundry_account_id" {
  description = "The resource id of the AI Foundry resource the project will be created in"
  type        = string
}

variable "aisearch_name" {
  description = "The resource name of the AI Search instance that will be used to store vector data"
  type        = string
}

variable "aisearch_resource_id" {
  description = "The resource id of the AI Search instance that will be used to store vector data"
  type        = string
}

variable "application_insights_connection_string" {
  description = "The connection string of the Application Insights instance that will be used to store trace data"
  type        = string
  sensitive = true
}

variable "application_insights_name" {
  description = "The resource name of the Application Insights instance that will be used to store trace data"
  type        = string
}

variable "application_insights_resource_id" {
  description = "The resource id of the Application Insights instance that will be used to store trace data"
  type        = string
}

variable "bing_grounding_search_name" {
  description = "The resource name of the Bing Search instance that will be used for grounding search"
  type        = string
}

variable "bing_grounding_search_resource_id" {
  description = "The resource id of the Bing Search instance that will be used for grounding search"
  type        = string
}

variable "bing_grounding_search_subscription_key" {
  description = "The subscription key for the Bing Search instance that will be used for grounding search"
  type        = string
  sensitive = true
}

variable "cosmosdb_document_endpoint" {
  description = "The CosmosDB document endpoint the agent will store conversation history in"
  type        = string
}

variable "cosmosdb_name" {
  description = "The resource name of the CosmosDB account"
  type        = string
}

variable "cosmosdb_resource_id" {
  description = "The resource id of the CosmosDB account the agent will store conversation history in"
  type        = string
}

variable "location" {
  description = "The location to deploy the AI Foundry project to. Assumes all supporting resources are in same location"
  type        = string
}

variable "project_description" {
  description = "The description of the AI Foundry project"
  type = string
}

variable "project_name" {
  description = "The name of the AI Foundry project"
  type = string
}

variable "resource_group_name" {
  description = "The name of the resource group to create the AI Foundry project in"
  type        = string
}

variable "resource_group_id" {
  description = "The resource id of the resource group to create the AI Foundry project in"
  type        = string
}

variable "storage_account_blob_endpoint" {
  description = "The blob endpoint of the Storage Account the agent will use"
  type        = string
}

variable "storage_account_name" {
  description = "The resource name of the Storage Account the agent will use"
  type        = string
}

variable "storage_account_resource_id" {
  description = "The resource id of the Storage Account the agent will use"
  type        = string
}

