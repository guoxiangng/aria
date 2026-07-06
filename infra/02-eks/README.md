# infra/02-eks

EKS cluster + managed node group + Bedrock access (Pod Identity), deployed into an **existing VPC**.
Uses the **S3 remote backend** created by `infra/01-bootstrap`.

## What it creates
- **EKS** cluster (`cluster_version` default 1.36), public API endpoint, creator gets cluster-admin
- **Managed node group** (default 2× `t3.large` **spot**, autoscale 1–3)
- **Addons**: coredns, kube-proxy, vpc-cni, **eks-pod-identity-agent**, aws-ebs-csi-driver
- **Bedrock IAM role** + invoke policy, bound to a K8s ServiceAccount via **Pod Identity** (no static keys)

> **Network:** does NOT create a VPC. Deploys into the existing `vpc_id` + `private_subnet_ids` set in
> `terraform.tfvars` (gitignored). Requires private subnets in ≥2 AZs with NAT egress + DNS enabled.
> `terraform destroy` removes the cluster/nodes but leaves your VPC untouched.

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

## Scaling nodes — `node_desired_size` does NOT work on an existing node group
The `terraform-aws-modules/eks/aws` module sets `lifecycle { ignore_changes = [scaling_config[0].desired_size] }`
on the node group **by design** (so Terraform doesn't fight a cluster-autoscaler). This means bumping
`node_desired_size` in `terraform.tfvars` and re-applying **only takes effect when the node group is first
created** — on an existing node group, `terraform apply` will report success but silently do nothing to the
running ASG. (Learned the hard way: bumped to 2, applied cleanly, ASG stayed at 1.)

Since we don't run cluster-autoscaler/Karpenter, scale manually via the ASG directly (this does NOT conflict
with Terraform — the field is explicitly ignored):
```bash
ASG=$(aws eks describe-nodegroup --cluster-name aria --nodegroup-name <name> --region ap-southeast-1 \
  --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG" --desired-capacity 2 --region ap-southeast-1
```
`node_min_size`/`node_max_size` in tfvars still matter (they bound what the ASG will accept), so keep those
updated too even though `desired_size` itself needs the manual step.
