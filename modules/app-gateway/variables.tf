variable "key_vault_id" {
  description = "The Key Vault resource id the API Management instance will have access to"
  type        = string
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "location" {
  description = "The name of the location to provision the resource to"
  type        = string
}

variable "location_code" {
  description = "The location code of the region to append to the resource name"
  type = string
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

variable "sku" {
  description = "The SKU of the Application Gateway to deploy"
  type        = string
  default = "Standard_v2"
}

variable "subnet_id" {
  description = "The subnet id to deploy the Application Gateway to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}
