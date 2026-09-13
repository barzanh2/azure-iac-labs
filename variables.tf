variable "resource_group_location" {
  type        = string
  default     = "australiasoutheast"
  description = "Azure region for all resources."
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "rg"
  description = "Prefix combined with a random pet name for a unique resource group name."
}

variable "environment" {
  type        = string
  description = "Environment name, used in resource naming and tags."
}

variable "owner" {
  type        = string
  default     = "ariyo"
  description = "Owner tag applied to every resource."
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the virtual network."
}

variable "workload_subnet_prefix" {
  type        = string
  description = "CIDR for the workload subnet."
}

variable "mgmt_subnet_prefix" {
  type        = string
  description = "CIDR for the management subnet."
}

variable "allowed_ssh_source_ip" {
  type        = string
  description = "Single public IP permitted to reach the management subnet over SSH."
}
