variable "cluster_name" {
  description = "EKS cluster name; Karpenter object names and the cluster-tag conditions use it."
  type        = string
}

variable "access_entry_cluster_name" {
  description = "The same name, taken from the cluster module output, so the node access entry is created only after the cluster exists."
  type        = string

  validation {
    condition     = var.access_entry_cluster_name != ""
    error_message = "access_entry_cluster_name must be the cluster module output, not empty."
  }
}

variable "region" {
  description = "Region of the cluster."
  type        = string
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
  description = "Namespace of the Karpenter controller (never on a node it provisions, boundary 3)."
  type        = string
  default     = "karpenter"
}

variable "service_account" {
  description = "ServiceAccount of the Karpenter controller (chart default)."
  type        = string
  default     = "karpenter"
}
