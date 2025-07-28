
variable "bypass_network_rules" {
  description = "Determines whether trusted Azure services are allowed to bypass the service firewall. Set to AzureServices or None"
  type        = string
  default = "AzureServices"
}

variable "default_network_action" {
  description = "The default network action for the resource. Set to either Allow or Deny"
  type        = string
  default = "Deny"
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type        = string
}

variable "public_network_access_enabled" {
  description = "The three character purpose of the resource"
  type        = bool
  default     = false
}

variable "purpose" {
  description = "The three character purpose of the resource"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}
