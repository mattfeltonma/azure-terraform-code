variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster"
  type        = string
  default = "1.32.6"
}

variable "law_resource_id" {
  description = "The resource id of the Log Analytics Workspace the resources will send logs tos"
  type        = string
}

variable "pod_cidr" {
  description = "The CIDR block that will be used for the overlay network"
  type        = string
  default = "10.244.0.0/16"
}

variable "random_string" {
  description = "The random string to append to the resource name"
  type        = string
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to provision the resources to"
  type        = string
}

variable "service_cidr" {
  description = "The CIDR block that will be used for Kubernetes services"
  type        = string
  default = "172.20.0.0/16"
}

variable "ssh_public_key" {
  description = "The SSH public key to access the AKS nodes"
  type        = string
}

variable "subnet_id_aks" {
  description = "The subnet id that will be used by the overlay CNI"
  type        = string
}

variable "subnet_id_pe" {
  description = "The subnet id to deploy private endpoints for supporting services to"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "node_sku" {
  description = "The SKU of the virtual machines in the AKS node pool"
  type        = string
  default     = "Standard_DS2_v2"
}