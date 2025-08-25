locals {
    # Standard naming convention for relevant resources
    app_insights_prefix = "appin"
    aml_workspace_prefix = "aml"
    umi_prefix = "umi" 

    # Settings for Azure Key Vault
    sku_name = "premium"
    rbac_enabled = true
    deployment_vm = true
    deployment_template = true
}

