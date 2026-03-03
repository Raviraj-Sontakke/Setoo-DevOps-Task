output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "resource_group_name" {
  value = module.networking.resource_group_name
}
