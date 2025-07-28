variable "allow_blob_public_access" {
  description = "Allow public access of blob containers if specified on the container"
  type = bool
  default = false
}

variable "allowed_ips" {
  description = "The list of IP addresses to allow through the service firewall for the storage account"
  type = list(string)
  default = []
}

variable "cors_rules" {
  description = "The list of CORS rules to apply to the blob service of the storage account"
  type = list(object({
    allowed_origins     = list(string)
    allowed_methods     = list(string)
    allowed_headers = list(string)
    max_age_in_seconds = number
    exposed_headers = list(string)
  }))
  default = [
  ]
}

variable "key_based_authentication" {
  description = "Storage Account should support key-based authentication"
  type = bool
  default = false
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace"
  type = string
}

variable "location" {
  description = "The name of the location to deploy the resources to"
  type = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type = string
}

variable "resource_access" {
  description = "The list of resource access rules to apply to the storage account"
  type = list(object({
    endpoint_resource_id         = string
    endpoint_tenant_id           = optional(string)
  }))
  default = []
}

variable "purpose" {
  description = "The three-letter purpose code for the resource"
  type = string
}

variable "network_access_default" {
  description = "The default network access to apply to the storage account"
  type = string
  default = "Deny"
}

variable "network_trusted_services_bypass" {
  description = "The trusted services to bypass the network"
  type = list(string)
  # For Azure Storage this can be set to AzureServices, Logging, Metrics
  # By default trusted services are not bypassed
  default = ["None"]
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type = string
}

variable "storage_account_kind" {
  description = "The kind of storage account to create"
  type = string
  default = "StorageV2"
}

variable "storage_account_replication_type" {
  description = "The replication type to apply to the storage account"
  type = string
  default = "LRS"
}

variable "storage_account_tier" {
  description = "The tier of the storage account to create"
  type = string
  default = "Standard"
}

variable "tags" {
  description = "The tags to apply to the resource"
  type = map(string)
}