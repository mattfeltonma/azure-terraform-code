variable "kind" {
  description = "The API the Cosmos DB account should use "
  type        = string
  default     = "GlobalDocumentDB"
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "local_authentication_disabled" {
  description = "Setting this to true disables local authentication for the Cosmos DB account"
  type        = string
  default     = "true"
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type = string
}

variable "offer_type" {
  description = "The offer type of the Cosmos DB account"
  type        = string
  default = "Standard"
}

variable "public_network_access_enabled" {
  description = "Setting this to true allows traffic to Cosmos DB's public endpoint"
  type = string
  default = "false"
}

variable "purpose" {
  description = "The purpose of the resource"
  type = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to provision the resources to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "trusted_services_bypass" {
  description = "The trusted services that should bypass the service firewall"
  type        = string
  default = "None"
}