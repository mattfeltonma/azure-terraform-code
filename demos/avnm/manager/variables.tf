variable "description" {
  description = "The description of the virtual network manager instance"
  type        = string
}

variable "configurations_supported" {
  description = "The configurations this supports. This can be SecurityAdmin, Connectivity, or both"
  type        = list(string)
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "management_scope" {
  description = "The scope of subscriptions the virtual network manager can manage. This either a collection of subscription ids or management group ids."
  type        = object({
    management_group_ids = optional(list(string))
    subscription_ids     = optional(list(string))
  })
}

variable "name" {
  description = "The name of the virtual network"
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
