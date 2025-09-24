variable "address_space_vnet" {
  description = "The address space assigned to the virtual network created as part of this demo. It should be /22 or larger."
  type        = string
  default     = "10.0.0.0/22"
}

variable "vm_admin_username" {
  description = "The username of the local administration on the virtual machines"
  type        = string
}

variable "vm_admin_password" {
  description = "The password of the local administration on the virtual machines"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The Azure region to deploy resources to"
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

variable "object_id_user" {
  description = "The object ID that will be assigned permissions at the data plane of the resources created in this demo"
  type        = string
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
  description = "The trusted IP to allow through the service firewalls"
  type        = string
}