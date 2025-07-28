variable "key_vault_id" {
  description = "The Key Vault resource id the API Management instance will have access to"
  type        = string
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace to send diagnostic logs to"
  type        = string
}

variable "primary_location" {
  description = "The name of the location to provision the primary gateway to"
  type        = string
}

variable "primary_location_code" {
  description = "The location code of the primary region to append to the resource name"
  type = string
}

variable "publisher_name" {
  description = "The name of the publisher to display in the Azure API Management instance"
  type = string
}

variable "publisher_email" {
  description = "The email address of the publisher to display in the Azure API Management instance"
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

variable "secondary_location" {
  description = "The secondary location to deploy an API Gateway in the multi-region configuration"
  type        = string
  default = null
}

variable "secondary_location_code" {
  description = "The location code of the secondary region to append to the resource name"
  type        = string
  default = null
}

variable "sku" {
  description = "The APIM SKU to use for the API Management instance"
  type        = string
  default = "Developer_1"
}

variable "subnet_id_primary" {
  description = "The subnet id to deploy the primary API Gateway to"
  type        = string
}

variable "subnet_id_secondary" {
  description = "The subnet id to deploy the primary API Gateway to"
  type        = string
  default = null
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}
