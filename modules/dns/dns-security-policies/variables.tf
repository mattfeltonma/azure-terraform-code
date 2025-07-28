variable "location" {
  description = "The location of the resource"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type = string
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics workspace to send diagnostic logs to"
  type        = string
}

variable "random_string" {
  description = "A random string to append to the resource name"
  type        = string
}

variable "resource_group_id" {
  description = "The resource group resource id the resources in this template will be deployed to"
  type        = string
}

variable "resource_group_name" {
  description = "The resource group name the resources in this template will be deployed to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vnet_id" {
  description = "The resource id of the virtual network the DNS Security Policy will be linked to"
  type        = string
}

variable "vnet_name" {
  description = "The resource name of the virtual network the DNS Security Policy will be linked to"
  type        = string
}