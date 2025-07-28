# Create a storage account
resource "azurerm_storage_account" "storage_account" {
  name                = "${local.storage_account_name}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  account_kind             = var.storage_account_kind
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  shared_access_key_enabled = var.key_based_authentication
  allow_nested_items_to_be_public = var.allow_blob_public_access


  network_rules {
    default_action = var.network_access_default

    # Configure bypass if bypass isn't an empty list
    bypass         = var.network_trusted_services_bypass
    ip_rules = var.allowed_ips
    dynamic "private_link_access" {
      for_each = var.resource_access != null ? var.resource_access : []
      content {
        endpoint_resource_id = private_link_access.value.endpoint_resource_id
        endpoint_tenant_id   = private_link_access.value.endpoint_tenant_id
      }
    }
  }

  blob_properties {
    dynamic "cors_rule" {
      for_each = var.cors_rules != null ? var.cors_rules : []
      content {
        allowed_origins     = cors_rule.value.allowed_origins
        allowed_methods     = cors_rule.value.allowed_methods
        allowed_headers = cors_rule.value.allowed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
        exposed_headers = cors_rule.value.exposed_headers
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

# Configure diagnostic settings

resource "azurerm_monitor_diagnostic_setting" "diag-blob" {

  depends_on = [
    azurerm_storage_account.storage_account
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/blobServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag-file" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-blob
  ]

  name                       = "diag-file"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/fileServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag-queue" {
  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-file
  ]

  name                       = "diag-default"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/queueServices/default"
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

resource "azurerm_monitor_diagnostic_setting" "diag-table" {

  depends_on = [
    azurerm_storage_account.storage_account,
    azurerm_monitor_diagnostic_setting.diag-queue
  ]

  name                       = "diag-table"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/tableServices/default"
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
