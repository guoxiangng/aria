###############################################################################
# NAT instance (fck-nat) — replaces a hand-made NAT gateway on the private subnets
###############################################################################
#
# WHY: the NAT gateway (`gx-network-nat`) cost ~$43/month in hours alone, on a POC whose whole egress
# is a few GB. fck-nat on a t4g.nano is ~$3/month plus ~$3.60 for its public IPv4.
#
# WHAT IT REPLACES: the NAT gateway was created by hand in July 2024 — not by the `enterprise-network`
# CloudFormation stack (2022) and not by any Terraform. The live private route table was likewise added
# outside the stack (the stack's own table is now "(old)", 0 subnets). So nothing else owns this path;
# this layer takes the default route over via `import` and points it at the NAT instance.
#
# TRADE-OFFS ACCEPTED: one instance, one AZ. `ha_mode` puts it in an ASG with a STATIC ENI, so a dead
# instance is replaced and re-attached to the same ENI without touching the route — but egress is down
# for the minutes that takes. Fine for a POC; a production VPC would keep NAT gateways per AZ.

module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.6.1"

  name          = "aria-nat"
  vpc_id        = var.vpc_id
  subnet_id     = var.public_subnet_id
  instance_type = var.instance_type
  ha_mode       = true

  # The route is managed below, not by the module, so the cut-over is its own reviewable step.
  update_route_tables = false
}

# The private subnets' default route. It existed already (pointing at the hand-made NAT gateway), so it
# was adopted with a one-off `import` block on 2026-11-01, removed afterwards: on a fresh rebuild there
# is no route to import, and the block would fail the plan. Terraform now simply creates it.
resource "aws_route" "private_default" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fck_nat.eni_id
}
