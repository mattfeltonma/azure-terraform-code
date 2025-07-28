locals {
  # Configure standard naming convention for relevant resources
  fw_name = "fw"
  fw_policy_name = "fp"
  ip_group_name = "ig"

  # Configure three character code for purpose of vnet
  fw_purpose = "cnt"

  # Add additional tags
  required_tags = {
    cycle = "true"
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}
