locals {
  cluster_name = var.cluster_name
}

###############################################################################
# EKS cluster + managed node group — deployed into EXISTING VPC (gx-network:Vpc1)
###############################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true # the principal running apply gets cluster-admin

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {} # enables Pod Identity (used for Bedrock + EBS CSI)
    aws-ebs-csi-driver = {
      # Controller needs EC2 perms; bind its SA to a dedicated IAM role via Pod Identity.
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}

###############################################################################
# Default StorageClass (gp3, via the EBS CSI driver we install above).
# The cluster ships no default SC — PVCs with no storageClassName (e.g. kagent's
# bundled Postgres) stay Pending forever without this.
###############################################################################

resource "kubernetes_storage_class" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}

###############################################################################
# Bedrock access for agent pods (EKS Pod Identity — no static keys)
###############################################################################

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    # Tighten to specific model / inference-profile ARNs once chosen.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name   = "${local.cluster_name}-bedrock-invoke"
  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "bedrock" {
  name               = "${local.cluster_name}-bedrock"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "bedrock" {
  role       = aws_iam_role.bedrock.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

# Binds the IAM role to a Kubernetes ServiceAccount. Enable once the kagent SA exists
# (set enable_bedrock_pod_identity = true). Until then the role exists but is unbound.
resource "aws_eks_pod_identity_association" "bedrock" {
  count = var.enable_bedrock_pod_identity ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.agent_namespace
  service_account = var.agent_service_account
  role_arn        = aws_iam_role.bedrock.arn
}

###############################################################################
# EBS CSI driver IAM (Pod Identity) — required for PVCs (e.g. kagent Postgres)
###############################################################################

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
