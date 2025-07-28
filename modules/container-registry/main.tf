resource "azurerm_container_registry" "acr" {
  name                = "${local.acr_name}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku                    = local.sku_name
  admin_enabled          = local.local_admin_enabled
  anonymous_pull_enabled = local.anonymous_pull_enabled

  identity {
    type = "SystemAssigned"
  }

  public_network_access_enabled = var.public_network_access_enabled
  network_rule_set {
    default_action = var.default_network_action
  }
  network_rule_bypass_option = "AzureServices"

  tags = var.tags
}
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}
