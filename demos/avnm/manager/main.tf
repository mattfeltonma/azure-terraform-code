resource "azurerm_network_manager" "vnm-central" {
  name                = var.name
  description         = var.description
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  scope {
    management_group_ids = var.management_scope.management_group_ids
    subscription_ids     = var.management_scope.subscription_ids
  }
  scope_accesses = var.configurations_supported


  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_network_manager.vnm-central.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "NetworkGroupMembershipChange"
  }

  enabled_log {
    category = "RuleCollectionChange"
  }

  enabled_log {
    category = "ConnectivityConfigurationChange"
  }
}
