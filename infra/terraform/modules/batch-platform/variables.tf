variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from the EKS module)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer URL, with or without https://."
  type        = string
}

variable "region" {
  description = "Region of the queues."
  type        = string
}

variable "queue_name" {
  description = "Shared batch queue (ver3 §6.5, D3); the dead-letter queue is <name>-dlq."
  type        = string
  default     = "zero-drift-batch"

  validation {
    condition     = var.queue_name == "zero-drift-batch"
    error_message = "queue_name is fixed by SPEC-P6 P6-T3: zero-drift-batch."
  }
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout (D8: 120 s, heartbeat every 40 s)."
  type        = number
  default     = 120

  validation {
    condition     = var.visibility_timeout_seconds == 120
    error_message = "D8 fixes the visibility timeout at 120 s."
  }
}

variable "max_receive_count" {
  description = "Receives before a message moves to the dead-letter queue (D8)."
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count == 3
    error_message = "D8 fixes maxReceiveCount at 3."
  }
}

variable "retention_seconds" {
  description = "Message retention of both queues (D8: 1 h, so no stale message reaches a later window)."
  type        = number
  default     = 3600

  validation {
    condition     = var.retention_seconds == 3600
    error_message = "D8 fixes retention at 3600 s."
  }
}

variable "tenants" {
  description = "Tenants with a batch-train role. A namespace not listed here gets no role."
  type        = list(string)
  default     = ["tenant-a", "tenant-b"]

  validation {
    condition     = length(var.tenants) > 0 && alltrue([for t in var.tenants : can(regex("^tenant-[a-z]$", t))])
    error_message = "tenants must be names like tenant-a: one letter after tenant-, so no tenant name is a prefix of another."
  }
}

variable "bucket_prefix" {
  description = "Checkpoint buckets are zero-drift-batch-<tenant>-<name> (P6-T2.2)."
  type        = string
  default     = "zero-drift-batch-"

  validation {
    condition     = var.bucket_prefix == "zero-drift-batch-"
    error_message = "bucket_prefix is fixed: zero-drift-batch-."
  }
}

variable "platform_namespace" {
  description = "Namespace of the submit Job's ServiceAccount."
  type        = string
  default     = "zdr-platform"

  validation {
    condition     = !startswith(var.platform_namespace, "tenant-")
    error_message = "The platform namespace must not be a tenant namespace."
  }
}

variable "submit_service_account" {
  description = "ServiceAccount of the submit Job in the platform namespace (P6-T2.2 must use this name)."
  type        = string
  default     = "batch-submit"
}

variable "train_service_account" {
  description = "Platform-owned ServiceAccount in each tenant namespace (P6-T2.2)."
  type        = string
  default     = "batch-train"
}

variable "keda_namespace" {
  description = "Namespace of the KEDA operator."
  type        = string
  default     = "keda"
}

variable "keda_service_account" {
  description = "ServiceAccount of the KEDA operator (chart default)."
  type        = string
  default     = "keda-operator"
}
