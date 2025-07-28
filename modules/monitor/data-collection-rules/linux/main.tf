resource "azurerm_monitor_data_collection_rule" "rule" {
  name                        = "${local.data_collection_rule_prefix}${var.purpose}${var.random_string}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  kind = "Linux"
  description                 = "This data collection rule captures common Linux logs and metrics"
  data_collection_endpoint_id = var.data_collection_endpoint_id

  destinations {
    log_analytics {
      workspace_resource_id = var.law_resource_id
      name                  = var.law_name
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = [var.law_name]
  }
 
  data_sources {
    syslog {
      facility_names = ["syslog"]
      log_levels     = [
        "Alert",
        "Critical",
        "Emergency"
     ]
      name           = "syslogBase"
      streams        = ["Microsoft-Syslog"]
    }
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
