locals {
    # Standard naming convention for relevant resources
    ai_foundry_resource_prefix = "aif"
    umi_prefix = "umi"

    # Create conditional locals
    cmk_umi = var.encryption == "cmk" && var.managed_identity == "user_assigned"
    cmk_smi = var.encryption == "cmk" && var.managed_identity == "system_assigned"
}