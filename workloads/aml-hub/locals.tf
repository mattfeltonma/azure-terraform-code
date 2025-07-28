locals {
    # Standard naming convention for relevant resources
    app_insights_prefix = "appin"
    aml_hub_name_prefix = "amlh"
    aml_project_name_prefix = "amlp"
    umi_prefix = "umi"

    # Settings for Azure Key Vault
    sku_name = "premium"
    rbac_enabled = true
    deployment_vm = false
    deployment_template = false
}