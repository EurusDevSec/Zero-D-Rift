# Credentials come only from the environment (temporary STS session from the
# reviewed operator role, ADR-0007). No profile, key or account ID in code.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}
