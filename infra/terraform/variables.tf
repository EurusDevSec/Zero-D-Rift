variable "region" {
  description = "AWS Region for the PoC."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "Zero D-Rift runs only in us-east-1."
  }
}

variable "cluster_name" {
  description = "EKS cluster name; also prefixes networking names. Changing it replaces the cluster."
  type        = string
  default     = "zero-drift"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name may contain only lowercase letters, digits and hyphens."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.35"

  validation {
    condition     = var.kubernetes_version == "1.35"
    error_message = "The approved EKS version is 1.35; an upgrade needs a reviewed change to this validation."
  }
}

variable "azs" {
  description = "Availability Zones for public and DB subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) == 2 && alltrue([for az in var.azs : startswith(az, var.region)])
    error_message = "Use exactly 2 AZs in the selected Region: EKS needs at least 2 and the PoC budget allows 2."
  }
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR block."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR such as 10.0.0.0/16."
  }
}

variable "enable_nat_gateway" {
  description = "Guardrail only; ADR-0006 forbids a default NAT Gateway."
  type        = bool
  default     = false

  validation {
    condition     = var.enable_nat_gateway == false
    error_message = "NAT Gateway is disabled by ADR-0006 (cost guard)."
  }
}

variable "system_node_ami_type" {
  description = "AMI type of the system node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition     = startswith(var.system_node_ami_type, "AL2023")
    error_message = "System nodes must use an AL2023 AMI type."
  }
}

variable "system_node_desired_size" {
  description = "Desired number of system nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_desired_size >= 1 && var.system_node_desired_size <= 3
    error_message = "system_node_desired_size must be between 1 and 3."
  }
}

# Run metadata for the tag contract (docs/finops/COST_PLAN.md §10). No defaults:
# every plan must name its run and expiry (see run.tfvars.example).
variable "run_id" {
  description = "Run ID linking AWS resources to the run manifest and evidence."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{2,63}$", var.run_id))
    error_message = "run_id must be 3-64 characters: letters, digits and hyphens."
  }
}

variable "expires_at" {
  description = "UTC RFC3339 expiry metadata tag; it does not delete anything by itself."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.expires_at))
    error_message = "expires_at must be UTC RFC3339, e.g. 2026-11-02T12:00:00Z."
  }
}
