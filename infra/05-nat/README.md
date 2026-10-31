# infra/05-nat

**Durable** layer — a NAT *instance* ([fck-nat](https://fck-nat.dev)) for the private subnets the EKS
nodes run in. Survives `terraform destroy` of `infra/02-eks`, like `04-persistent`. Its own state key
(`nat/terraform.tfstate`) and its own AWS provider major (6.x — the module needs it).

## Why it exists
The private subnets' egress went through a NAT **gateway** created by hand in July 2024 — not by the
`enterprise-network` CloudFormation stack and not by any Terraform. It cost ~$43/month in hours alone.
This layer replaces it with fck-nat on a `t4g.nano`: ~$3/month + ~$3.60 for the public IPv4.

## What it creates
- The fck-nat module (pinned 1.6.1): an ASG of one, a **static ENI** (the route target), security group
  (ingress from the VPC CIDR only), instance role.
- `aws_route.private_default` — the private route table's `0.0.0.0/0`, **imported** from the old gateway
  route and pointed at the static ENI.

## Trade-offs accepted
One instance, one AZ, no HA. If the instance dies, the ASG replaces it and re-attaches the same ENI —
the route never changes, but egress is down for those minutes. A production VPC would keep a NAT
gateway per AZ.

## Use
```bash
cp backend.hcl.example backend.hcl            # fill in the bucket
cp terraform.tfvars.example terraform.tfvars  # vpc, public subnet, private route table
terraform init -backend-config=backend.hcl
terraform apply
```

## Cut-over log (2026-11-01)
1. `apply -target=module.fck_nat` — instance up, ENI attached, no traffic change.
2. `apply` — route imported and switched in place from `nat-08f392e26a9b20a5a` to the ENI.
3. Verified from a pod: egress IP = the NAT instance's, GitHub 200, Bedrock/ECR reachable, and a real
   agent call (k8s-agent → LiteLLM → Bedrock → tools) completed.
4. The old NAT gateway and its Elastic IP are deleted by hand (it was never in any IaC).
