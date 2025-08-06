variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to use for diagnostics"
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

variable "managed_identity" {
  description = "Indicate whether a user-assigned managed identity or system-assigned managed identity should be used by hub"
  type        = string
  validation {
    condition     = contains(["user_assigned", "system_assigned"], var.managed_identity)
    error_message = "Managed identity must be either 'user_assigned' or 'system_assigned'."
  }
  default     = "system_assigned"
}

variable "object_id_manage_resource_group" {
  description = "The object IDs of the Entra ID security principals that should have the Azure AI Administrator role over the AML Registry managed resource group"
  type        = list(string)
  default     = []
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}