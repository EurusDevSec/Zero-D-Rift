variable "cluster_name" {
  description = "EKS cluster name; Karpenter object names and the cluster-tag conditions use it."
  type        = string
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
