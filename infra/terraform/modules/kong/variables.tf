# Kong Module Variables

# -----------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------

variable "namespace" {
  description = "Kubernetes namespace for Kong"
  type        = string
  default     = "kong"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "kong"
}

variable "chart_version" {
  description = "Kong Helm chart version"
  type        = string
  default     = "2.33.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

# -----------------------------------------------------------------------------
# Kong Image
# -----------------------------------------------------------------------------

variable "kong_image_repository" {
  description = "Kong container image repository"
  type        = string
  default     = "kong"
}

variable "kong_image_tag" {
  description = "Kong container image tag"
  type        = string
  default     = "3.6"
}

# -----------------------------------------------------------------------------
# Service Account
# -----------------------------------------------------------------------------

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "kong"
}

variable "service_account_role_arn" {
  description = "IAM role ARN for IRSA (leave empty to disable)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Kong Configuration
# -----------------------------------------------------------------------------

variable "kong_config_yaml" {
  description = "Kong declarative configuration YAML content"
  type        = string
}

variable "custom_plugins" {
  description = "Map of custom plugin names to their file contents"
  type        = map(map(string))
  default     = {}
  # Example:
  # {
  #   "bedrock-proxy" = {
  #     "handler.lua" = "..."
  #     "schema.lua"  = "..."
  #   }
  # }
}

# -----------------------------------------------------------------------------
# Ingress Controller
# -----------------------------------------------------------------------------

variable "enable_ingress_controller" {
  description = "Enable Kong Ingress Controller"
  type        = bool
  default     = true
}

variable "install_crds" {
  description = "Install Kong CRDs"
  type        = bool
  default     = true
}

variable "ingress_class" {
  description = "Ingress class name"
  type        = string
  default     = "kong"
}

variable "watch_namespaces" {
  description = "List of namespaces to watch (empty for all)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Proxy Service
# -----------------------------------------------------------------------------

variable "proxy_service_type" {
  description = "Service type for Kong proxy"
  type        = string
  default     = "LoadBalancer"
}

variable "proxy_annotations" {
  description = "Annotations for proxy service (e.g., for AWS ALB)"
  type        = map(string)
  default = {
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
  }
}

variable "enable_tls" {
  description = "Enable TLS on proxy"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Admin API
# -----------------------------------------------------------------------------

variable "enable_admin_api" {
  description = "Enable Kong Admin API (should be disabled in production)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

variable "enable_service_monitor" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "service_monitor_labels" {
  description = "Labels for ServiceMonitor"
  type        = map(string)
  default = {
    "release" = "prometheus"
  }
}

# -----------------------------------------------------------------------------
# Resources & Scaling
# -----------------------------------------------------------------------------

variable "resources" {
  description = "Resource requests and limits for Kong pods"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "2000m"
      memory = "2Gi"
    }
  }
}

variable "enable_autoscaling" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = true
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 10
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization percentage for autoscaling"
  type        = number
  default     = 70
}

# -----------------------------------------------------------------------------
# High Availability
# -----------------------------------------------------------------------------

variable "enable_pdb" {
  description = "Enable Pod Disruption Budget"
  type        = bool
  default     = true
}

variable "pdb_min_available" {
  description = "Minimum available pods for PDB"
  type        = string
  default     = "50%"
}

# -----------------------------------------------------------------------------
# Network Policy
# -----------------------------------------------------------------------------

variable "enable_network_policy" {
  description = "Enable Kubernetes NetworkPolicy for Kong"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Extra Configuration
# -----------------------------------------------------------------------------

variable "extra_values" {
  description = "Extra Helm values in YAML format"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
