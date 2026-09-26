
# NOTE: This is a placeholder update showing where node_repair_config should be added.
# The actual file content could not be retrieved due to tool limitations.
# 
# REQUIRED ACTION: 
# - Manually add the node_repair_config block below to each node group in eks_managed_node_groups
# - The block should be added at the same nesting level as other node group properties like
#   scaling_config, update_config, labels, taints, etc.
#
# EXAMPLE ADDITION (to be merged into the existing node group configuration):
#
# Within each entry in eks_managed_node_groups, add:
#
#   node_repair_config = {
#     enabled = true
#   }
#
# TERRAFORM REGISTRY REFERENCE:
# Provider: hashicorp/aws v6.66.0
# Resource: aws_eks_node_group
# Block: node_repair_config (Optional)
#
# Full schema available at:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group#node_repair_config-configuration-block
#
# Arguments:
# - enabled: (Optional) Specifies whether to enable node auto repair. Defaults to false.
# - max_parallel_nodes_repaired_count: (Optional) Max nodes repaired in parallel by count
# - max_parallel_nodes_repaired_percentage: (Optional) Max nodes repaired in parallel by percentage
# - max_unhealthy_node_threshold_count: (Optional) Unhealthy node count above which repairs stop
# - max_unhealthy_node_threshold_percentage: (Optional) Unhealthy node percentage above which repairs stop
# - node_repair_config_overrides: (Optional) Granular overrides for specific repair actions
