variable "address_space_azure" {
  description = "The address space used in the Azure environment"
  type        = string
}

variable "address_space_onpremises" {
  description = "The address space used on-premises"
  type        = string
}

variable "address_space_vnet" {
  description = "The address space to assign to the virtual network"
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

variable "asn_router" {
  description = "The ASN to assign to the NVAs"
  type        = string
}

variable "dce_id" {
  description = "The resource id of the Data Collection Endpoint"
  type        = string
}

variable "dcr_id_linux" {
  description = "The resource id of the Data Collection Rule for Linux"
  type        = string
}

variable "dns_servers" {
  description = "The DNS Servers to configure for the virtual network"
  type        = list(string)
  default     = ["168.63.129.16"]
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type        = string
}

variable "network_watcher_name" {
  description = "The name of the Network Watcher to send vnet flow logs to"
  type        = string
}

variable "network_watcher_resource_group_name" {
  description = "The resource group name the Network Watcher is deployed to that will receive vnet flow logs"
  type        = string
}

variable "nva_count" {
  description = "The number of NVAs to deploy"
  type        = number
  default     = 2
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the resources to"
  type        = string
}

variable "storage_account_id_flow_logs" {
  description = "The resource id of the storage account to send virtual network flow logs to"
  type        = string
}

variable "subnet_cidr_firewall_private" {
  description = "The address space to assign to the subnet used for the private NIC for the NVA"
  type        = string
}

variable "subnet_cidr_firewall_public" {
  description = "The address space to assign to the subnet used for the public NIC for the NVA"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "traffic_analytics_workspace_guid" {
  description = "The workspace guid to send traffic analytics to"
  type        = string
}

variable "traffic_analytics_workspace_location" {
  description = "The workspace region to send traffic analytics to"
  type        = string
}

variable "traffic_analytics_workspace_id" {
  description = "The workspace resource id send traffic analytics to"
  type        = string
}

variable "vm_size_nva" {
  description = "The size of the virtual machine to deploy"
  type        = string
}

variable "vnet_cidr_ss" {
  description = "The address space assigned to the Shared Services virtual network"
  type        = string
}

variable "vnet_cidr_wl1" {
  description = "The address space assigned to the Workload 1 virtual network"
  type        = string
}

variable "vnet_cidr_wl2" {
  description = "The address space assigned to the Workload 2 virtual network"
  type        = string
}

variable "vwan_hub_id" {
  description = "The resource id of the VWAN Hub to connect the transit virtual network to"
  type        = string
}

variable "vwan_associated_route_table_id" {
  description = "The resource id of the VWAN Hub route table to associate to the virtual network connection"
  type        = string
}

variable "vwan_propagate_route_table_ids" {
  description = "The resource ids of the VWAN Hub route tables the virtual network connection should propagate its routes to"
  type        = list(string)
}

variable "vwan_propagate_route_labels" {
  description = "The labels the virtual network connection should propagate to the VWAN Hub"
  type        = list(string)
}

variable "vwan_propagate_static_routes" {
  description = "The static routes the virtual network connection should propagate to the VWAN Hub"
  type        = bool
}
