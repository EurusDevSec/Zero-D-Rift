output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public worker subnet IDs (input for the EKS node group in DRF-9)."
  value       = module.vpc.public_subnets
}

output "db_subnet_ids" {
  description = "Private DB subnet IDs."
  value       = module.vpc.database_subnets
}

output "db_subnet_group_name" {
  description = "DB subnet group for a later private RDS."
  value       = module.vpc.database_subnet_group_name
}

output "public_route_table_ids" {
  description = "Route tables of the public subnets (IGW route and S3 endpoint)."
  value       = module.vpc.public_route_table_ids
}

output "db_route_table_ids" {
  description = "Route tables of the DB subnets (no Internet route)."
  value       = module.vpc.database_route_table_ids
}

output "nat_gateway_count" {
  description = "Number of NAT Gateways; must stay 0 (ADR-0006)."
  value       = length(module.vpc.natgw_ids)
}

output "s3_endpoint_type" {
  description = "Type of the S3 endpoint; must be Gateway (no hourly charge)."
  value       = module.vpc_endpoints.endpoints["s3"].vpc_endpoint_type
}
