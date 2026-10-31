variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
}

variable "vpc_id" {
  description = "VPC from the network module."
  type        = string
}

variable "subnet_ids" {
  description = "Public worker subnets from the network module (control plane ENIs and nodes)."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint."
  type        = list(string)
}

variable "bootstrap_role_name" {
  description = "IAM role that gets the bootstrap access entry (DRF-5)."
  type        = string
}

variable "bootstrap_cluster_admin" {
  description = "Associate AmazonEKSClusterAdminPolicy with the bootstrap entry (window only)."
  type        = bool
}

variable "addon_versions" {
  description = "Exact add-on versions, keyed by add-on name."
  type        = map(string)
}

variable "node_ami_type" {
  description = "AMI type of the system node group."
  type        = string
}

variable "node_ami_release_version" {
  description = "Exact EKS-optimized AMI release version of the system node group."
  type        = string
}

variable "node_instance_type" {
  description = "Instance type of the system node group."
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of system nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of system nodes."
  type        = number
}
