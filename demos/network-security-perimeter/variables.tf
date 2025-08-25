variable "address_space_vnet" {
  description = "The address space assigned to the virtual network created as part of this demo. It should be /25 or larger."
  type        = string
  default     = "10.0.0.0/25"
}

variable "admin_username" {
  description = "The username of the local administration on the virtual machines"
  type        = string
}

variable "admin_password" {
  description = "The password of the local administration on the virtual machines"
  type        = string
  sensitive   = true
}

variable "key_vault_admin_object_id" {
  description = "The object id of the user or service principal to assign the Key Vault Administrator role to"
  type        = string
}

variable "location" {
  description = "The location to deploy resources to"
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

variable "trusted_ip" {
  description = "The IP address of the Terraform server"
  type        = string
}