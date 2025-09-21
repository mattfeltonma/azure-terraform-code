#################### Create core resources
####################

## Create a random string
##
resource "random_string" "unique" {
  length      = 3
  min_numeric = 3
  numeric     = true
  special     = false
  lower       = true
  upper       = false
}

## Create resource groups
##
resource "azurerm_resource_group" "rg_demo_avnm" {
  name     = "rgdemoavnm${random_string.unique.result}"
  location = var.region_prod
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

#################### Create resources used for logging
####################

## Create a Log Analytics Workspace for resources to centrally log to
##
resource "azurerm_log_analytics_workspace" "law" {
  name                = "lawavnm${local.location_code_prod}${random_string.unique.result}"
  location            = var.region_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

## Create a storage account to store VNet flow logs for each environment
##
resource "azurerm_storage_account" "storage_account_flow_logs" {
  for_each = toset(local.hub_environments)

  name                = "stflowlog${each.key}${each.key == "prod" ? local.location_code_prod : local.location_code_nonprod}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  location            = each.key == "prod" ? var.region_prod : var.region_nonprod
  tags                = local.tags

  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  network_rules {

    # Configure the default action for public network access to block all traffic
    default_action = "Deny"

    # Configure the service to allow trusted Azure services to bypass the service firewall to support VNet flow log delivery
    bypass = [
      "AzureServices"
    ]
    # Allow the trusted IP to bypass the firewall. In most cases this will be the IP you use to demo and the machine being used
    # to deploy the Teraform code
    ip_rules = var.trusted_ips
  }
}

## Configure diagnostic settings for blob and table endpoints for the storage accounts
##
resource "azurerm_monitor_diagnostic_setting" "diag_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_flow_logs
  ]

  for_each = toset(local.hub_environments)

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.storage_account_flow_logs[each.key].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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

resource "azurerm_monitor_diagnostic_setting" "diag_table" {
  depends_on = [
    azurerm_storage_account.storage_account_flow_logs,
    azurerm_monitor_diagnostic_setting.diag_blob
  ]

  for_each = toset(local.hub_environments)

  name                       = "diag-table"
  target_resource_id         = "${azurerm_storage_account.storage_account_flow_logs[each.key].id}/tableServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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

#################### Create resources used for logging
####################

## Create transit virtual networks and their components
module "transit_vnet" {
  for_each = toset(local.hub_environments)

  source = "./modules/transit-vnet"

  address_space_vnet                  = [each.key == "prod" ? local.vnet_cidr_tr_prod : local.vnet_cidr_tr_nonprod]
  bastion                             = each.key == "prod" ? true : false
  environment                         = each.key
  law_region                          = var.region_prod
  law_resource_id                     = azurerm_log_analytics_workspace.law.id
  law_workspace_id                    = azurerm_log_analytics_workspace.law.workspace_id
  random_string                       = random_string.unique.result
  region                              = each.key == "prod" ? var.region_prod : var.region_nonprod
  region_code                         = each.key == "prod" ? local.location_code_prod : local.location_code_nonprod
  resource_group_name_network_watcher = var.network_watcher_resource_group_name
  resource_group_name_workload        = azurerm_resource_group.rg_demo_avnm.name
  storage_account_vnet_flow_logs      = azurerm_storage_account.storage_account_flow_logs[each.key].id
  tags                                = var.tags
  tags_vnet                           = { "env" = each.key, "func" = "hub" }
  vm_admin_username                   = var.vm_admin_username
  vm_admin_password                   = var.vm_admin_password
  vm_sku_size                         = var.vm_sku_size
}

## Create workload virtual networks and their components
##
module "workload_vnets" {
  depends_on = [module.transit_vnet]

  for_each = { for idx, env in local.workload_environments : env.env => env }

  source = "./modules/workload-vnet"

  address_space_vnet                  = [each.value.address_space]
  db_vm                               = each.value.db_vm
  environment                         = each.value.env
  law_region                          = var.region_prod
  law_resource_id                     = azurerm_log_analytics_workspace.law.id
  law_workspace_id                    = azurerm_log_analytics_workspace.law.workspace_id
  random_string                       = random_string.unique.result
  region                              = each.value.region
  region_code                         = each.value.region_code
  resource_group_name_network_watcher = var.network_watcher_resource_group_name
  resource_group_name_workload        = azurerm_resource_group.rg_demo_avnm.name
  storage_account_vnet_flow_logs      = contains(["prod", "pci"], each.value.env) ? azurerm_storage_account.storage_account_flow_logs["prod"].id : azurerm_storage_account.storage_account_flow_logs["nonprod"].id
  tags                                = var.tags
  tags_vnet                           = contains(["prod", "nonprod"], each.value.env) ? { "env" = each.value.env, "func" = "spoke", "wl" = "app1" } : { "env" = "prod", "func" = "spoke", "data" = "pci" }
  vm_admin_username                   = var.vm_admin_username
  vm_admin_password                   = var.vm_admin_password
  vm_sku_size                         = var.vm_sku_size
}

#################### Create central AVNM resources
####################

## Create Azure Virtual Network Manager and configure diagnostic settings
##
resource "azurerm_network_manager" "network_manager_central" {
  depends_on = [
    module.workload_vnets
  ]

  name                = "avnmcentral${random_string.unique.result}"
  description         = "The Central IT Azure Virtual Network Manager instance"
  location            = var.region_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  # Set scope of management to management group allowing it to manage all subscriptions beneath
  scope {
    management_group_ids = [
      var.management_group_id
    ]
  }

  # Set scope of access to enable it to manage connectivity, securityadmin, and routing configurations
  scope_accesses = [
    "Connectivity",
    "SecurityAdmin",
    "Routing"
  ]
  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "diag_avnm_central" {
  name                       = "diag-base"
  target_resource_id         = azurerm_network_manager.network_manager_central.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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

########## Create Network Groups
##########

##### Create Network Groups used across Routing, Configuration, and SecurityAdmin Configurations
#####

## Create a network group for the production spoke virtual networks
##
resource "azurerm_network_manager_network_group" "network_group_central_spoke_prod" {
  name               = "ng-spoke-prod"
  description        = "The network group for spokes in production"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

## Create a network group for the non-production spoke virtual networks
##
resource "azurerm_network_manager_network_group" "network_group_central_spoke_nonprod" {
  name               = "ng-spoke-nonprod"
  description        = "The network group for spokes in non-production"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

##### Create Network Groups used with Routing Configurations
##### AzApi is used to create Network Groups with subnet members because that is not yet supported
##### by AzureRm as of 4.44

## Create a network group for the production Gateway Subnet to be used with a routing configuration
resource "azapi_resource" "network_group_central_gatewaysubnet_prod" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-gatewaysubnet-prod"
  parent_id                 = azurerm_network_manager.network_manager_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains the GatewaySubnet for production"
      memberType  = "Subnet"
    }
  }
}

## Create a network group for the non-production Gateway Subnet to be used with a routing configuration
resource "azapi_resource" "network_group_central_gatewaysubnet_nonprod" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-gatewaysubnet-nonprod"
  parent_id                 = azurerm_network_manager.network_manager_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains the GatewaySubnet for non-production"
      memberType  = "Subnet"
    }
  }
}

## Create a network group for the production and non-production subnets to enable cross region routing
resource "azapi_resource" "network_group_central_fwintsubnet" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-fwint-prod"
  parent_id                 = azurerm_network_manager.network_manager_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains the firewall internal subnets"
      memberType  = "Subnet"
    }
  }
}

##### Create Network Groups used with Connectivity Configurations
#####

## Create a network group for the production and non-production hubs
##
resource "azurerm_network_manager_network_group" "network_group_central_transit_all" {
  name               = "ng-transit-all"
  description        = "The network group containing all transit virtual network across all environments and regions"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

## Create a network group for the spoke virtual networks containing application 1 workloads
##
resource "azurerm_network_manager_network_group" "network_group_central_app1" {
  name               = "ng-spoke-app1"
  description        = "The network group containing application 1 workloads in both production and non-production"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

##### Create Network Groups used with SecurityAdmin Configurations
##### AzApi is used to create Network Groups with subnet members because that is not yet supported
##### by AzureRm as of 4.44

## Create a network group for the spoke virtual networks containing PCI workloads
##
resource "azurerm_network_manager_network_group" "network_group_central_spoke_all_pci" {
  name               = "ng-spoke-all-pci"
  description        = "The network group for spokes running PCI workloads"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

## Create a network group for the subnets where application 1 non-production database servers are deployed to
##
resource "azapi_resource" "network_group_central_subnet_app1_db_nonprod" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-app1-db-nonprod"
  parent_id                 = azurerm_network_manager.network_manager_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains subnets where application 1 non-production database servers are deployed to"
      memberType  = "Subnet"
    }
  }
}

## Create a network group for the spoke virtual networks that should be exempted SecurityAdmin rules
## This will be associated with an allow all traffic SecurityAdmin rule
resource "azurerm_network_manager_network_group" "network_group_central_spoke_exceptions" {
  name               = "ng-spoke-exceptions"
  description        = "The network group for spokes that have an exception to all Security Admin rules"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

##### Create Network Group Static Members to groups which are configured for subnet membership
#####

## Add the application 1 non-production database subnet to the relevant network group
##
resource "azapi_resource" "static_member_central_subnet_app1_db_nonprod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.network_group_central_subnet_app1_db_nonprod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-app1-db-nonprod"
  parent_id                 = azapi_resource.network_group_central_subnet_app1_db_nonprod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.workload_vnets["nonprod"].subnet_id_data
    }
  }
}

## Add the production GatewaySubnet to the relevant network group
##
resource "azapi_resource" "static_member_central_subnet_gatewaysubnet_prod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.network_group_central_gatewaysubnet_prod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-gateway-subnet-prod"
  parent_id                 = azapi_resource.network_group_central_gatewaysubnet_prod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit_vnet["prod"].subnet_id_gateway
    }
  }
}

## Add the non-production GatewaySubnet to the relevant network group
##
resource "azapi_resource" "static_member_central_subnet_gatewaysubnet_nonprod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.network_group_central_gatewaysubnet_nonprod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-gateway-subnet-nonprod"
  parent_id                 = azapi_resource.network_group_central_gatewaysubnet_nonprod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit_vnet["nonprod"].subnet_id_gateway
    }
  }
}

## Add the production firewall private subnet to the relevant network group
##
resource "azapi_resource" "static_member_central_subnet_fwintsubnet_prod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.network_group_central_fwintsubnet
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-fwintsubnet-prod"
  parent_id                 = azapi_resource.network_group_central_fwintsubnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit_vnet["prod"].subnet_id_firewall_private
    }
  }
}

## Add the non-production firewall private subnet to the relevant network group
##
resource "azapi_resource" "static_member_central_subnet_fwintsubnet_nonprod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.network_group_central_fwintsubnet
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-fwintsubnet-nonprod"
  parent_id                 = azapi_resource.network_group_central_fwintsubnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit_vnet["nonprod"].subnet_id_firewall_private
    }
  }
}

########## Create Connectivity Configurations
##########

## Create the central connectivity configuration for hub and spoke in the production environment
##
resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_prod_hubspoke" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  name                  = "cfg-connectivity-prod-hubspoke"
  network_manager_id    = azurerm_network_manager.network_manager_central.id
  connectivity_topology = "HubAndSpoke"

  # This is false because DirectConnectivity is not used in this configuration
  global_mesh_enabled = false

  # Delete existing peers and create the AVNM-managed peerings
  delete_existing_peering_enabled = true

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_spoke_prod.id
    use_hub_gateway    = true
  }

  hub {
    resource_id   = module.transit_vnet["prod"].transit_vnet_id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}

## Create the central connectivity configuration for hub and spoke in the non-production environment
##
resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_nonprod_hubspoke" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  name                  = "cfg-connectivity-nonprod-hubspoke"
  network_manager_id    = azurerm_network_manager.network_manager_central.id
  connectivity_topology = "HubAndSpoke"

  # This is false because DirectConnectivity is not used in this configuration
  global_mesh_enabled = false

  # Delete existing peers and create the AVNM-managed peerings
  delete_existing_peering_enabled = true

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
    use_hub_gateway    = true
  }

  hub {
    resource_id   = module.transit_vnet["nonprod"].transit_vnet_id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}

## Create the central connectivity configuration to mesh the hubs across environments
##
resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_all_mesh_hubs" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  name                  = "cfg-connectivity-all-mesh-hubs"
  network_manager_id    = azurerm_network_manager.network_manager_central.id
  connectivity_topology = "Mesh"

  # Do not mesh spoke virtual networks
  global_mesh_enabled = true

  # Delete existing peers and create the AVNM-managed peerings
  delete_existing_peering_enabled = true

  applies_to_group {
    group_connectivity = "DirectlyConnected"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_transit_all.id
  }
}

## Create the central connectivity configuration to mesh the application 1 workload spoke virtual networks
##
resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_all_mesh_app1_spokes" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  name                  = "cfg-connectivity-all-mesh-app1-spokes"
  network_manager_id    = azurerm_network_manager.network_manager_central.id
  connectivity_topology = "Mesh"

  # Do not mesh spoke virtual networks
  global_mesh_enabled = true

  # Delete existing peers and create the AVNM-managed peerings
  delete_existing_peering_enabled = true

  applies_to_group {
    group_connectivity = "DirectlyConnected"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_app1.id
  }
}

########## Create Routing Configuration, rule collections, and rules
########## AzAPI is used to create routing rules because they are not yet supported by AzureRm as of 4.44

##### Create Routing Configuration
#####

## Create a the central routing configuration
##
resource "azurerm_network_manager_routing_configuration" "routing_config_central" {
  depends_on = [
    azurerm_network_manager.network_manager_central
  ]

  name               = "cfg-routing"
  description        = "The routing configuration for Central IT"
  network_manager_id = azurerm_network_manager.network_manager_central.id
}

##### Create Routing Rule Collections and rules
#####

## Create the routing rule collection for production spoke virtual networks and its relevant rule
## to route traffic from the production spoke virtual network to the production NVA load balancer
resource "azurerm_network_manager_routing_rule_collection" "routing_rule_collection_prod_spokes" {
  name                     = "rc-route-prod-spokes"
  description              = "The routing rule collection to apply to production spokes"
  routing_configuration_id = azurerm_network_manager_routing_configuration.routing_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_prod.id
  ]
  bgp_route_propagation_enabled = false
}

resource "azapi_resource" "routing_rule_prod_spokes_default" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_spokes
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "defaultRoute"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_spokes.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to point the default route to the production NVA load balancer"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = "0.0.0.0/0"
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["prod"].lb_trusted_ip
      }
    }
  }
}

## Create the routing rule collection for non-production spoke virtual networks and its relevant rule
## to route traffic from the non-production spoke virtual network to the non-production NVA load balancer
resource "azurerm_network_manager_routing_rule_collection" "routing_rule_collection_nonprod_spokes" {
  name                     = "rc-route-nonprod-spokes"
  description              = "The routing rule collection to apply to non-production spokes"
  routing_configuration_id = azurerm_network_manager_routing_configuration.routing_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
  ]
  bgp_route_propagation_enabled = false
}

resource "azapi_resource" "routing_rule_nonprod_spokes_default" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_nonprod_spokes
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "defaultRoute"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_nonprod_spokes.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to point the default route to the non-production NVA load balancer"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = "0.0.0.0/0"
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["nonprod"].lb_trusted_ip
      }
    }
  }
}

## Create a routing rule collection for the production GatewaySubnets and relevant rules to route
## traffic from on-premises to spoke virtual networks to the production NVA load balancer
resource "azurerm_network_manager_routing_rule_collection" "routing_rule_collection_prod_gatewaysubnet" {
  name                     = "rc-route-prod-gatewaysubnet"
  description              = "The routing rule collection to apply to the production GatewaySubnet"
  routing_configuration_id = azurerm_network_manager_routing_configuration.routing_config_central.id
  network_group_ids = [
    azapi_resource.network_group_central_gatewaysubnet_prod.id
  ]
  bgp_route_propagation_enabled = true
}

resource "azapi_resource" "routing_rule_prod_gatewaysubnet_prodvnet" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_gatewaysubnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "prodvnet1"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_gatewaysubnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to production spoke 1 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl1_prod
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["prod"].lb_trusted_ip
      }
    }
  }
}

resource "azapi_resource" "routing_rule_prod_gatewaysubnet_pcivnet" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_gatewaysubnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "pcivnet1"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_prod_gatewaysubnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to production spoke 1 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl1_pci
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["prod"].lb_trusted_ip
      }
    }
  }
}

## Create a routing rule collection for the non-production GatewaySubnets and relevant rules to route
## traffic from on-premises to spoke virtual networks to the non-production NVA load balancer
resource "azurerm_network_manager_routing_rule_collection" "routing_rule_collection_nonprod_gatewaysubnet" {
  name                     = "rc-route-nonprod-gatewaysubnet"
  description              = "The routing rule collection to apply to the non-production GatewaySubnet"
  routing_configuration_id = azurerm_network_manager_routing_configuration.routing_config_central.id
  network_group_ids = [
    azapi_resource.network_group_central_gatewaysubnet_nonprod.id
  ]
  bgp_route_propagation_enabled = true
}

resource "azapi_resource" "routing_rule_nonprod_gatewaysubnet_nonprodvnet" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_nonprod_gatewaysubnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "nonprodvnet1"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_nonprod_gatewaysubnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to non-production spoke 1 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl1_nonprod
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["nonprod"].lb_trusted_ip
      }
    }
  }
}

## Create a routing rule collection for production and non-production trusted firewall subnets and the relevant
## rules to enable cross region routing
resource "azurerm_network_manager_routing_rule_collection" "routing_rule_collection_trusted_firewall_subnets" {
  name                     = "rc-route-trusted-firewall-subnets"
  description              = "The routing rule collection to apply to trusted firewall subnets for cross region routing"
  routing_configuration_id = azurerm_network_manager_routing_configuration.routing_config_central.id
  network_group_ids = [
    azapi_resource.network_group_central_fwintsubnet.id
  ]
  bgp_route_propagation_enabled = true
}

# Create routing rule to route traffic to production CIDR block to production NVA trusted load balancer
#
resource "azapi_resource" "routing_rule_prod_cidr" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_trusted_firewall_subnets
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "prod_cidr"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_trusted_firewall_subnets.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic destined for the production environment to the production NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = var.address_space_azure_prod
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["prod"].lb_trusted_ip
      }
    }
  }
}

# Create routing rule to route traffic to non-production CIDR block to non-production NVA trusted load balancer
#
resource "azapi_resource" "routing_rule_nonprod_cidr" {
  depends_on = [
    azurerm_network_manager_routing_rule_collection.routing_rule_collection_trusted_firewall_subnets
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "nonprod_cidr"
  parent_id                 = azurerm_network_manager_routing_rule_collection.routing_rule_collection_trusted_firewall_subnets.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic destined for the non-production environment to the non-production NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = var.address_space_azure_nonprod
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit_vnet["nonprod"].lb_trusted_ip
      }
    }
  }
}

########## Create SecurityAdmin Configuration, rule collections, and rules
########## AzApi is used for SecurityAdmin rules where Network Groups are used as source or destination because this is not supported in AzureRm as of 4.44

##### Create SecurityAdmin Configuration
#####

## Create central SecurityAdmin Configuration
## AzApi is used because AzureRm does not support networkGroupAddressSpaceAggregationOption as of 4.44
resource "azapi_resource" "security_config_central" {
  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations@2024-05-01"
  name                      = "cfg-security_admin"
  parent_id                 = azurerm_network_manager.network_manager_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The SecurityAdmin configuration for Central IT"
      applyOnNetworkIntentPolicyBasedServices = [
        "AllowRulesOnly"
      ]
      # This option allows Network Groups in Security Admin Rules
      networkGroupAddressSpaceAggregationOption = "Manual"
    }
  }
}

##### Create SecurityAdmin Rule Collections and SecurityAdmin Rules
#####

## Create SecurityAdmin Rule Collection and its rules which will apply SecurityAdmin rules to production spoke virtual networks
##
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_prod" {
  name                            = "rc-prod"
  description                     = "The rule collection for production"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_prod.id
  ]
}

# Create SecurityAdmin Rule which will always allow DNS traffic regardless of NSG rules applied to the subnet
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_always_allow_dns_prod" {
  name                     = "AlwaysAllowDns"
  description              = "Always allow DNS traffic to DNS service"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  action                   = "AlwaysAllow"
  direction                = "Outbound"
  priority                 = 1000
  protocol                 = "Any"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["53"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "8.8.8.8/32"
  }
}

# Create SecurityAdmin Rule which will allow Application 1 non-production database subnets to communicate with Application Production database subnets
#
resource "azapi_resource" "security_admin_rule_allow_app1_from_nonprod_prod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.security_config_central,
    azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod
  ]

  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "AllowMySqlNonProd"
  parent_id                 = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  schema_validation_enabled = true

  body = {
    kind = "Custom"
    properties = {
      description = "Allow traffic from non-production db servers",
      protocol    = "Tcp",
      sources = [
        {
          addressPrefixType = "NetworkGroup",
          addressPrefix     = azapi_resource.network_group_central_subnet_app1_db_nonprod.id
        }
      ],
      destinations = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = "*"
        }
      ],
      sourcePortRanges = [
        "0-65535"
      ],
      destinationPortRanges = [
        "3306"
      ],
      access    = "Allow",
      priority  = 2100,
      direction = "Inbound"
    }
  }
}

# Create SecurityAdmin Rule which will allow remote access traffic from production hub virtual network
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_allow_remote_access_prod" {
  name                     = "AllowRemoteAccess"
  description              = "Allow remote access from production jump hosts"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  action                   = "Allow"
  direction                = "Inbound"
  priority                 = 2110
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges = [
    "2222",
    "3389"
  ]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = local.vnet_cidr_tr_prod
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

# Create SecurityAdmin Rule which will block non-production from communicating with production
#
resource "azapi_resource" "security_admin_rule_block_nonprod_from_prod" {
  depends_on = [
    azurerm_network_manager.network_manager_central,
    azapi_resource.security_config_central,
    azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod
  ]

  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "DenyNonProd"
  parent_id                 = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  schema_validation_enabled = true

  body = {
    kind = "Custom"
    properties = {
      description = "Block non-production from communicating with production",
      protocol    = "Any",
      sources = [
        {
          addressPrefixType = "NetworkGroup",
          addressPrefix     = azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
        }
      ],
      destinations = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = "*"
        }
      ],
      sourcePortRanges = [
        "0-65535"
      ],
      destinationPortRanges = [
         "0-65535"
      ],
      access    = "Deny",
      priority  = 3000,
      direction = "Inbound"
    }
  }
}

# Create SecurityAdmin Rule which will block all remote access traffic from all sources to production
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_deny_remote_access_all_prod" {
  name                     = "DenyRemoteAccessFromAll"
  description              = "Deny remote access from all sources"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 3010
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["22", "2222", "3389"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

## Create SecurityAdmin Rule Collection and its rules which will apply SecurityAdmin rules to non-production spoke virtual networks
##
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_nonprod" {
  name                            = "rc-nonprod"
  description                     = "The rule collection for non-production"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
  ]
}

# Create SecurityAdmin Rule which will always allow DNS traffic regardless of NSG rules applied to the subnet
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_always_allow_dns_non_prod" {
  name                     = "AlwaysAllowDns"
  description              = "Always allow DNS traffic to DNS service"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_nonprod.id
  action                   = "AlwaysAllow"
  direction                = "Outbound"
  priority                 = 1100
  protocol                 = "Any"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["53"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "8.8.8.8/32"
  }
}

# Create SecurityAdmin Rule which will allow remote access traffic from non-production hub virtual network
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_allow_remote_access_nonprod" {
  name                     = "AllowRemoteAccess"
  description              = "Allow remote access non-production jump hosts"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_nonprod.id
  action                   = "AlwaysAllow"
  direction                = "Outbound"
  priority                 = 2200
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges = [
    "3389",
    "2222"
  ]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = local.vnet_cidr_tr_nonprod
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

# Create SecurityAdmin Rule which will block all remote access traffic from all sources to non-production
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_deny_remote_access_all_nonprod" {
  name                     = "DenySshFromAll"
  description              = "Deny SSH from all sources"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_nonprod.id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 3100
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["22", "2222", "3389"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

## Create SecurityAdmin Rule Collection and its rules which will apply SecurityAdmin rules to PCI spoke virtual networks
##
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_pci" {
  name                            = "rc-pci"
  description                     = "The rule collection for PCI workloads"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_all_pci.id
  ]
}

# Create SecurityAdmin Rule which will block all HTTP traffic from all sources to PCI workloads
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_deny_http_from_all_to_pci" {
  name                     = "DenyHttp"
  description              = "Deny all HTTP traffic"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_pci.id
  action                   = "AlwaysAllow"
  direction                = "Inbound"
  priority                 = 3200
  protocol                 = "Any"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["80"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

## Create SecurityAdmin Rule Collection and its rules which will exempt virtual networks from all SecurityAdmin rules
##
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_exceptions" {
  name                            = "rc-exceptions"
  description                     = "The rule collection for exceptions to remote access"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_exceptions.id
  ]
}

# Create SecurityAdmin Rule which will exempt virtual networks from all SecurityAdmin rules
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_allow_all" {
  name                     = "AllowRemoteAccessFromAll"
  description              = "Do not filter traffic with Security Admin Rules"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_exceptions.id
  action                   = "Allow"
  direction                = "Inbound"
  priority                 = 2000
  protocol                 = "Tcp"
  source_port_ranges       = ["0-65535"]
  destination_port_ranges  = ["2222"]
  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
}

########## Create IPAM Resources
##########

##### Create IPAM Pools
#####

## Create IPAM pool for on-premises
##
resource "azurerm_network_manager_ipam_pool" "ipam_org_on_prem_pool" {
  name               = "pool-org-onprem"
  location           = var.region_prod
  network_manager_id = azurerm_network_manager.network_manager_central.id
  display_name       = "pool-org-onprem"
  description        = "The primary pool for the organization used on-premises"
  address_prefixes   = [var.address_space_onpremises]
  tags               = var.tags
}

# Create Static CIDR to represent on-premises and assign to on-premises IPAM pool
#
resource "azurerm_network_manager_ipam_pool_static_cidr" "ipam_org_pool_allocation_on_premises_lab" {
  name         = "example-ipsc"
  ipam_pool_id = azurerm_network_manager_ipam_pool.ipam_org_on_prem_pool.id
  address_prefixes = [
    cidrsubnet(var.address_space_onpremises, 8, 0)
  ]
}

## Create IPAM pool for all of Azure
##
resource "azurerm_network_manager_ipam_pool" "ipam_org_azure_pool" {
  name               = "pool-org-azure"
  location           = var.region_prod
  network_manager_id = azurerm_network_manager.network_manager_central.id
  display_name       = "pool-org-azure"
  description        = "The pool dedicated to all of Azure"
  address_prefixes = [
    var.address_space_cloud
  ]
  tags = var.tags
}

## Create IPAM pool for production
##
resource "azurerm_network_manager_ipam_pool" "ipam_org_prod_pool" {
  name               = "pool-org-prod"
  location           = var.region_prod
  network_manager_id = azurerm_network_manager.network_manager_central.id
  parent_pool_name   = azurerm_network_manager_ipam_pool.ipam_org_azure_pool.name
  display_name       = "pool-org-prod"
  description        = "The pool dedicated to production environment"
  address_prefixes = [
    var.address_space_azure_prod
  ]
  tags = var.tags
}

## Create IPAM pool for non-production
##
resource "azurerm_network_manager_ipam_pool" "ipam_org_nonprod_pool" {
  name               = "pool-org-nonprod"
  location           = var.region_nonprod
  network_manager_id = azurerm_network_manager.network_manager_central.id
  parent_pool_name   = azurerm_network_manager_ipam_pool.ipam_org_azure_pool.name
  display_name       = "pool-org-nonprod"
  description        = "The pool dedicated to non-production environment"
  address_prefixes = [
    var.address_space_azure_nonprod
  ]
  tags = var.tags
}

## Create IPAM pool for the business unit
##
resource "azurerm_network_manager_ipam_pool" "ipam_org_bu_pool" {
  name               = "pool-org-bu"
  location           = var.region_prod
  network_manager_id = azurerm_network_manager.network_manager_central.id
  parent_pool_name   = azurerm_network_manager_ipam_pool.ipam_org_prod_pool.name
  display_name       = "pool-org-bu"
  description        = "The pool dedicated to the business unit"
  address_prefixes = [
    cidrsubnet(var.address_space_azure_prod, 2, 3)
  ]
  tags = var.tags
}

#################### Create Azure Policies which will be used with AVNM Network Group dynamic membership
####################

########## Create Azure Policy definitions
##########

##### Create Azure Policy Definition that adds virtual networks to the all spoke production network group if they are tagged with func=spoke and env=prod
#####
resource "azurerm_policy_definition" "policy_add_spokes_prod_to_prod_network_group" {
  name                = "custom-avnm-production-spoke"
  policy_type         = "Custom"
  mode                = "Microsoft.Network.Data"
  display_name        = "Custom Policy - AVNM Production Spokes"
  description         = "Automatically adds production virtual network spokes to the AVNM group for production spokes"
  management_group_id = var.management_group_id
  metadata = jsonencode({
    "version" : "1.0.0",
    "category" : "Network"
  })
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Network/virtualNetworks"
        },
        {
          "allOf" : [
            {
              "field" : "tags['env']",
              "equals" : "prod"
            },
            {
              "field" : "tags['func']",
              "equals" : "spoke"
            }
          ]
        }
      ]
    },
    "then" : {
      "effect" : "addToNetworkGroup",
      "details" : {
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_spoke_prod.id
      }
    }
  })
}

##### Create Azure Policy Definition that adds virtual networks to the all spoke non-production network group if they are tagged with func=spoke and env=nonprod
#####
resource "azurerm_policy_definition" "policy_add_spokes_prod_to_nonprod_network_group" {
  name                = "custom-avnm-nonproduction-spoke"
  policy_type         = "Custom"
  mode                = "Microsoft.Network.Data"
  display_name        = "Custom Policy - AVNM Non-Production Spokes"
  description         = "Automatically adds non-production virtual network spokes to the AVNM group for non-production spokes"
  management_group_id = var.management_group_id
  metadata = jsonencode({
    "version" : "1.0.0",
    "category" : "Network"
  })
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Network/virtualNetworks"
        },
        {
          "allOf" : [
            {
              "field" : "tags['env']",
              "equals" : "nonprod"
            },
            {
              "field" : "tags['func']",
              "equals" : "spoke"
            }
          ]
        }
      ]
    },
    "then" : {
      "effect" : "addToNetworkGroup",
      "details" : {
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
      }
    }
  })
}

##### Create Azure Policy Definition that adds virtual networks to the PCI network groups if they are tagged with data=pci
#####
resource "azurerm_policy_definition" "policy_add_spokes_pci_to_pci_network_group" {
  name                = "custom-avnm-pci-spoke"
  policy_type         = "Custom"
  mode                = "Microsoft.Network.Data"
  display_name        = "Custom Policy - AVNM PCI Spokes"
  description         = "Automatically adds PCI virtual network spokes to the AVNM group for PCI spokes"
  management_group_id = var.management_group_id
  metadata = jsonencode({
    "version" : "1.0.0",
    "category" : "Network"
  })
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Network/virtualNetworks"
        },
        {
          "allOf" : [
            {
              "field" : "tags['data']",
              "equals" : "pci"
            }
          ]
        }
      ]
    },
    "then" : {
      "effect" : "addToNetworkGroup",
      "details" : {
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_spoke_all_pci.id
      }
    }
  })
}

##### Create Azure Policy Definition that adds virtual networks to the all hub network group if they are tagged with func=hub
#####
resource "azurerm_policy_definition" "policy_add_hub_to_hub_network_group" {
  name                = "custom-avnm-all-hub"
  policy_type         = "Custom"
  mode                = "Microsoft.Network.Data"
  display_name        = "Custom Policy - AVNM all Hubs"
  description         = "Automatically adds hub virtual networks to the AVNM group for all hubs"
  management_group_id = var.management_group_id
  metadata = jsonencode({
    "version" : "1.0.0",
    "category" : "Network"
  })
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Network/virtualNetworks"
        },
        {
          "allOf" : [
            {
              "field" : "tags['func']",
              "equals" : "hub"
            }
          ]
        }
      ]
    },
    "then" : {
      "effect" : "addToNetworkGroup",
      "details" : {
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_transit_all.id
      }
    }
  })
}

##### Create Azure Policy Definition that adds virtual networks to the sql workload network group if they are tagged with wl=app1
#####
resource "azurerm_policy_definition" "policy_add_hub_to_app1_network_group" {
  name                = "custom-avnm-all-app1"
  policy_type         = "Custom"
  mode                = "Microsoft.Network.Data"
  display_name        = "Custom Policy - AVNM App1 Spokes"
  description         = "Automatically adds virtual networks hosting App1's workload to the AVNM group for App1"
  management_group_id = var.management_group_id
  metadata = jsonencode({
    "version" : "1.0.0",
    "category" : "Network"
  })
  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Network/virtualNetworks"
        },
        {
          "allOf" : [
            {
              "field" : "tags['wl']",
              "equals" : "app1"
            }
          ]
        }
      ]
    },
    "then" : {
      "effect" : "addToNetworkGroup",
      "details" : {
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_app1.id
      }
    }
  })
}

########## Create Azure Policy assignments
##########

##### Assign policies to the resource group created in this demo
#####
resource "azurerm_resource_group_policy_assignment" "policy_assignment_add_spokes_prod_to_prod_network_group" {
  name                 = "custom-avnm-production-spoke"
  policy_definition_id = azurerm_policy_definition.policy_add_spokes_prod_to_prod_network_group.id
  resource_group_id    = azurerm_resource_group.rg_demo_avnm.id
}

resource "azurerm_resource_group_policy_assignment" "policy_assignment_spokes_prod_to_nonprod_network_group" {
  name                 = "custom-avnm-nonproduction-spoke"
  policy_definition_id = azurerm_policy_definition.policy_add_spokes_prod_to_nonprod_network_group.id
  resource_group_id    = azurerm_resource_group.rg_demo_avnm.id
}

resource "azurerm_resource_group_policy_assignment" "policy_assignment_spokes_pci_to_pci_network_group" {
  name                 = "custom-avnm-pci-spoke"
  policy_definition_id = azurerm_policy_definition.policy_add_spokes_pci_to_pci_network_group.id
  resource_group_id    = azurerm_resource_group.rg_demo_avnm.id
}

resource "azurerm_resource_group_policy_assignment" "policy_assignment_hub_to_hub_network_group" {
  name                 = "custom-avnm-all-hub"
  policy_definition_id = azurerm_policy_definition.policy_add_hub_to_hub_network_group.id
  resource_group_id    = azurerm_resource_group.rg_demo_avnm.id
}

resource "azurerm_resource_group_policy_assignment" "policy_assignment_hub_to_app1_network_group" {
  name                 = "custom-avnm-all-app1"
  policy_definition_id = azurerm_policy_definition.policy_add_hub_to_app1_network_group.id
  resource_group_id    = azurerm_resource_group.rg_demo_avnm.id
}

#################### Create BU AVNM resources
####################

## Create Azure Virtual Network Manager and configure diagnostic settings
##
resource "azurerm_network_manager" "network_manager_bu" {
  name                = "avnmbu${random_string.unique.result}"
  description         = "The BU Azure Virtual Network Manager instance"
  location            = var.region_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  # Set scope of management to management group allowing it to manage all subscriptions beneath
  scope {
    subscription_ids = [
      data.azurerm_subscription.current.id
    ]
  }

  # Set scope of access to enable it to manage connectivity, securityadmin, and routing configurations
  scope_accesses = [
    "Connectivity",
    "SecurityAdmin",
    "Routing"
  ]
  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "diag_avnm_bu" {
  name                       = "diag-base"
  target_resource_id         = azurerm_network_manager.network_manager_bu.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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

########## Create Network Groups
##########

##### Create Network Groups used by SecurityAdmin Configurations and add static members
#####

## Create Network Group which will contain all BU production spoke virtual networks
##
resource "azurerm_network_manager_network_group" "network_group_bu_spoke_prod" {
  name               = "ng-spoke-prod-bu"
  description        = "The network group for BU spokes in production"
  network_manager_id = azurerm_network_manager.network_manager_bu.id
}

## Add the production virtual network to the network group as a static member
##
resource "azurerm_network_manager_static_member" "static_member_bu_spoke_prod" {
  name                      = "mem-vnet-prod-workload"
  network_group_id          = azurerm_network_manager_network_group.network_group_bu_spoke_prod.id
  target_virtual_network_id = module.workload_vnets["prod"].workload_vnet_id
}

##### Create SecurityAdmin Configuration
#####

## Create business unit SecurityAdmin Configuration
## AzApi is used because AzureRm does not support networkGroupAddressSpaceAggregationOption as of 4.44
resource "azapi_resource" "security_config_bu" {
  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations@2024-05-01"
  name                      = "cfg-security_admin"
  parent_id                 = azurerm_network_manager.network_manager_bu.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The SecurityAdmin configuration for BU"
      applyOnNetworkIntentPolicyBasedServices = [
        "AllowRulesOnly"
      ]
      # This option allows Network Groups in Security Admin Rules
      networkGroupAddressSpaceAggregationOption = "Manual"
    }
  }
}

##### Create SecurityAdmin Rule Collections and SecurityAdmin Rules
#####


## Create Azure Virtual Network Manager BU Security Admin Rule Collections
##
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_bu_sec_prod" {
  name                            = "rc-prod"
  description                     = "The rule collection for production BU spokes"
  security_admin_configuration_id = azapi_resource.security_config_bu.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_bu_spoke_prod.id
  ]
}

## Create Security Admin Rule for BU production rule collection
##
resource "azapi_resource" "security_admin_rule_allow_remote_access_prod_bu" {
  depends_on = [
    azurerm_network_manager.network_manager_bu,
    azapi_resource.security_config_bu,
    azurerm_network_manager_admin_rule_collection.rule_collection_bu_sec_prod
  ]

  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "AllowRemoteAccess"
  parent_id                 = azurerm_network_manager_admin_rule_collection.rule_collection_bu_sec_prod.id
  schema_validation_enabled = true

  body = {
    kind = "Custom"
    properties = {
      description = "Allow remote access from all source to the BU servers",
      protocol    = "Tcp",
      sources = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = "*"
        }
      ],
      destinations = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = "*"
        }
      ],
      sourcePortRanges = [
        "0-65535"
      ],
      destinationPortRanges = [
        "3389",
        "2222",
        "22"
      ],
      access    = "Allow",
      priority  = 2000,
      direction = "Inbound"
    }
  }
}

############### Perform remaining actions to exercises AVNM features
###############

## Create an Azure RBAC Role assignment granting the user the ability to use the BU IPAM pool
##
resource "azurerm_role_assignment" "ipam_pool_user_bu_pool" {
  depends_on = [
    azurerm_network_manager_ipam_pool.ipam_org_bu_pool
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_demo_avnm.name}${var.user_object_id}${azurerm_network_manager_ipam_pool.ipam_org_bu_pool.name}pooluser")
  scope                = azurerm_network_manager_ipam_pool.ipam_org_bu_pool.id
  role_definition_name = "IPAM Pool User"
  principal_id         = var.user_object_id
}

## Create BU virtual network to demonstrate consumption of IPAM pool
##
resource "azurerm_virtual_network" "vnet_bu" {
  name                = "vnetbu${local.location_code_prod}${random_string.unique.result}"
  location            = var.region_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  ip_address_pool {
    id                     = azurerm_network_manager_ipam_pool.ipam_org_bu_pool.id
    number_of_ip_addresses = 256
  }
  dns_servers = ["168.63.129.16"]
  tags        = var.tags
}

