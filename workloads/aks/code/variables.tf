variable "address_space_vnet" {
  description = "The address space for the virtual network. This address space should be a mininum of /22"
  type        = string
  default     = "10.32.0.0/22"

  validation {
    condition     = tonumber(split("/", var.address_space_vnet)[1]) <= 22
    error_message = "The address space must be /22 or larger. Current value has a prefix of /${split("/", var.address_space_vnet)[1]}."
  }
}

variable "cni" {
  description = "The Kubernetes CNI to deploy to the AKS cluster. This must be set to overlay (Azure CNI Overlay) or flat (Azure CNI)"
  type        = string
  default = "overlay"


  validation {
    condition     = var.cni == "overlay" || var.cni == "flat"
    error_message = "The CNI must be either 'overlay' or 'flat'. Current value is '${var.cni}'."
  }
}

variable "dns_servers" {
  description = "The DNS servers to set for the virtual network"
  type        = list(string)
  default = [
    "168.63.129.16"
  ]
}

variable "fw_private_ip" {
  description = "The private IP address of the firewall. This must be set if standalone is set to false"
  type        = string
  default     = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.fw_private_ip != null)
    error_message = "The fw_private_ip must be provided when standalone is set to false."
  }
}

variable "hub_name" {
  description = "The name of the hub virtual network. This must be set if standalone is set to false"
  type        = string
  default     = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.hub_name != null)
    error_message = "The hub_name must be provided when standalone is set to false."
  }
}

variable "hub_resource_group_name" {
  description = "The name of the resource group where the hub virtual network exists. This must be set if standalone is set to false"
  type        = string
  default     = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.hub_resource_group_name != null)
    error_message = "The hub_resource_group_name must be provided when standalone is set to false."
  }
}

variable "hub_vnet_id" {
  description = "The ID of the hub virtual network. This must be set if standalone is set to false"
  type        = string
  default     = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.hub_vnet_id != null)
    error_message = "The hub_vnet_id must be provided when standalone is set to false."
  }
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.32.6"
}

variable "pod_cidr" {
  description = "The CIDR block that will be used for the overlay network. This "
  type        = string
  default     = "10.244.0.0/16"
}

variable "region" {
  description = "The name of the Azure region to provision the resources to"
  type        = string
}

variable "region_code" {
  description = "The code of the Azure region to provision the resources to"
  type        = string
}

variable "random_string" {
  description = "The random three digit alphanumeric string to append to resource names"
  type        = string
}

variable "resource_group_name_dns" {
  description = "The name of the resource group where the Private DNS Zones exist"
  type        = string
  default = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.resource_group_name_dns != null)
    error_message = "The resource_group_name_dns must be provided when standalone is set to false."
  }
}

variable "service_cidr" {
  description = "The CIDR block that will be used for Kubernetes services"
  type        = string
  default     = "172.20.0.0/16"
}

variable "standalone" {
  description = "Specify whether this is a standalone deployment. If set to false, it must be peered to a hub virtual network."
  type        = bool
  default     = true
}

variable "sub_id_dns" {
  description = "The subscription where the Private DNS Zones are located"
  type        = string
  default = null

  validation {
    condition     = var.standalone == true || (var.standalone == false && var.sub_id_dns != null)
    error_message = "The sub_id_dns must be provided when standalone is set to false."
  }
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "vm_admin_password" {
  description = "The password to set for the bastion virtual machine. This must be set if standalone is set to false"
  type        = string
  sensitive   = true
  default     = null
}

variable "vm_sku" {
  description = "The SKU of the virtual machines in the AKS node pool and the tools virtual machine"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "ssh_key_name" {
  description = "The name of the SSH key resource in Azure"
  type        = string
}

variable "ssh_key_resource_group" {
  description = "The resource group containing the SSH key resource"
  type        = string
}
