## Create a public IP address
##
module "public_ip_primary" {
  source = "../../public-ip"

  location            = var.primary_location
  resource_group_name = var.resource_group_name
  purpose             = var.purpose
  location_code       = var.primary_location_code
  random_string       = var.random_string
  dns_label           = "${local.dns_label}p"
  law_resource_id     = var.law_resource_id
  tags                = var.tags
}

module "public_ip_secondary" {
  count = var.secondary_location != null ? 1 : 0
  source = "../../public-ip"

  location            = var.secondary_location
  resource_group_name = var.resource_group_name
  purpose             = var.purpose
  location_code       = var.secondary_location_code
  random_string       = var.random_string
  dns_label           = "${local.dns_label}s"
  law_resource_id     = var.law_resource_id
  tags                = var.tags
}

## Create an Azure API Management service instance
##
resource "azurerm_api_management" "apim" {
  depends_on = [
    module.public_ip_primary,
    module.public_ip_secondary[0]
 ]
  name                = "${local.apim_name_prefix}${var.purpose}${var.primary_location_code}${var.random_string}"
  location            = var.primary_location
  resource_group_name = var.resource_group_name

  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku

  public_ip_address_id = module.public_ip_primary.id
  virtual_network_type = "Internal"

  dynamic additional_location {
    for_each = var.secondary_location != null ? [var.secondary_location] : []
    content {
      location            = var.secondary_location
      public_ip_address_id = module.public_ip_secondary[0].id
      virtual_network_configuration {
        subnet_id = var.subnet_id_secondary
      }
    }
  }

  virtual_network_configuration {
    subnet_id = var.subnet_id_primary
  }

  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 60 seconds after API Management instance is created to allow for system-managed identity to replicate
##
resource "time_sleep" "sleep_rbac" {
  depends_on = [
    azurerm_api_management.apim
]
  create_duration = "60s"
}

## Create Azure RBAC Role Assignment for API Management instance
##
resource "azurerm_role_assignment" "apim_rbac" {
  depends_on = [ 
    time_sleep.sleep_rbac
 ]
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.apim.identity[0].principal_id
}

## Create a diagnostic setting to send logs to Log Analytics
##
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_api_management.apim.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "GatewayLogs"
  }
  enabled_log {
    category = "WebSocketConnectionLogs"
  }
  enabled_log {
    category = "DeveloperPortalAuditLogs"
  }
}

