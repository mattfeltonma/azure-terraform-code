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

variable "region_prod" {
  description = "The Azure region to deploy production resources to"
  type        = string
}

variable "region_nonprod" {
  description = "The Azure region to deploy non-production resources to"
  type        = string
}

variable "management_group_id" {
  description = "The management scope for the network manager to apply to"
  type        = string
}

variable "network_watcher_name_prefix" {
  description = "The prefix name of the network watcher resource"
  type        = string
  default     = "NetworkWatcher_"
}

variable "network_watcher_resource_group_name" {
  description = "The name of the network watcher resource group"
  type        = string
  default     = "NetworkWatcherRG"
}

variable "vm_sku_size" {
  description = "The SKU to use for virtual machines created"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "tags" {
  description = "The tags to apply to the resources"
  type        = map(string)
}

variable "trusted_ips" {
  description = "The list of trusted IPs to allow through the PaaS service firewalls"
  type        = list(string)
}

variable "user_object_id" {
  description = "The Entra ID user object id to assign the IPAM Pool User role assignment"
  type        = string
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