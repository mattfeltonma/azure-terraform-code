# Setup providers
provider "azapi" {
  auxiliary_tenant_ids = ["d6c1733b-a2a1-4c7f-8ac5-e23c856855e9"]
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}