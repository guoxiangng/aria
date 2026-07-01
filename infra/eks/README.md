# infra/eks

VPC + EKS cluster + managed node group + Bedrock access (Pod Identity). Uses the **S3 remote backend**
created by `infra/bootstrap`.

## What it creates
- **VPC** (3 AZs, public + private subnets, single NAT GW for cost), subnet-tagged for future LB controller
- **EKS** cluster (`cluster_version` default 1.32), public API endpoint, creator gets cluster-admin
- **Managed node group** (default 2× `t3.large` **spot**, autoscale 1–3)
- **Addons**: coredns, kube-proxy, vpc-cni, **eks-pod-identity-agent**, aws-ebs-csi-driver
- **Bedrock IAM role** + invoke policy, bound to a K8s ServiceAccount via **Pod Identity** (no static keys)

## Use

```bash
# 1. Put state_bucket into backend.hcl (gitignored)
# 2.
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 3.
aws eks update-kubeconfig --name aria --region ap-southeast-1
kubectl get nodes
```

## Notes
- `enable_bedrock_pod_identity` is **false** by default — the Bedrock IAM role is created but not yet bound
  to a ServiceAccount. After kagent is installed, set it `true` (and confirm `agent_service_account`) to bind it.
- Bedrock `resources = ["*"]` for now — tighten to the chosen Claude inference-profile ARNs later.
- Cost: `terraform destroy` this layer when idle to drop node + control-plane charges.
