###############################################################################
# Agent Substrate — JWT-mode cert/session material, generated declaratively and
# stored in AWS Secrets Manager (consumed via ESO ExternalSecrets in
# platform/substrate/manifests/).
#
# WHY THIS EXISTS: the upstream substrate chart self-bootstraps these via Helm
# `genCA`/`genSignedCert` + `lookup` (reuse-on-upgrade). `lookup` returns empty
# under ArgoCD's `helm template` rendering, so ArgoCD would regenerate the ate-api
# server cert + session-signing keys on EVERY sync. We therefore DISABLE the chart
# bootstrap (auth.jwt.bootstrap.enabled=false in platform/substrate/values.yaml)
# and provide the material ourselves — deterministic, and the same ESO + Secrets
# Manager pattern as the kagent secrets (see eso.tf). Shapes mirror jwt-bootstrap.yaml
# EXACTLY (server cert SANs, session-pool JSON) so ate-api consumes them unchanged.
#
# LAYERING: this is cert *material generation + AWS storage* (Terraform/AWS layer),
# same tier as the secret seeding in eso.tf. The K8s objects (Secrets via ESO) are
# in the platform layer, deployed by ArgoCD. No K8s resource is created here.
###############################################################################

# --- ate-api server cert: a private CA + a server cert for the ate-api gRPC endpoint.
resource "tls_private_key" "substrate_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "substrate_ca" {
  private_key_pem       = tls_private_key.substrate_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600 # 10y (chart: 3650d)
  subject { common_name = "api-ate-system-ca" }
  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "substrate_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "substrate_server" {
  private_key_pem = tls_private_key.substrate_server.private_key_pem
  subject { common_name = "api.ate-system.svc" }
  # SANs must match jwt-bootstrap.yaml's genSignedCert exactly.
  dns_names = [
    "api.ate-system.svc",
    "api.ate-system.svc.cluster.local",
    "atenet-router.ate-system.svc",
  ]
}

resource "tls_locally_signed_cert" "substrate_server" {
  cert_request_pem      = tls_cert_request.substrate_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.substrate_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.substrate_ca.cert_pem
  validity_period_hours = 8760 # 1y (chart: 365d)
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

# --- session-id pools: an ECDSA (ES256) JWT signing key + an RSA session CA.
resource "tls_private_key" "substrate_session_jwt" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256" # ES256
}

resource "tls_private_key" "substrate_session_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "substrate_session_ca" {
  private_key_pem       = tls_private_key.substrate_session_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600
  subject { common_name = "session-id-ca" }
  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

# --- Secrets Manager: seed the material. ignore_changes => stable after first apply
# (SM is the source of truth; certs don't churn). Property keys match the ExternalSecrets.
resource "aws_secretsmanager_secret" "substrate_ateapi_tls" {
  name        = "${local.sm_prefix}/substrate-ateapi-tls"
  description = "Substrate ate-api JWT-mode server cert + CA (ESO -> ateapi-tls, ateapi-ca)."
}

resource "aws_secretsmanager_secret_version" "substrate_ateapi_tls" {
  secret_id = aws_secretsmanager_secret.substrate_ateapi_tls.id
  secret_string = jsonencode({
    "tls.crt" = tls_locally_signed_cert.substrate_server.cert_pem
    "tls.key" = tls_private_key.substrate_server.private_key_pem
    "ca.crt"  = tls_self_signed_cert.substrate_ca.cert_pem # public; ESO -> ateapi-ca Secret
  })
  lifecycle { ignore_changes = [secret_string] }
}

resource "aws_secretsmanager_secret" "substrate_session_jwt_pool" {
  name        = "${local.sm_prefix}/substrate-session-jwt-pool"
  description = "Substrate session-id JWT signing pool (ESO -> session-id-jwt-pool)."
}

resource "aws_secretsmanager_secret_version" "substrate_session_jwt_pool" {
  secret_id = aws_secretsmanager_secret.substrate_session_jwt_pool.id
  # `pool` = the JSON the chart builds: {"Authorities":[{ID,Algorithm,SigningKeyPEM}]}.
  # ESO writes it to Secret key `pool` (K8s base64s it) — mounted as pool.json.
  secret_string = jsonencode({
    pool = jsonencode({
      Authorities = [{
        ID            = "1"
        Algorithm     = "ES256"
        SigningKeyPEM = tls_private_key.substrate_session_jwt.private_key_pem
      }]
    })
  })
  lifecycle { ignore_changes = [secret_string] }
}

resource "aws_secretsmanager_secret" "substrate_session_ca_pool" {
  name        = "${local.sm_prefix}/substrate-session-ca-pool"
  description = "Substrate session-id CA pool (ESO -> session-id-ca-pool)."
}

resource "aws_secretsmanager_secret_version" "substrate_session_ca_pool" {
  secret_id = aws_secretsmanager_secret.substrate_session_ca_pool.id
  secret_string = jsonencode({
    pool = jsonencode({
      CAs = [{
        ID                 = "1"
        SigningKeyPEM      = tls_private_key.substrate_session_ca.private_key_pem
        RootCertificatePEM = tls_self_signed_cert.substrate_session_ca.cert_pem
      }]
    })
  })
  lifecycle { ignore_changes = [secret_string] }
}

# --- Extend the ESO role (defined in eso.tf) to read these three secrets too. ---
data "aws_iam_policy_document" "eso_read_substrate" {
  statement {
    sid       = "ReadSubstrateSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.substrate_ateapi_tls.arn,
      aws_secretsmanager_secret.substrate_session_jwt_pool.arn,
      aws_secretsmanager_secret.substrate_session_ca_pool.arn,
    ]
  }
}

resource "aws_iam_role_policy" "eso_read_substrate" {
  name   = "read-substrate-secrets"
  role   = aws_iam_role.eso.id # role from eso.tf
  policy = data.aws_iam_policy_document.eso_read_substrate.json
}
