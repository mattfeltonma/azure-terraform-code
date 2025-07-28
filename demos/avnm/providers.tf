# Setup providers
provider "azapi" {
  auxiliary_tenant_ids = ["d6c1733b-a2a1-4c7f-XXXXXXXXXXXX"]
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}