# P4 shared database (SPEC-P4 P4-T2.2 A, D1, D2, ADR-0008). One private RDS
# PostgreSQL instance for all sandboxes, created and destroyed with each window.
# Terraform owns the instance and its security group; nothing in the request
# path creates or changes them (ADR-0003).
#
# - Private: the existing DB subnet group (P2 network module, no Internet route),
#   publicly_accessible = false, and a security group with exactly one ingress
#   rule: 5432/tcp from the node security group (Pods use the node SG).
# - Master password: generated and kept by RDS in Secrets Manager
#   (manage_master_user_password); Terraform never sees it.
# - Destroyable in the window: no automated backup, no final snapshot, no
#   deletion protection. Encrypted with the AWS managed key (no customer KMS key,
#   plan_assert check 2).
# - TLS: the default postgres17 parameter group has rds.force_ssl = 1 (DRF-40),
#   so no custom parameter group is created.

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "P4 shared RDS: 5432 from the EKS node security group only"
  vpc_id      = var.vpc_id

  # No inline rules: the only rule is the ingress rule below. Terraform removes
  # the default allow-all egress of a new group, and RDS needs no egress.
  tags = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from EKS nodes (Pods share the node SG)"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.node_security_group_id

  tags = { Name = "${var.name}-db-from-nodes" }
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 0 # no storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  username                    = var.master_username
  manage_master_user_password = true
  port                        = 5432

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false
  network_type           = "IPV4"
  ca_cert_identifier     = var.ca_cert_identifier

  iam_database_authentication_enabled = false
  performance_insights_enabled        = false
  monitoring_interval                 = 0

  backup_retention_period  = 0
  delete_automated_backups = true
  skip_final_snapshot      = true
  deletion_protection      = false
  copy_tags_to_snapshot    = true

  # The pin only holds if AWS may not upgrade the minor version (DRF-40).
  auto_minor_version_upgrade  = false
  allow_major_version_upgrade = false
  apply_immediately           = true

  tags = { Name = var.name }
}
