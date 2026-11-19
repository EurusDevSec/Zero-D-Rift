# Endpoint and secret ARN hold the account ID or the host name: sensitive.

output "identifier" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.identifier
}

output "address" {
  description = "Host name of the instance (DB_HOST in platform-config)."
  value       = aws_db_instance.this.address
  sensitive   = true
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "master_secret_arn" {
  description = "ARN of the RDS-managed master secret (MASTER_SECRET_ID for db-init)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  sensitive   = true
}

output "security_group_id" {
  description = "Security group of the instance."
  value       = aws_security_group.db.id
}

output "settings" {
  description = "Settings as planned, for the contract tests."
  value = {
    engine                     = aws_db_instance.this.engine
    engine_version             = aws_db_instance.this.engine_version
    instance_class             = aws_db_instance.this.instance_class
    allocated_storage          = aws_db_instance.this.allocated_storage
    max_allocated_storage      = aws_db_instance.this.max_allocated_storage
    storage_type               = aws_db_instance.this.storage_type
    storage_encrypted          = aws_db_instance.this.storage_encrypted
    publicly_accessible        = aws_db_instance.this.publicly_accessible
    multi_az                   = aws_db_instance.this.multi_az
    manage_master_password     = aws_db_instance.this.manage_master_user_password
    backup_retention_period    = aws_db_instance.this.backup_retention_period
    skip_final_snapshot        = aws_db_instance.this.skip_final_snapshot
    deletion_protection        = aws_db_instance.this.deletion_protection
    auto_minor_version_upgrade = aws_db_instance.this.auto_minor_version_upgrade
    db_subnet_group_name       = aws_db_instance.this.db_subnet_group_name
    security_group_ids         = aws_db_instance.this.vpc_security_group_ids
  }
}

output "ingress" {
  description = "The single ingress rule, for the contract tests."
  value = {
    protocol     = aws_vpc_security_group_ingress_rule.postgres_from_nodes.ip_protocol
    from_port    = aws_vpc_security_group_ingress_rule.postgres_from_nodes.from_port
    to_port      = aws_vpc_security_group_ingress_rule.postgres_from_nodes.to_port
    source_sg    = aws_vpc_security_group_ingress_rule.postgres_from_nodes.referenced_security_group_id
    cidr_ipv4    = aws_vpc_security_group_ingress_rule.postgres_from_nodes.cidr_ipv4
    target_group = aws_vpc_security_group_ingress_rule.postgres_from_nodes.security_group_id
  }
}
