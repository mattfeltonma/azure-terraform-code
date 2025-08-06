########## Create a resource group for the AML Registry
##########
resource "azurerm_resource_group" "rgreg" {
  name     = "rgamlr${var.location_code}${var.random_string}"
  location = var.location
  tags     = var.tags
}

########## Create the AML Registry and diagnostic settings
##########

## Create the AML Registry
##
resource "azapi_resource" "registry" {
  depends_on = [
    azurerm_resource_group.rgreg
  ]

  type                      = "Microsoft.MachineLearningServices/registries@2025-06-01"
  name                      = "${local.aml_registry_prefix}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rgreg.id
  location                  = var.location
  schema_validation_enabled = true
 
  body = {
    # Set the identity for the AML Registry to use
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
      managedResourceGroupSettings = length(var.object_id_manage_resource_group) > 0 ? {
        assignedIdentities = [
          for object_id in var.object_id_manage_resource_group : {
            principalId = object_id
          }
        ]
      } : null
      publicNetworkAccess = "Disabled"
    }

    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.regionDetails",
    "properties"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AML Registry storage account and container registry
##
resource "azurerm_monitor_diagnostic_setting" "diag_storage_blob" {
  depends_on = [
    azapi_resource.registry
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azapi_resource.registry.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/blobServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_file" {
  depends_on = [
    azapi_resource.registry,
    azurerm_monitor_diagnostic_setting.diag_storage_blob
  ]

  name                       = "diag-file"
  target_resource_id         = "${azapi_resource.registry.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/fileServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_queue" {
  depends_on = [
    azapi_resource.registry,
    azurerm_monitor_diagnostic_setting.diag_storage_file
  ]

  name                       = "diag-default"
  target_resource_id         = "${azapi_resource.registry.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/queueServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_storage_table" {

  depends_on = [
    azapi_resource.registry,
    azurerm_monitor_diagnostic_setting.diag_storage_queue
  ]

  name                       = "diag-table"
  target_resource_id         = "${azapi_resource.registry.output.properties.regionDetails[0].storageAccountDetails[0].systemCreatedStorageAccount.armResourceId.resourceId}/tableServices/default"
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_acr" {
  name                       = "diag-base"
  target_resource_id         = azapi_resource.registry.output.properties.regionDetails[0].acrDetails[0].systemCreatedAcrAccount.armResourceId.resourceId
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}