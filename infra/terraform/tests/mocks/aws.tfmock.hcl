# Shared AWS mock values for terraform test. The account ID is the obvious fake
# 000000000000; mocks only need ARNs and JSON that pass the provider's checks.
mock_data "aws_caller_identity" {
  defaults = {
    account_id = "000000000000"
    arn        = "arn:aws:iam::000000000000:user/test"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

mock_data "aws_iam_session_context" {
  defaults = {
    arn        = "arn:aws:iam::000000000000:role/test"
    issuer_arn = "arn:aws:iam::000000000000:role/test"
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::000000000000:role/test"
  }
}

mock_resource "aws_iam_policy" {
  defaults = {
    arn = "arn:aws:iam::000000000000:policy/test"
  }
}

mock_resource "aws_eks_cluster" {
  defaults = {
    arn = "arn:aws:eks:us-east-1:000000000000:cluster/test"
    identity = [{
      oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST" }]
    }]
    certificate_authority = [{ data = "dGVzdA==" }]
  }
}

mock_resource "aws_iam_openid_connect_provider" {
  defaults = {
    arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST"
  }
}

mock_resource "aws_launch_template" {
  defaults = {
    id  = "lt-0000000000000000"
    arn = "arn:aws:ec2:us-east-1:000000000000:launch-template/lt-0000000000000000"
  }
}

# P4 (DRF-46): the RDS-managed master secret and the endpoint are computed.
mock_resource "aws_db_instance" {
  defaults = {
    arn      = "arn:aws:rds:us-east-1:000000000000:db:zero-drift-rag"
    address  = "zero-drift-rag.test.us-east-1.rds.amazonaws.com"
    endpoint = "zero-drift-rag.test.us-east-1.rds.amazonaws.com:5432"
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:us-east-1:000000000000:secret:rds!db-TEST-AbCdEf"
      kms_key_id    = "arn:aws:kms:us-east-1:000000000000:key/test"
      secret_status = "active"
    }]
  }
}

mock_resource "aws_security_group" {
  defaults = {
    id  = "sg-00000000000000000"
    arn = "arn:aws:ec2:us-east-1:000000000000:security-group/sg-00000000000000000"
  }
}
