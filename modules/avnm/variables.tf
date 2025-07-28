variable "address_space_onpremises" {
  description = "The address space used on-premises"
  type        = string
}
 
variable "address_space_cloud" {
  description = "The address space in the cloud"
  type        = string
}

variable "address_space_azure_prod" {
  description = "The address space in production Azure environment"
  type        = string
}

variable "address_space_azure_nonprod" {
  description = "The address space in the non-production Azure environment"
  type        = string
}

variable "admin_username" {
  description = "The username to assign to the virtual machine"
  type        = string
}

variable "admin_password" {
  description = "The password to assign to the virtual machine"
  type        = string
  sensitive   = true
}

variable "key_vault_admin" {
  description = "The object id of the user or service principal to assign the Key Vault Administrator role to"
  type        = string

}

variable "location_prod" {
  description = "The location to deploy production resources to"
  type        = string
}

variable "location_nonprod" {
  description = "The location to deploy non-production resources to"
  type        = string
  default = null
}

variable "management_group_id" {
  description = "The management scope for the network manager to apply to"
  type        = string
}

variable "network_watcher_name" {
  description = "The name of the network watcher resource"
  type        = string
  default     = "NetworkWatcher_"
}

variable "network_watcher_resource_group_name" {
  description = "The name of the network watcher resource group"
  type        = string
  default     = "NetworkWatcherRG"
}

variable "sku_vm_size" {
  description = "The SKU to use for virtual machines created"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "tags" {
  description = "The tags to apply to the resources"
  type        = map(string)
}

variable "user_object_id" {
  description = "The Entra ID user object id to assign the IPAM Pool User role assignment"
  type        = string
}