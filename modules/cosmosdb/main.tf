## Create Cosmos DB account
##
resource "azurerm_cosmosdb_account" "cosmosdb" {
  name                = "${local.cosmosdb_prefix}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # General settings
  offer_type        = "Standard"
  kind              = "GlobalDocumentDB"
  free_tier_enabled = false

  # Set security-related settings
  local_authentication_disabled = var.local_authentication_disabled
  public_network_access_enabled = var.public_network_access_enabled

  # Set high availability and failover settings
  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false

  # Configure consistency settings
  consistency_policy {
    consistency_level = "Session"
  }

  # Configure single location with no zone redundancy to reduce costs
  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }
}

# Create diagnostic settings for the Cosmos DB account
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  depends_on = [
    azurerm_cosmosdb_account.cosmosdb
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_cosmosdb_account.cosmosdb.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "MongoRequests"
  }

  enabled_log {
    category = "QueryRuntimeStatistics"
  }

  enabled_log {
    category = "PartitionKeyStatistics"
  }

  enabled_log {
    category = "PartitionKeyRUConsumption"
  }

  enabled_log {
    category = "ControlPlaneRequests"
  }

  enabled_log {
    category = "CassandraRequests"
  }

  enabled_log {
    category = "GremlinRequests"
  }

  enabled_log {
    category = "TableApiRequests"
  }
}
