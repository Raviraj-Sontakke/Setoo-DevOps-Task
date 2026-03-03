variable "location" {
  type    = string
  default = "eastus"
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "user_node_min_count" {
  type    = number
  default = 2
}

variable "user_node_max_count" {
  type    = number
  default = 8
}
