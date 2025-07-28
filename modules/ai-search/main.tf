# Create an AI Search service with local authentication disabled
resource "azapi_resource" "ai_search" {
  type                      = "Microsoft.Search/searchServices@2024-03-01-preview"
  name                      = "${local.ai_search_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    sku = {
      name = var.sku
    }

    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # Search-specific properties
      replicaCount = 1
      partitionCount = 1
      hostingMode = "default"
      semanticSearch = "standard"

      # Identity-related controls
      disableLocalAuth = false
      authOptions = {
        aadOrApiKey = {
                aadAuthFailureMode = "http401WithBearerChallenge"
        }
      }
      # Networking-related controls
      publicNetworkAccess = var.public_network_access
      networkRuleSet = {
        bypass = var.trusted_services_bypass
        ipRules = var.allowed_ips != null ? var.allowed_ips : []
      }
    }
    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]
  
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

# Create diagnostic settings for the Azure AI Search service
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  depends_on = [
    azapi_resource.ai_search
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.ai_search.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "OperationLogs"
  }
}
