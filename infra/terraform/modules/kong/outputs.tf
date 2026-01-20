# Kong Module Outputs

output "namespace" {
  description = "Kubernetes namespace where Kong is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.kong.name
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.kong.status
}

output "service_account_name" {
  description = "Name of the Kong service account"
  value       = var.service_account_name
}

output "config_map_name" {
  description = "Name of the Kong configuration ConfigMap"
  value       = kubernetes_config_map.kong_config.metadata[0].name
}

output "plugin_config_maps" {
  description = "Names of custom plugin ConfigMaps"
  value       = { for k, v in kubernetes_config_map.kong_plugins : k => v.metadata[0].name }
}

output "proxy_service_name" {
  description = "Name of the Kong proxy service"
  value       = "${var.release_name}-kong-proxy"
}

output "admin_service_name" {
  description = "Name of the Kong admin service (if enabled)"
  value       = var.enable_admin_api ? "${var.release_name}-kong-admin" : null
}

output "ingress_class" {
  description = "Kong ingress class name"
  value       = var.ingress_class
}

output "helm_values_summary" {
  description = "Summary of key Helm values applied"
  value = {
    chart_version      = var.chart_version
    kong_image         = "${var.kong_image_repository}:${var.kong_image_tag}"
    ingress_controller = var.enable_ingress_controller
    autoscaling        = var.enable_autoscaling
    service_monitor    = var.enable_service_monitor
    admin_api          = var.enable_admin_api
    irsa_enabled       = var.service_account_role_arn != ""
  }
}
