##### Create the base resources
#####

## Create resource group
##
resource "azurerm_resource_group" "rgwork" {

  name     = "rgamlr${var.location_code}${var.random_string}"
  location = var.location
  tags = var.tags
}

## Create a Log Analytics Workspace
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rgwork.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##### Create the Azure Machine Learning Registry
#####

## Create the Azure Machine Learning Registry
##
resource "azapi_resource" "registry" {
  depends_on = [
    azurerm_resource_group.rgwork
  ]

  type                      = "Microsoft.MachineLearningServices/registries@2025-01-01-preview"
  name                      = "${local.aml_registry_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rgwork.id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      regionDetails = [
        {
          location = var.location
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountType       = "Standard_LRS"
                storageAccountHnsEnabled = false
              }
            }
          ]
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountSku = "Premium"
              }
            }
          ]

        }
      ]
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause 10 seconds to ensure the managed identity has replicated
##
resource "time_sleep" "wait_registry_identity" {
  depends_on = [
    azapi_resource.registry
  ]
  create_duration = "10s"
}

##### Create the Private Endpoints for the registry
#####

module "private_endpoint_aml_registry" {
  depends_on = [
    azapi_resource.registry
  ]

  source              = "../../modules/private-endpoint"
  
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = azapi_resource.registry.name
  resource_id      = azapi_resource.registry.id
  subresource_name = "amlregistry"

  

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms"
  ]
}

