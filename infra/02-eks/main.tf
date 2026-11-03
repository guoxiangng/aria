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

  # Control-plane logging OFF (2026-10-31). The module's default (api, audit, authenticator) was
  # ingesting ~64 GB/month into CloudWatch, ~$43/month — the largest CloudWatch line on a POC bill.
  # Re-enable selectively, e.g. ["authenticator"], when debugging auth; "audit" is the expensive one.
  cluster_enabled_log_types = []

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    # Prefix delegation ON (2026-11-01). Each ENI slot holds a /28 (16 IPs) instead of one IP, so a
    # t3.large goes from 35 pods to EKS's 110 cap (managed node groups compute max-pods themselves —
    # our launch template pins no AMI). The 35-pod ceiling, not CPU or memory, is what forced the third
    # node ("1 Too many pods"). Cost: nodes reserve IPs 16 at a time — irrelevant in /23 subnets with
    # ~470 free each. Existing nodes keep 35 until replaced. Version pinned so this change can't also
    # upgrade the CNI.
    #
    # before_compute = true (2026-11-03, found by the rebuild drill): the module otherwise creates
    # addons AFTER the node group, so on a fresh build the nodes launched 2 minutes before prefix
    # delegation was switched on and EKS gave them max-pods 35, not 110. The 11-01 change only worked
    # because the nodes happened to be replaced after the CNI was already configured.
    vpc-cni = {
      before_compute = true
      addon_version  = "v1.22.3-eksbuild.1"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {} # enables Pod Identity (used for Bedrock + EBS CSI)
    # Added 2026-09-19. Without it `kubectl top` fails with "Metrics API not available", so the only
    # visible numbers are resource *requests* — which is how this cluster ran at 96-97% of requested
    # CPU while nobody could see actual utilisation. Agents reserve 100m each and spend most of their
    # life blocked on an LLM call, so requests almost certainly overstate real use; this is what
    # makes that measurable (and right-sizing possible) rather than guessed.
    metrics-server = {}
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
      subnet_ids     = length(var.node_subnet_ids) > 0 ? var.node_subnet_ids : var.private_subnet_ids
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  # Module default only opens ephemeral ports (1025-65535) between nodes on the node
  # security group's self-referencing rule. Any pod serving on a privileged port needs an
  # explicit rule here to be reachable from a pod on a DIFFERENT node. Found via Agent
  # Substrate's ate-api (port 443): cross-node calls timed out at the TCP layer even though
  # ate-api itself was healthy and listening — not the mesh, not certs, this SG default.
  node_security_group_additional_rules = {
    ingress_self_443 = {
      description = "Node-to-node pod traffic on 443 (e.g. Substrate ate-api gRPC)"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      self        = true
    }
    # Same class of bug as ingress_self_443, different direction. The metrics-server addon (added
    # 2026-09-19) serves on 10251, and the Kubernetes API server must reach it to back the
    # metrics.k8s.io APIService. The module's defaults do not open that port from the CONTROL PLANE
    # to the nodes, so the pods ran happily, the addon reported ACTIVE, and `kubectl top` still
    # failed — the APIService showed the real cause:
    #   Available=False ... dial https://<pod-ip>:10251/apis/metrics.k8s.io/v1beta1: Client.Timeout
    ingress_cluster_metrics_server = {
      description                   = "Control plane to metrics-server (10251) - backs metrics.k8s.io"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}

# vpc-cni switched to before_compute (above): the module keeps those addons under a different
# resource address. Without this, Terraform would delete and recreate the live CNI addon.
moved {
  from = module.eks.aws_eks_addon.this["vpc-cni"]
  to   = module.eks.aws_eks_addon.before_compute["vpc-cni"]
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
