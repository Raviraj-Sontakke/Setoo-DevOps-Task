variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/8"]
}

variable "aks_subnet_prefixes" {
  type    = list(string)
  default = ["10.240.0.0/16"]
}

variable "app_gw_subnet_prefixes" {
  type    = list(string)
  default = ["10.241.0.0/24"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
