# Get the current subscription id that is being deployed to
#
data "azurerm_subscription" "current" {}

# Get the identity being used to deploy the Terraform
#
data "azurerm_client_config" "identity_config" { }