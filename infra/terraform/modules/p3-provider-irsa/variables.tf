variable "role_name" {
  description = "IAM role name; must keep the zero-drift-p3- prefix."
  type        = string

  validation {
    condition     = startswith(var.role_name, "zero-drift-p3-")
    error_message = "role_name must start with zero-drift-p3-."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from the EKS module)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer URL, with or without https://."
  type        = string
}

variable "namespace" {
  description = "Namespace of the provider ServiceAccount."
  type        = string
  default     = "crossplane-system"
}

variable "service_account" {
  description = "Provider ServiceAccount name, fixed by the DeploymentRuntimeConfig (DRF-39)."
  type        = string
  default     = "provider-aws-s3"
}

variable "bucket_prefix" {
  description = "Only buckets whose name starts with this prefix are allowed."
  type        = string

  validation {
    condition     = can(regex("^zero-drift-p3-[a-z0-9-]*$", var.bucket_prefix))
    error_message = "bucket_prefix must start with zero-drift-p3- and contain no wildcard."
  }
}
