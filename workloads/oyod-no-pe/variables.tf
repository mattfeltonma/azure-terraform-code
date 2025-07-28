variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

variable "location_code" {
  description = "The location code to append to the resource name"
  type        = string
}

variable "purpose" {
  description = "The three character purpose of the resource"
  type        = string
}

variable "tags" {
  description = "The tags to apply to the resource"
  type        = map(string)
}

variable "your_ip" {
  description = "The IP address to allow through the PaaS firewalls"
  type        = string
}

variable "user_object_id" {
  description = "The object id of the user who will manage the Azure Machine Learning Workspace"
  type        = string
}
