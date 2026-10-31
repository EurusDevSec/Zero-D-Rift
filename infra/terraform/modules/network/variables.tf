variable "name" {
  description = "Name prefix for network resources."
  type        = string
}

variable "region" {
  description = "AWS Region; used for the S3 endpoint service name and policy."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR block."
  type        = string
}

variable "azs" {
  description = "Availability Zones, one public and one DB subnet in each."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public worker subnet CIDRs, in the same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "Give exactly one public subnet CIDR per AZ."
  }
}

variable "db_subnet_cidrs" {
  description = "Private DB subnet CIDRs, in the same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.db_subnet_cidrs) == length(var.azs)
    error_message = "Give exactly one DB subnet CIDR per AZ."
  }
}
