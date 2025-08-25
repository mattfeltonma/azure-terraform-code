variable "encryption" {
  description = "Indicate whether the AI Foundry account should be encrypted with a provider-managed key or customer-managed key. CMK will create a Key Vault, key, and necessary role assignments"
  type        = string
  default     = "pmk"
  validation {
    condition     = contains(["pmk", "cmk"], var.encryption)
    error_message = "Encryption must be either 'pmk' or 'cmk'."
  }
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The code of the location to provision the resources to"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The resource id of the Log Analytics Workspace to send logs to"
  type        = string
}

# (As of 8/6/2025) Note that user-assigned managed identities are not yet supported for CMK encryption
# so there isn't much use of using an UMI at this time
variable "managed_identity" {
  description = "Indicate whether a user-assigned managed identity or system-assigned managed identity should be used by AI Foundry account"
  type        = string
  validation {
    condition     = contains(["user_assigned", "system_assigned"], var.managed_identity)
    error_message = "Managed identity must be either 'user_assigned' or 'system_assigned'."
  }
  default = "system_assigned"
}

variable "network_default_action" {
  description = "Indicate whether network access is enabled or disabled for the AI Foundry account"
  type        = string
  default     = "Deny"
}

variable "public_network_access" {
  description = "Indicate whether public network access is enabled or disabled for the AI Foundry account"
  type        = string
  default     = "Disabled"
}

variable "private_endpoint" {
  description = "Indicate whether private endpoint is enabled or disabled for the AI Foundry account. This must be set to true when creating an account to support a standard agent"
  type        = bool
  default     = true
}

variable "purpose" {
  description = "The three character purpose of the resource"
  type        = string
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_id" {
  description = "The resource id of the resource group to deploy the resources to"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist. This must be set when creating an account to support a standard agent"
  type        = string
  default = null
}

variable "sub_id_dns" {
  description = "The subscription where the Private DNS Zones are located. This must be set when creating an account to support a standard agent"
  type        = string
  default = null
}

variable "subnet_id_agent" {
  description = "The subnet id to use for Standard Agent vnet injection. This subnet must already be delegated to Microsoft.Apps/environments. This must be set when creating an account to support a standard agent "
  type        = string
  default     = null
}

variable "subnet_id_private_endpoints" {
  description = "The subnet id to deploy the private endpoints to. This must be set when creating an account to support a standard agent"
  type        = string
  default     = null
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "trusted_ip" {
  description = "The IP address where the Terraform code will be run from to allow access to the data plane of Azure Key Vault. This is only necessary for this sample code when using CMK to ensure the machine running the Terraform code can redeploy or destroy"
  type        = string
  default     = null
}

variable "user_object_id" {
  description = "The object id of an Entra ID user that will be granted the Key Vault Administrator role for the Azure Key Vault. This is only necessary for this sample code when using CMK to support the Key Vault module used with this sample code"
  type        = string
  default     = null
}
