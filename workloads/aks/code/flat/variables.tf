variable "pod_cidr" {
  description = "The CIDR block that will be used for the overlay network"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "The CIDR block that will be used for Kubernetes services"
  type        = string
  default     = "172.20.0.0/16"
}