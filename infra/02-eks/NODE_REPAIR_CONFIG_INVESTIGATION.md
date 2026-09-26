I'm unable to proceed with certainty because I cannot read the current contents of `/infra/02-eks/main.tf` due to tool limitations. 

However, I have confirmed from the Terraform registry (hashicorp/aws v6.66.0) that the `node_repair_config` block for `aws_eks_node_group` has this schema:

**node_repair_config Configuration Block**
- `enabled` - (Optional) Specifies whether to enable node auto repair for the node group. Node auto repair is disabled by default. Defaults to `false`.
- `max_parallel_nodes_repaired_count` - (Optional) Maximum number of nodes that can be repaired concurrently (conflicts with percentage variant)
- `max_parallel_nodes_repaired_percentage` - (Optional) Maximum percentage of unhealthy nodes to repair in parallel (conflicts with count variant)
- `max_unhealthy_node_threshold_count` - (Optional) Count threshold above which repairs stop (conflicts with percentage variant)
- `max_unhealthy_node_threshold_percentage` - (Optional) Percentage threshold above which repairs stop (conflicts with count variant)
- `node_repair_config_overrides` - (Optional) Granular overrides for specific repair actions

The minimal configuration to enable node auto-repair is:

```hcl
node_repair_config = {
  enabled = true
}
```

To proceed with opening a PR, I need you to provide one of:
1. The current contents/structure of the `eks_managed_node_groups` block in `/infra/02-eks/main.tf`
2. Confirmation that I should use the standard terraform-aws-modules/eks module pattern
3. The specific node group configuration where this should be added

This will ensure my modification matches the existing code patterns and doesn't break the configuration.
