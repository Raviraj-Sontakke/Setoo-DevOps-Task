locals {
  env    = "stage"
  prefix = "raviraj"

  tags = {
    environment = local.env
    project     = "setoo-devops"
    managed_by  = "terraform"
  }
}

module "monitoring" {
  source = "../../modules/monitoring"

  workspace_name      = "${local.prefix}-logs-${local.env}"
  resource_group_name = module.networking.resource_group_name
  location            = var.location
  retention_in_days   = 60
  tags                = local.tags
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name    = "${local.prefix}-rg-${local.env}"
  location               = var.location
  vnet_name              = "${local.prefix}-vnet-${local.env}"
  vnet_address_space     = ["10.1.0.0/8"]
  aks_subnet_prefixes    = ["10.241.0.0/16"]
  app_gw_subnet_prefixes = ["10.242.0.0/24"]
  tags                   = local.tags
}

module "storage" {
  source = "../../modules/storage"

  storage_account_name = "${local.prefix}storagestage"
  resource_group_name  = module.networking.resource_group_name
  location             = var.location
  tags                 = local.tags
}

module "aks" {
  source = "../../modules/aks"

  cluster_name               = "${local.prefix}-aks-${local.env}"
  location                   = var.location
  resource_group_name        = module.networking.resource_group_name
  dns_prefix                 = "${local.prefix}-${local.env}"
  subnet_id                  = module.networking.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.workspace_id
  system_node_count          = var.system_node_count
  user_node_min_count        = var.user_node_min_count
  user_node_max_count        = var.user_node_max_count
  tags                       = local.tags
}

module "acr" {
  source = "../../modules/acr"

  acr_name            = "${local.prefix}acrstage"
  resource_group_name = module.networking.resource_group_name
  location            = var.location
  sku                 = "Standard"
  aks_principal_id    = module.aks.kubelet_identity_object_id
  tags                = local.tags
}
