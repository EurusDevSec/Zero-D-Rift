variable "name" {
  description = "Instance identifier and name prefix; must keep the zero-drift-rag prefix."
  type        = string
  default     = "zero-drift-rag"

  validation {
    condition     = can(regex("^zero-drift-rag(-[a-z0-9]+)*$", var.name))
    error_message = "name must start with zero-drift-rag."
  }
}

variable "vpc_id" {
  description = "VPC of the cluster (P2 network module)."
  type        = string
}

variable "db_subnet_group_name" {
  description = "Existing DB subnet group of the private DB subnets (P2 network module, ADR-0006)."
  type        = string
}

variable "node_security_group_id" {
  description = "EKS node security group; the only source allowed on 5432."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL version pinned in VERSION_MATRIX §8 (DRF-40)."
  type        = string
  default     = "17.11"

  validation {
    condition     = can(regex("^17\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be an exact PostgreSQL 17 minor, e.g. 17.11."
  }
}

variable "instance_class" {
  description = "Approved instance class (D2). A larger class needs a new approval."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = var.instance_class == "db.t4g.micro"
    error_message = "instance_class must be db.t4g.micro (SPEC-P4 D2)."
  }
}

variable "allocated_storage" {
  description = "Storage in GiB (D2)."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage == 20
    error_message = "allocated_storage must be 20 (SPEC-P4 D2)."
  }
}

variable "master_username" {
  description = "Master user name. Its password is managed by RDS in Secrets Manager."
  type        = string
  default     = "zdr_master"
}

variable "ca_cert_identifier" {
  description = "Server certificate CA; the app verifies it with the RDS CA bundle (verify-full)."
  type        = string
  default     = "rds-ca-rsa2048-g1"
}
