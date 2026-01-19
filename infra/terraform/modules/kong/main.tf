# Kong Module
# Deploys Kong Gateway on EKS using Helm
#
# Features:
# - Kong Ingress Controller with DB-less mode
# - Custom plugins mounted from ConfigMaps
# - IRSA integration for Bedrock access
# - Prometheus metrics enabled

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "kong" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "kong"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Kong Configuration ConfigMap
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "kong_config" {
  metadata {
    name      = "kong-declarative-config"
    namespace = var.namespace
  }

  data = {
    "kong.yaml" = var.kong_config_yaml
  }

  depends_on = [kubernetes_namespace.kong]
}

# -----------------------------------------------------------------------------
# Custom Plugins ConfigMap
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "kong_plugins" {
  for_each = var.custom_plugins

  metadata {
    name      = "kong-plugin-${each.key}"
    namespace = var.namespace
  }

  data = each.value

  depends_on = [kubernetes_namespace.kong]
}

# -----------------------------------------------------------------------------
# Kong Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "kong" {
  name       = var.release_name
  repository = "https://charts.konghq.com"
  chart      = "kong"
  version    = var.chart_version
  namespace  = var.namespace

  # Wait for deployment to be ready
  wait    = true
  timeout = var.helm_timeout

  # Core configuration
  values = [
    yamlencode({
      # DB-less mode
      env = {
        database = "off"
        declarative_config = "/kong_dbless/kong.yaml"
        plugins = join(",", concat(
          ["bundled"],
          keys(var.custom_plugins)
        ))
        # Bedrock proxy settings
        nginx_proxy_proxy_buffer_size    = "128k"
        nginx_proxy_proxy_buffers        = "4 256k"
        nginx_proxy_proxy_busy_buffers_size = "256k"
      }

      # Image configuration
      image = {
        repository = var.kong_image_repository
        tag        = var.kong_image_tag
      }

      # Service Account with IRSA
      serviceAccount = {
        create = true
        name   = var.service_account_name
        annotations = var.service_account_role_arn != "" ? {
          "eks.amazonaws.com/role-arn" = var.service_account_role_arn
        } : {}
      }

      # Ingress Controller
      ingressController = {
        enabled            = var.enable_ingress_controller
        installCRDs        = var.install_crds
        ingressClass       = var.ingress_class
        watchNamespaces    = var.watch_namespaces
      }

      # Proxy service
      proxy = {
        enabled = true
        type    = var.proxy_service_type
        annotations = var.proxy_annotations
        http = {
          enabled     = true
          containerPort = 8000
          servicePort = 80
        }
        tls = {
          enabled     = var.enable_tls
          containerPort = 8443
          servicePort = 443
        }
      }

      # Admin API (disabled in production)
      admin = {
        enabled = var.enable_admin_api
        type    = "ClusterIP"
        http = {
          enabled = var.enable_admin_api
        }
      }

      # Status endpoint for health checks
      status = {
        enabled = true
        http = {
          enabled = true
        }
      }

      # Prometheus metrics
      serviceMonitor = {
        enabled   = var.enable_service_monitor
        namespace = var.namespace
        labels    = var.service_monitor_labels
      }

      # Resources
      resources = var.resources

      # Autoscaling
      autoscaling = var.enable_autoscaling ? {
        enabled     = true
        minReplicas = var.min_replicas
        maxReplicas = var.max_replicas
        metrics = [{
          type = "Resource"
          resource = {
            name = "cpu"
            target = {
              type               = "Utilization"
              averageUtilization = var.target_cpu_utilization
            }
          }
        }]
      } : {
        enabled = false
      }

      # Pod disruption budget
      podDisruptionBudget = var.enable_pdb ? {
        enabled        = true
        minAvailable   = var.pdb_min_available
      } : {
        enabled = false
      }

      # Security context
      securityContext = {
        runAsUser  = 1000
        runAsGroup = 1000
        fsGroup    = 1000
      }

      # Declarative config volume
      deployment = {
        kong = {
          enabled = true
        }
      }

      # Custom plugin volumes
      extraConfigMaps = concat(
        [
          {
            name      = kubernetes_config_map.kong_config.metadata[0].name
            mountPath = "/kong_dbless"
          }
        ],
        [
          for name, _ in var.custom_plugins : {
            name      = kubernetes_config_map.kong_plugins[name].metadata[0].name
            mountPath = "/opt/kong/plugins/${name}"
          }
        ]
      )
    }),
    var.extra_values
  ]

  depends_on = [
    kubernetes_namespace.kong,
    kubernetes_config_map.kong_config,
    kubernetes_config_map.kong_plugins
  ]
}

# -----------------------------------------------------------------------------
# Network Policy (optional)
# -----------------------------------------------------------------------------

resource "kubernetes_network_policy" "kong" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "kong-network-policy"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "kong"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress on proxy ports
    ingress {
      ports {
        protocol = "TCP"
        port     = 8000
      }
      ports {
        protocol = "TCP"
        port     = 8443
      }
    }

    # Allow egress to Bedrock endpoints
    egress {
      ports {
        protocol = "TCP"
        port     = 443
      }
    }

    # Allow egress to Kubernetes DNS
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = 53
      }
    }
  }

  depends_on = [kubernetes_namespace.kong]
}
