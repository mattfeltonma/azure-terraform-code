variable "address_space_vnet" {
  description = "The address space for the virtual network."
  type        = list(string)
}

variable "bastion" {
  description = "Whether to deploy a bastion host."
  type        = bool
  default     = false
}

variable "dns_servers" {
  description = "The DNS servers for the virtual network."
  type        = list(string)
  default = [
    "168.63.129.16"
  ]
}

variable "environment" {
  description = "The environment to include in resource names."
  type        = string
}

variable "law_region" {
  description = "The region of the Log Analytics Workspace that will be used for Traffic Analytics"
  type        = string
}

variable "law_resource_id" {
  description = "The resource ID of the Log Analytics Workspace that will be used for Traffic Analytics"
  type        = string
}

variable "law_workspace_id" {
  description = "The workspace ID of the Log Analytics Workspace that will be used for Traffic Analytics"
  type        = string
}

variable "random_string" {
  description = "A random string to include in resource names."
  type        = string
}

variable "region" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "region_code" {
  description = "The region code to include in the resource name."
  type        = string
}

variable "resource_group_name_network_watcher" {
  description = "The name of the resource group where Network Watcher resources have been deployed to."
  type        = string
}

variable "resource_group_name_workload" {
  description = "The name of the resource group where workload resources will be deployed."
  type        = string
}

variable "storage_account_vnet_flow_logs" {
  description = "The ID of the storage account for VNet flow logs."
  type        = string
}

variable "nva_asn" {
  description = "The ASN for the Network Virtual Appliance."
  type        = number
  default = 65001
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "tags_vnet" {
  description = "Additional tags to add to virtual network to be used with Azure Virtual Network Manager"
  type        = map(string)
}

variable "vm_admin_username" {
  description = "The admin username for the virtual machine."
  type        = string
}

variable "vm_admin_password" {
  description = "The admin password for the virtual machine."
  type        = string
  sensitive   = true
}

variable "vm_sku_size" {
  description = "The SKU size for the virtual machine."
  type        = string
  default = "Standard_D2s_v3"
}