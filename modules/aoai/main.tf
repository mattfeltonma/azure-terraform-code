## Create an Azure OpenAI Service instance
##
resource "azurerm_cognitive_account" "openai" {
  name                = "${local.openai_name}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"

  custom_subdomain_name = "${local.openai_name}${var.purpose}${var.location_code}${var.random_string}"
  sku_name              = "S0"

  public_network_access_enabled = var.public_network_access

  # Enable outbound restrictions by default
  outbound_network_access_restricted = true
  fqdns = var.allowed_fqdn_list

  # Ensure AzureServices (Trusted Azure Services toggle) bypasses service firewall
  network_acls {
    default_action = var.network_access_default
    ip_rules = var.allowed_ips
    bypass = "AzureServices"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings
##
resource "azurerm_monitor_diagnostic_setting" "diag" {
  name                       = "diag"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "AzureOpenAIRequestUsage"
  }
  
  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Trace"
  }
}


## Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "openai_deployment_gpt_4o" {
  depends_on = [
    azurerm_cognitive_account.openai
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  sku {
    name     = "DataZoneStandard"
    capacity = 100
  }

  model {
    format = "OpenAI"
    name   = "gpt-4o"
  }
}

## Create a deployment for the text-embedding-3-large embededing model
##
resource "azurerm_cognitive_deployment" "openai_deployment_text_embedding_3_large" {
  depends_on = [
    azurerm_cognitive_account.openai,
    azurerm_cognitive_deployment.openai_deployment_gpt_4o
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  sku {
    name     = "Standard"
    capacity = 50
  }

  model {
    format = "OpenAI"
    name   = "text-embedding-3-large"
  }
}
