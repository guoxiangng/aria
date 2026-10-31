output "nat_eni_id" {
  description = "The static ENI the private route table points at. It survives instance replacement."
  value       = module.fck_nat.eni_id
}

output "nat_public_ip" {
  description = "Egress IP — what GitHub, Bedrock and every other outside service sees ARIA as."
  value       = module.fck_nat.instance_public_ip
}

output "nat_autoscaling_group_arn" {
  value = module.fck_nat.autoscaling_group_arn
}
