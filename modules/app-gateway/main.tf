## Create a public IP address
##
module "public_ip" {
  source = "../public-ip"

  location            = var.location
  resource_group_name = var.resource_group_name
  purpose             = "agw${var.purpose}"
  location_code       = var.location_code
  random_string       = var.random_string
  law_resource_id     = var.law_resource_id
  tags                = var.tags
}

## Create User-Assigned Managed Identity
##
module "umi" {
  source = "../managed-identity"

  location            = var.location
  resource_group_name = var.resource_group_name
  purpose             = "agw${var.purpose}"
  location_code       = var.location_code
  random_string       = var.random_string
  tags                = var.tags
}

## Pause for 10 seconds after user-assigned managed identity is created to allow for it to replicate through Entra IDss
##
resource "time_sleep" "sleep_identity" {
  depends_on = [
    module.umi
]
  create_duration = "10s"
}

## Create an Azure Application Gateway instance
##
resource "azurerm_application_gateway" "agw" {
  depends_on = [ 
    time_sleep.sleep_identity 
  ]

  name                = "${local.agw_name_prefix}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  identity {
    type = "UserAssigned"
    identity_ids = [
      module.umi.id
    ]
  }

  sku {
    name     = var.sku
    tier     = var.sku
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gwipcfg"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = "fecfgpub"
    public_ip_address_id = module.public_ip.id
  }

  frontend_port {
    name = "feportdef"
    port = 80
  }

  backend_address_pool {
    name = "bepdef"
  }

  backend_http_settings {
    name                  = "behsdef"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = "20"
  }

  http_listener {
    name                           = "hldef"
    frontend_ip_configuration_name = "fecfgpub"
    frontend_port_name             = "feportdef"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rrrdef"
    rule_type                  = "Basic"
    http_listener_name         = "hldef"
    backend_address_pool_name  = "bepdef"
    backend_http_settings_name = "behsdef"
    priority = 1

  }

  tags                = var.tags

}

## Create Azure RBAC Role Assignment for Application Gateway instance
##
resource "azurerm_role_assignment" "agw_rbac" {
  depends_on = [ 
    azurerm_application_gateway.agw
 ]
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.umi.principal_id
}

## Create a diagnostic setting to send logs to Log Analytics
##
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_application_gateway.agw.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }
  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }
}

