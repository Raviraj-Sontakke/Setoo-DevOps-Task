variable "acr_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  type    = string
  default = "Standard"
}

variable "aks_principal_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
