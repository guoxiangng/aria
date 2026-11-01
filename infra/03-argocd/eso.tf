###############################################################################
# ESO's Pod Identity binding — the only cluster-scoped piece of the secrets setup.
#
# The Secrets Manager secrets and the IAM role ESO assumes live in infra/04-persistent
# (secrets.tf, substrate-certs.tf) so they survive a cluster teardown. This association is
# tied to the cluster, so it is destroyed and recreated with it. It finds the role by name.
#
# The SA (external-secrets/external-secrets) is created later by the ArgoCD-managed ESO
# install; the association binds by name and does not require the SA to exist yet. With Pod
# Identity, NO annotation on the SA is needed (unlike IRSA) and the ClusterSecretStore needs
# no auth block — the AWS SDK picks creds up automatically.
###############################################################################

data "aws_iam_role" "eso" {
  name = "${var.cluster_name}-external-secrets" # created by infra/04-persistent/secrets.tf
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = data.aws_iam_role.eso.arn
}
