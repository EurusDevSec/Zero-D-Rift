variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from the EKS module)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer URL, with or without https://."
  type        = string
}

variable "region" {
  description = "Region of the secrets."
  type        = string
}

variable "master_secret_arn" {
  description = "ARN of the RDS-managed master secret (shared-rds output)."
  type        = string
}

variable "tenants" {
  description = "Tenants with a role (D6, D11). A namespace not listed here gets no role."
  type        = list(string)
  default     = ["tenant-a", "tenant-b"]

  validation {
    condition     = length(var.tenants) > 0 && alltrue([for t in var.tenants : can(regex("^tenant-[a-z]$", t))])
    error_message = "tenants must be names like tenant-a: one letter after tenant-, so no tenant name is a prefix of another."
  }
}

variable "platform_namespace" {
  description = "Namespace of the db-init and bootstrap ServiceAccounts (D4)."
  type        = string
  default     = "zdr-platform"

  validation {
    condition     = !startswith(var.platform_namespace, "tenant-")
    error_message = "The platform namespace must not be a tenant namespace."
  }
}

variable "secret_prefix" {
  description = "Name prefix of every P4 secret (ADR-0008 §3)."
  type        = string
  default     = "zero-drift/rag/"

  validation {
    condition     = var.secret_prefix == "zero-drift/rag/"
    error_message = "secret_prefix is fixed by ADR-0008: zero-drift/rag/."
  }
}

variable "bucket_prefix" {
  description = "Sandbox buckets are zero-drift-rag-<tenant>-<name> (D7)."
  type        = string
  default     = "zero-drift-rag-"

  validation {
    condition     = var.bucket_prefix == "zero-drift-rag-"
    error_message = "bucket_prefix is fixed by D7: zero-drift-rag-."
  }
}

variable "crossplane_namespace" {
  description = "Namespace of the Crossplane S3 provider ServiceAccount."
  type        = string
  default     = "crossplane-system"
}

variable "crossplane_service_account" {
  description = "Provider ServiceAccount, fixed by the DeploymentRuntimeConfig (DRF-39)."
  type        = string
  default     = "provider-aws-s3"
}
