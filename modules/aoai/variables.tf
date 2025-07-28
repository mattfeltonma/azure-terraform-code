variable "allowed_fqdn_list" {
  description = "The list of domain names the AI Service should be allowed to access"
  type        = list(string)
  default = []
}
 
variable "allowed_ips" {
  description = "The list of IP addresses to allow through the service firewall for the Azure OpenAI Service"
  type        = list(string)
  default = []
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

variable "network_access_default" {
  description = "The default service firewall settings for the Azure OpenAI Service"
  type        = string
  default = "Deny"
}
 
variable "public_network_access" {
  description = "Block all public access to the service. This must be set to enabled if you are doing IP-based exceptions"
  type = bool
  default = false
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
