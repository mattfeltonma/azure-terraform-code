resource "azapi_resource" "domain_list_alert" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlalert${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
        "reddit.com"
      ]
    }
    tags = var.tags
  }
}

resource "azapi_resource" "domain_list_blocked" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlblocked${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
        "homersimpson.com"
      ]
    }
    tags = var.tags
  }
}

resource "azapi_resource" "domain_list_allow" {
  type                      = "Microsoft.Network/dnsResolverDomainLists@2025-05-01"
  name                      = "dlallow${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      domains = [
        "."
      ]
    }
    tags = var.tags
  }
}

resource "azapi_resource" "drp_enterprise" {
  depends_on = [ 
    azapi_resource.domain_list_allow,
    azapi_resource.domain_list_blocked,
    azapi_resource.domain_list_alert
   ]

  type                      = "Microsoft.Network/dnsResolverPolicies@2025-05-01"
  name                      = "drpent${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    tags = var.tags
  }
}

# Create diagnostic settings for the Cosmos DB account
resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.drp_enterprise.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "DnsResponse"
  }
}

resource "azapi_resource" "drpr_block_malicious" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drprblockmalicious"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 100
      action = {
        actionType = "Block"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_blocked.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

resource "azapi_resource" "drpr_alert" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drpralert"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 110
      action = {
        actionType = "Alert"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_alert.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

resource "azapi_resource" "drpr_allow_all" {
  depends_on = [
    azapi_resource.drp_enterprise
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2025-05-01"
  name                      = "drprallowall"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      priority = 120
      action = {
        actionType = "Allow"
      }
      dnsResolverDomainLists = [
        {
          id = azapi_resource.domain_list_allow.id
        }
      ]
      dnsSecurityRuleState = "Enabled"
    }
    tags = var.tags
  }
}

resource "azapi_resource" "vnet_link_drp_enterprise" {
  depends_on = [
    azapi_resource.drp_enterprise,
    azapi_resource.drpr_block_malicious,
    azapi_resource.drpr_allow_all,
    azapi_resource.drpr_alert
  ]

  type                      = "Microsoft.Network/dnsResolverPolicies/virtualNetworkLinks@2025-05-01"
  name                      = "vnetlink${azapi_resource.drp_enterprise.name}${var.vnet_name}"
  parent_id                 = azapi_resource.drp_enterprise.id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    properties = {
      virtualNetwork = {
        id = var.vnet_id
      }
    }
    tags = var.tags
  }
}