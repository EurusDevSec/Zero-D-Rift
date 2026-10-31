# Mock for the EKS module's OIDC thumbprint lookup (no network call in tests).
mock_data "tls_certificate" {
  defaults = {
    certificates = [{ sha1_fingerprint = "0000000000000000000000000000000000000000" }]
  }
}
