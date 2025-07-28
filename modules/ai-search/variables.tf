variable "allowed_ips" {
  description = "IP addresses to allow through the service firewall"
  type        = list(object({
    value = string
  }))
  default     = []
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
  type = string
}

variable "public_network_access" {
  description = "Block all public access to the service. This must be set to enabled if you are doing IP-based exceptions"
  type = string
  default = "disabled"
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

variable "resource_group_id" {
  description = "The id of the resource group to deploy the resources to"
  type        = string
}

variable "sku" {
  description = "The SKU of the Azure Bastion instance"
  type        = string
  default = "standard"
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