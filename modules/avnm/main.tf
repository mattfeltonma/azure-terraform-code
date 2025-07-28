# Create a random string
#
resource "random_string" "unique" {
  length      = 3
  min_numeric = 3
  numeric     = true
  special     = false
  lower       = true
  upper       = false
}

# Create resource groups
#
resource "azurerm_resource_group" "rg_demo_avnm" {
  name     = "rgdemoavnm${random_string.unique.result}"
  location = var.location_prod
  tags     = local.tags
}

# Create Log Analytics Workspace and Data Collection Endpoints and Data Collection Rules for Windows and Linux in primary region
#
module "law" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm
  ]

  source                        = "../monitor/log-analytics-workspace"
  random_string                 = random_string.unique.result
  purpose                       = local.law_purpose
  location_primary              = var.location_prod
  location_secondary            = var.location_nonprod
  location_code_primary         = local.location_code_prod
  location_code_secondary       = local.location_code_nonprod
  resource_group_name_primary   = azurerm_resource_group.rg_demo_avnm.name
  resource_group_name_secondary = azurerm_resource_group.rg_demo_avnm.name
  tags                          = local.tags
}

##### Build infrastructure required for demonstration
#####

# Create Storage Account for Flow Logs
#
module "storage-account-flow-logs-prod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location_prod
  location_code       = local.location_code_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  tags                = local.tags

  law_resource_id = module.law.id
}

module "storage-account-flow-logs-nonprod" {
  depends_on = [
    module.storage-account-flow-logs-prod,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location_nonprod
  location_code       = local.location_code_nonprod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  tags                = local.tags

  law_resource_id = module.law.id
}

# Build hub virtual networks
#
module "transit-vnet-prod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law,
    module.storage-account-flow-logs-prod
  ]

  source              = "../vnet/hub-and-spoke/transit-nva"
  random_string       = random_string.unique.result
  location            = var.location_prod
  location_code       = local.location_code_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  address_space_vnet           = local.vnet_cidr_tr_pri
  subnet_cidr_firewall_public  = cidrsubnet(local.vnet_cidr_tr_pri, 3, 0)
  subnet_cidr_firewall_private = cidrsubnet(local.vnet_cidr_tr_pri, 3, 1)
  subnet_cidr_gateway          = cidrsubnet(local.vnet_cidr_tr_pri, 3, 2)
  subnet_cidr_bastion          = cidrsubnet(local.vnet_cidr_tr_pri, 3, 3)

  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud
  vnet_cidr_ss             = local.vnet_cidr_wl1_pri
  vnet_cidr_wl             = local.vnet_cidr_wl2_pri

  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size_nva  = var.sku_vm_size
  dce_id       = module.law.dce_id_primary
  dcr_id_linux = module.law.dcr_id_linux
  asn_router   = local.asn_router_r1
  nva_count    = 1

  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_prod}"
  storage_account_id_flow_logs         = module.storage-account-flow-logs-prod.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = merge(
    local.tags,
    {
      "env"  = "prod"
      "func" = "hub"
    }
  )
}

module "transit-vnet-nonprod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law,
    module.storage-account-flow-logs-nonprod
  ]

  source              = "../../modules/vnet/hub-and-spoke/transit-nva"
  random_string       = random_string.unique.result
  location            = var.location_nonprod
  location_code       = local.location_code_nonprod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  address_space_vnet           = local.vnet_cidr_tr_sec
  subnet_cidr_firewall_public  = cidrsubnet(local.vnet_cidr_tr_sec, 3, 0)
  subnet_cidr_firewall_private = cidrsubnet(local.vnet_cidr_tr_sec, 3, 1)
  subnet_cidr_gateway          = cidrsubnet(local.vnet_cidr_tr_sec, 3, 2)

  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud
  vnet_cidr_ss             = local.vnet_cidr_wl1_sec
  vnet_cidr_wl             = local.vnet_cidr_wl2_sec

  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size_nva  = var.sku_vm_size
  dce_id       = module.law.dce_id_secondary
  dcr_id_linux = module.law.dcr_id_linux
  asn_router   = local.asn_router_r2
  nva_count    = 1

  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_nonprod}"
  storage_account_id_flow_logs         = module.storage-account-flow-logs-nonprod.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = merge(
    local.tags,
    {
      "env"  = "nonprod"
      "func" = "hub"
    }
  )
}

# Add routes to allow traffic to flow across prod and non-prod
#
resource "azurerm_route" "prod_to_nonprod" {
  name                   = "rtnonprod"
  resource_group_name    = azurerm_resource_group.rg_demo_avnm.name
  route_table_name       = module.transit-vnet-prod.route_table_name_firewall_private
  address_prefix         = var.address_space_azure_nonprod
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.transit-vnet-nonprod.firewall_ilb_ip
}

resource "azurerm_route" "nonprod_to_prod" {
  name                   = "rtprod"
  resource_group_name    = azurerm_resource_group.rg_demo_avnm.name
  route_table_name       = module.transit-vnet-nonprod.route_table_name_firewall_private
  address_prefix         = var.address_space_azure_prod
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.transit-vnet-prod.firewall_ilb_ip
}

# Build production spoke virtual network
#
module "workload1-vnet-prod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law
  ]

  source              = "../vnet/standalone"
  random_string       = random_string.unique.result
  location            = var.location_prod
  location_code       = local.location_code_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  address_space_vnet = local.vnet_cidr_wl1_pri
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 0)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 1)

  admin_password = var.admin_password
  admin_username = var.admin_username

  vm_size_web = var.sku_vm_size
  purpose     = "pwwl1"

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_primary
  dcr_id_linux    = module.law.dcr_id_linux

  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_prod}"
  storage_account_id_flow_logs         = module.storage-account-flow-logs-prod.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = merge(
    local.tags,
    {
      "env"  = "prod"
      "func" = "spoke"
      "wl"   = "app1"
    }
  )
}

# Build other spoke virtual networks
#
module "workload1-vnet-pci" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law
  ]

  source              = "../vnet/standalone"
  random_string       = random_string.unique.result
  location            = var.location_prod
  location_code       = local.location_code_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  address_space_vnet = local.vnet_cidr_wl2_pri
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 0)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 1)

  admin_password = var.admin_password
  admin_username = var.admin_username

  vm_size_web = var.sku_vm_size
  purpose     = "pciwwl1"

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_primary
  dcr_id_linux    = module.law.dcr_id_linux

  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_prod}"
  storage_account_id_flow_logs         = module.storage-account-flow-logs-prod.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = merge(
    local.tags,
    {
      "env"  = "prod"
      "func" = "spoke"
      "data" = "pci"
    }
  )
}

module "workload1-vnet-nonprod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law
  ]

  source              = "../vnet/standalone"
  random_string       = random_string.unique.result
  location            = var.location_nonprod
  location_code       = local.location_code_nonprod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  address_space_vnet = local.vnet_cidr_wl1_sec
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 0)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 1)

  admin_password = var.admin_password
  admin_username = var.admin_username

  vm_size_web = var.sku_vm_size
  purpose     = "npwwl1"

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_secondary
  dcr_id_linux    = module.law.dcr_id_linux

  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_nonprod}"
  storage_account_id_flow_logs         = module.storage-account-flow-logs-nonprod.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = merge(
    local.tags,
    {
      "env"  = "nonprod"
      "func" = "spoke"
      "wl"   = "app1"
    }
  )
}

# Add virtual machines that will host mysql to the spoke virtual networks for production and non-production
#
module "workload1-vm-db-prod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law,
    module.workload1-vnet-prod
  ]

  source              = "../virtual-machine/ubuntu-tools"
  random_string       = random_string.unique.result
  location            = var.location_prod
  location_code       = local.location_code_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  purpose        = "pdwl1"
  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size = var.sku_vm_size
  image_reference = {
    publisher = local.image_preference_publisher
    offer     = local.image_preference_offer
    sku       = local.image_preference_sku
    version   = local.image_preference_version
  }

  subnet_id                     = module.workload1-vnet-prod.subnet_id_svc
  private_ip_address_allocation = "Static"
  nic_private_ip_address        = cidrhost(cidrsubnet(local.vnet_cidr_wl1_pri, 3, 1), 20)

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_primary
  dcr_id          = module.law.dcr_id_linux

  tags = var.tags
}

module "workload1-vm-db-nonprod" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.law,
    module.workload1-vnet-nonprod
  ]

  source              = "../virtual-machine/ubuntu-tools"
  random_string       = random_string.unique.result
  location            = var.location_nonprod
  location_code       = local.location_code_nonprod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name

  purpose        = "npdwl1"
  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size = var.sku_vm_size
  image_reference = {
    publisher = local.image_preference_publisher
    offer     = local.image_preference_offer
    sku       = local.image_preference_sku
    version   = local.image_preference_version
  }

  subnet_id                     = module.workload1-vnet-nonprod.subnet_id_svc
  private_ip_address_allocation = "Static"
  nic_private_ip_address        = cidrhost(cidrsubnet(local.vnet_cidr_wl1_sec, 3, 1), 20)

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_secondary
  dcr_id          = module.law.dcr_id_linux

  tags = var.tags
}

## Create Central IT Azure Virtual Network Manager Instance
##
module "avnm_centralit" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.workload1-vnet-prod,
    module.workload1-vnet-nonprod,
    module.workload1-vnet-pci,
    module.transit-vnet-prod,
    module.transit-vnet-nonprod,
    module.workload1-vm-db-prod,
    module.workload1-vm-db-nonprod
  ]
  source = "./manager"

  name                = "avnmcentralit${random_string.unique.result}"
  location            = var.location_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  law_resource_id     = module.law.id

  description = "The Central IT Azure Virtual Network Manager instance"

  management_scope = {
    management_group_ids = [
      var.management_group_id
    ]
  }
  configurations_supported = [
    "SecurityAdmin",
    "Connectivity",
    "Routing"
  ]

  tags = local.tags
}

##### Build resources required for Central IT Azure Virtual Network Manager Instance
#####

### Create Network Groups
###

# Network Groups used in Routing Configurations
#
resource "azapi_resource" "network_group_central_gatewaysubnet_prod" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-gatewaysubnet-prod"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains the GatewaySubnet for production"
      memberType  = "Subnet"
    }
  }
}

resource "azapi_resource" "network_group_central_gatewaysubnet_nonprod" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-gatewaysubnet-nonprod"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains the GatewaySubnet for non-production"
      memberType  = "Subnet"
    }
  }
}

# Network Groups used in Connectivity configurations
#
resource "azurerm_network_manager_network_group" "network_group_central_hub_all" {
  name               = "ng-hub-all"
  description        = "The network group containing all hubs across all environments and regions"
  network_manager_id = module.avnm_centralit.id
}

resource "azurerm_network_manager_network_group" "network_group_central_app1" {
  name               = "ng-spoke-app1"
  description        = "The network group containing application 1 workloads in both production and non-production"
  network_manager_id = module.avnm_centralit.id
}

# Network Groups used in Routing Configuration, Connectivity Configurations, and Security Admin Rule Configuration
#
resource "azurerm_network_manager_network_group" "network_group_central_spoke_prod" {
  name               = "ng-spoke-prod"
  description        = "The network group for spokes in production"
  network_manager_id = module.avnm_centralit.id
}

resource "azurerm_network_manager_network_group" "network_group_central_spoke_nonprod" {
  name               = "ng-spoke-nonprod"
  description        = "The network group for spokes in non-production"
  network_manager_id = module.avnm_centralit.id
}

# Network Groups used in Security Admin Rule Configurations
#
resource "azurerm_network_manager_network_group" "network_group_central_spoke_all_pci" {
  name               = "ng-spoke-all-pci"
  description        = "The network group for spokes running PCI workloads"
  network_manager_id = module.avnm_centralit.id
}

resource "azurerm_network_manager_network_group" "network_group_central_spoke_exceptions" {
  name               = "ng-spoke-exceptions"
  description        = "The network group for spokes that have an exception to remote access rules"
  network_manager_id = module.avnm_centralit.id
}

resource "azapi_resource" "network_group_central_subnet_remote_access" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-jump"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains contains subnets where jump hosts are deployed"
      memberType  = "Subnet"
    }
  }
}

resource "azapi_resource" "network_group_central_subnet_app1_db_nonprod" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups@2024-05-01"
  name                      = "ng-subnet-app1-db-nonprod"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The network group contains ccontains subnets where application 1 database servers are deployed in non-production"
      memberType  = "Subnet"
    }
  }
}

# Add static members to network groups
#
resource "azapi_resource" "static_member_central_subnet_remote_access" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.network_group_central_subnet_remote_access
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-jump"
  parent_id                 = azapi_resource.network_group_central_subnet_remote_access.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit-vnet-prod.subnet_id_bastion
    }
  }
}

resource "azapi_resource" "static_member_central_subnet_app1_db_nonprod" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.network_group_central_subnet_app1_db_nonprod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-app1-db-nonprod"
  parent_id                 = azapi_resource.network_group_central_subnet_app1_db_nonprod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.workload1-vnet-nonprod.subnet_id_svc
    }
  }
}

resource "azapi_resource" "static_member_central_subnet_gatewaysubnet_prod" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.network_group_central_gatewaysubnet_prod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-gateway-subnet-prod"
  parent_id                 = azapi_resource.network_group_central_gatewaysubnet_prod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit-vnet-prod.subnet_id_gateway
    }
  }
}

resource "azapi_resource" "static_member_central_subnet_gatewaysubnet_nonprod" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.network_group_central_gatewaysubnet_nonprod
  ]

  type                      = "Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01"
  name                      = "mem-subnet-gateway-subnet-nonprod"
  parent_id                 = azapi_resource.network_group_central_gatewaysubnet_nonprod.id
  schema_validation_enabled = true

  body = {
    properties = {
      resourceId = module.transit-vnet-nonprod.subnet_id_gateway
    }
  }
}

### Security Admin Configuration and supporting resources
###

# Create Security Admin Configuration
#
resource "azapi_resource" "security_config_central" {
  depends_on = [
    module.avnm_centralit,
    azurerm_network_manager_network_group.network_group_central_hub_all,
    azurerm_network_manager_network_group.network_group_central_app1,
    azurerm_network_manager_network_group.network_group_central_spoke_prod,
    azurerm_network_manager_network_group.network_group_central_spoke_nonprod,
    azurerm_network_manager_network_group.network_group_central_spoke_all_pci,
    azurerm_network_manager_network_group.network_group_central_spoke_exceptions,
    azapi_resource.network_group_central_subnet_remote_access,
    azapi_resource.network_group_central_subnet_app1_db_nonprod
  ]
  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations@2024-05-01"
  name                      = "cfg-sec"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The security configuration for Central IT"
      applyOnNetworkIntentPolicyBasedServices = [
        "AllowRulesOnly"
      ]
      networkGroupAddressSpaceAggregationOption = "Manual"
    }
  }
}

# Create Azure Virtual Network Manager Security Admin Rule Collections
#
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_prod" {
  name                            = "rc-prod"
  description                     = "The rule collection for production"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_prod.id
  ]
}

resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_nonprod" {
  name                            = "rc-nonprod"
  description                     = "The rule collection for non-production"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
  ]
}

resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_pci" {
  name                            = "rc-pci"
  description                     = "The rule collection for PCI workloads"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_all_pci.id
  ]
}

resource "azurerm_network_manager_admin_rule_collection" "rule_collection_central_sec_exceptions" {
  name                            = "rc-exceptions"
  description                     = "The rule collection for exceptions to remote access"
  security_admin_configuration_id = azapi_resource.security_config_central.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_central_spoke_exceptions.id
  ]
}

# Create Security Admin Rules for production rule collection
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

resource "azapi_resource" "security_admin_rule_allow_app1_from_nonprod_prod" {
  depends_on = [
    module.avnm_centralit,
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

resource "azapi_resource" "security_admin_rule_allow_remote_access_prod" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.security_config_central,
    azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod
  ]

  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "AllowRemoteAccess"
  parent_id                 = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_prod.id
  schema_validation_enabled = true

  body = {
    kind = "Custom"
    properties = {
      description = "Allow remote access from production jump hosts",
      protocol    = "Tcp",
      sources = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = local.vnet_cidr_tr_pri
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
        "2222"
      ],
      access    = "Allow",
      priority  = 2110,
      direction = "Inbound"
    }
  }
}

resource "azapi_resource" "security_admin_rule_deny_nonprod_prod" {
  depends_on = [
    module.avnm_centralit,
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
      description = "Deny non-production from communication with production",
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

# Create Security Admin Rules for non-production rule collection
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

resource "azapi_resource" "security_admin_rule_allow_remote_access_nonprod" {
  depends_on = [
    module.avnm_centralit,
    azapi_resource.security_config_central,
    azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_nonprod
  ]

  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "AllowRemoteAccess"
  parent_id                 = azurerm_network_manager_admin_rule_collection.rule_collection_central_sec_nonprod.id
  schema_validation_enabled = true

  body = {
    kind = "Custom"
    properties = {
      description = "Allow remote access from non-production jump hosts",
      protocol    = "Tcp",
      sources = [
        {
          addressPrefixType = "IPPrefix",
          addressPrefix     = local.vnet_cidr_tr_sec
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
        "2222"
      ],
      access    = "Allow",
      priority  = 2200,
      direction = "Inbound"
    }
  }
}

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

# Create Security Admin Rules for PCI rule collection
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_deny_http_from_all_pci" {
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

# Create Security Admin Rules for exceptions rule collection
#
resource "azurerm_network_manager_admin_rule" "security_admin_rule_allow_remote_access_all" {
  name                     = "AllowRemoteAccessFromAll"
  description              = "Allow remote access from all sources"
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

### Create Connectivity Configurations and supporting resources
###

# Create Connectivity Configurations
#
resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_hubspoke_prod" {
  depends_on = [
    azapi_resource.security_config_central
  ]
  name        = "cfg-conn-hubspoke-prod"
  description = "The connectivity configuration for hub and spoke for the production environment"

  network_manager_id    = module.avnm_centralit.id
  connectivity_topology = "HubAndSpoke"
  global_mesh_enabled   = false

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_spoke_prod.id
    use_hub_gateway    = true
  }

  hub {
    resource_id   = module.transit-vnet-prod.id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}

resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_hubspoke_nonprod" {
  depends_on = [
    azapi_resource.security_config_central
  ]
  name        = "cfg-conn-hubspoke-nonprod"
  description = "The connectivity configuration for hub and spoke for the non-production environment"

  network_manager_id    = module.avnm_centralit.id
  connectivity_topology = "HubAndSpoke"
  global_mesh_enabled   = false

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
    use_hub_gateway    = true
  }

  hub {
    resource_id   = module.transit-vnet-nonprod.id
    resource_type = "Microsoft.Network/virtualNetworks"
  }
}

resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_mesh_hub_all_g" {
  depends_on = [
    azapi_resource.security_config_central
  ]
  name        = "cfg-conn-mesh-hub-all-g"
  description = "The connectivity configuration for mesh across hubs in all environments"

  network_manager_id    = module.avnm_centralit.id
  connectivity_topology = "Mesh"
  global_mesh_enabled   = true

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_hub_all.id
  }
}

resource "azurerm_network_manager_connectivity_configuration" "connectivity_config_central_mesh_app1_g" {
  depends_on = [
    azapi_resource.security_config_central
  ]
  name        = "cfg-conn-mesh-app1-g"
  description = "The connectivity configuration for mesh for application 1 workloads in all environments"

  network_manager_id    = module.avnm_centralit.id
  connectivity_topology = "Mesh"
  global_mesh_enabled   = true

  applies_to_group {
    group_connectivity = "None"
    network_group_id   = azurerm_network_manager_network_group.network_group_central_app1.id
  }
}

### Create routing configuration and supporting resources
###

# Create Routing Configurations
#
resource "azapi_resource" "routing_config_central" {
  depends_on = [
    azapi_resource.security_config_central
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations@2024-05-01"
  name                      = "cfg-routing"
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The routing configuration for Central IT"
    }
  }
}

# Create Routing Rule Collections
#
resource "azapi_resource" "routing_rule_collection_prod_spokes" {
  depends_on = [
    azapi_resource.routing_config_central
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-05-01"
  name                      = "rt-rc-spoke-prod"
  parent_id                 = azapi_resource.routing_config_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description                = "The routing rule collection to apply to production spokes"
      disableBgpRoutePropagation = "True"
      appliesTo = [
        {
          networkGroupId = azurerm_network_manager_network_group.network_group_central_spoke_prod.id
        }
      ]
    }
  }
}

resource "azapi_resource" "routing_rule_collection_nonprod_spokes" {
  depends_on = [
    azapi_resource.routing_config_central
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-05-01"
  name                      = "rt-rc-spoke-nonprod"
  parent_id                 = azapi_resource.routing_config_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description                = "The routing rule collection to apply to non-production spokes"
      disableBgpRoutePropagation = "True"
      appliesTo = [
        {
          networkGroupId = azurerm_network_manager_network_group.network_group_central_spoke_nonprod.id
        }
      ]
    }
  }
}

resource "azapi_resource" "routing_rule_collection_prod_gateway_subnet" {
  depends_on = [
    azapi_resource.routing_config_central
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-05-01"
  name                      = "rt-rc-gateway-subnet-prod"
  parent_id                 = azapi_resource.routing_config_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description                = "The routing rule collection to apply to the GatewaySubnet in production"
      disableBgpRoutePropagation = "False"
      appliesTo = [
        {
          networkGroupId = azapi_resource.network_group_central_gatewaysubnet_prod.id
        }
      ]
    }
  }
}

resource "azapi_resource" "routing_rule_collection_nonprod_gateway_subnet" {
  depends_on = [
    azapi_resource.routing_config_central
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections@2024-05-01"
  name                      = "rt-rc-gateway-subnet-nonprod"
  parent_id                 = azapi_resource.routing_config_central.id
  schema_validation_enabled = true

  body = {
    properties = {
      description                = "The routing rule collection to apply to the GatewaySubnet in non-production"
      disableBgpRoutePropagation = "False"
      appliesTo = [
        {
          networkGroupId = azapi_resource.network_group_central_gatewaysubnet_nonprod.id
        }
      ]
    }
  }
}

# Create Routing Rules
#
resource "azapi_resource" "routing_rule_default_route_prod" {
  depends_on = [
    azapi_resource.routing_rule_collection_prod_spokes
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "defaultRoute"
  parent_id                 = azapi_resource.routing_rule_collection_prod_spokes.id
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
        nextHopAddress = module.transit-vnet-prod.firewall_ilb_ip
      }
    }
  }
}

resource "azapi_resource" "routing_rule_default_route_nonprod" {
  depends_on = [
    azapi_resource.routing_rule_collection_prod_spokes
  ]

  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "defaultRoute"
  parent_id                 = azapi_resource.routing_rule_collection_nonprod_spokes.id
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
        nextHopAddress = module.transit-vnet-nonprod.firewall_ilb_ip
      }
    }
  }
}

resource "azapi_resource" "routing_rule_gateway_subnet_route_prod_spoke1" {
  depends_on = [
    azapi_resource.routing_rule_collection_prod_gateway_subnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "prodvnet1"
  parent_id                 = azapi_resource.routing_rule_collection_prod_gateway_subnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to production spoke 1 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl1_pri
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit-vnet-nonprod.firewall_ilb_ip
      }
    }
  }
}

resource "azapi_resource" "routing_rule_gateway_subnet_route_prod_spoke2" {
  depends_on = [
    azapi_resource.routing_rule_collection_prod_gateway_subnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "prodvnet2"
  parent_id                 = azapi_resource.routing_rule_collection_prod_gateway_subnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to production spoke 2 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl2_pri
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit-vnet-nonprod.firewall_ilb_ip
      }
    }
  }
}

resource "azapi_resource" "routing_rule_gateway_subnet_route_nonprod_spoke1" {
  depends_on = [
    azapi_resource.routing_rule_collection_prod_gateway_subnet
  ]
  type                      = "Microsoft.Network/networkManagers/routingConfigurations/ruleCollections/rules@2024-05-01"
  name                      = "nonprodvnet1"
  parent_id                 = azapi_resource.routing_rule_collection_nonprod_gateway_subnet.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The rule to route traffic from on-premises to non-production spoke 1 to the NVA"
      destination = {
        type               = "AddressPrefix"
        destinationAddress = local.vnet_cidr_wl1_sec
      }
      nextHop = {
        nextHopType    = "VirtualAppliance"
        nextHopAddress = module.transit-vnet-nonprod.firewall_ilb_ip
      }
    }
  }
}

##### Create Azure Policies for Central IT Azure Virtual Network Manager Instance
#####

### Create Azure Policy Definitions
###

# Create Azure Policy Definition that adds virtual networks to the all spoke production network group if they are tagged with func=spoke and env=prod
#
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

# Create Azure Policy Definition that adds virtual networks to the all spoke non-production network group if they are tagged with func=spoke and env=nonprod
#
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

# Create Azure Policy Definition that adds virtual networks to the PCI network groups if they are tagged with data=pci
#
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

# Create Azure Policy Definition that adds virtual networks to the all hub network group if they are tagged with func=hub
#
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
        "networkGroupId" : azurerm_network_manager_network_group.network_group_central_hub_all.id
      }
    }
  })
}

# Create Azure Policy Definition that adds virtual networks to the sql workload network group if they are tagged with wl=app1
#
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

### Create Azure Policy Assignments
###

# Create Azure Policy assignments and apply directly to the resource group
#
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

##### Create IPAM resources
#####

# Create IPAM pools
#
resource "azapi_resource" "ipam_org_on_prem_pool" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools@2024-05-01"
  name                      = local.org_onprem_pool_name
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    location = var.location_prod
    tags     = local.tags
    properties = {
      description    = "The primary pool for the organization used on-premises",
      parentPoolName = ""
      addressPrefixes = [
        var.address_space_onpremises
      ]
    }
  }
}

resource "azapi_resource" "ipam_org_pool" {
  depends_on = [
    module.avnm_centralit
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools@2024-05-01"
  name                      = local.org_pool_name
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    location = var.location_prod
    tags     = local.tags
    properties = {
      description    = "The primary pool for the organization used in the cloud",
      parentPoolName = ""
      addressPrefixes = [
        var.address_space_cloud
      ]
    }
  }
}

resource "azapi_resource" "ipam_org_pool_prod" {
  depends_on = [
    azapi_resource.ipam_org_pool
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools@2024-05-01"
  name                      = local.prod_pool_name
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    location = var.location_prod
    tags     = local.tags
    properties = {
      description    = "The pool for production for the organization used in the cloud",
      parentPoolName = local.org_pool_name
      addressPrefixes = [
        var.address_space_azure_prod
      ]
    }
  }
}

resource "azapi_resource" "ipam_org_pool_nonprod" {
  depends_on = [
    azapi_resource.ipam_org_pool
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools@2024-05-01"
  name                      = local.nonprod_pool_name
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    location = var.location_nonprod
    tags     = local.tags
    properties = {
      description    = "The pool for non-production for the organization used in the cloud",
      parentPoolName = local.org_pool_name
      addressPrefixes = [
        var.address_space_azure_nonprod
      ]
    }
  }
}

resource "azapi_resource" "ipam_org_pool_prod_bu" {
  depends_on = [
    azapi_resource.ipam_org_pool_prod
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools@2024-05-01"
  name                      = local.bu_prod_pool_name
  parent_id                 = module.avnm_centralit.id
  schema_validation_enabled = true

  body = {
    location = var.location_prod
    tags     = local.tags
    properties = {
      description    = "The pool for production for the business unit used in the cloud",
      parentPoolName = local.prod_pool_name
      addressPrefixes = [
        # Give BU a subset of total Azure production address space
        cidrsubnet(var.address_space_azure_prod, 2, 3)
      ]
    }
  }
}

# Create IPAM Allocations
#
resource "azapi_resource" "ipam_org_pool_allocation_on_premises_lab" {
  depends_on = [
    azapi_resource.ipam_org_on_prem_pool
  ]

  type                      = "Microsoft.Network/networkManagers/ipamPools/staticCidrs@2024-05-01"
  name                      = local.org_allocation_onprem_lab_name
  parent_id                 = azapi_resource.ipam_org_on_prem_pool.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "This is the allocation for the on-premises lab"
      addressPrefixes = [
        cidrsubnet(var.address_space_onpremises, 8, 0)
      ]
    }
  }
}

# Create a Virtual Network to demonstrate adding it to the IPAM pool by specifying number of addresses
#
resource "azapi_resource" "vnet_bu_wl1_ipam" {
  depends_on = [
    azapi_resource.ipam_org_pool_prod_bu
  ]

  type                      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name                      = "vnetbuwl1${local.location_code_prod}${random_string.unique.result}"
  parent_id                 = azurerm_resource_group.rg_demo_avnm.id
  schema_validation_enabled = true

  body = {
    location = var.location_prod
    properties = {
      addressSpace = {
        ipamPoolPrefixAllocations = [
          {
            numberOfIpAddresses = "512"
            pool = {
              id = azapi_resource.ipam_org_pool_prod_bu.id
            }
          }
        ]
      }
      subnets = [
        {
          name = "snet-pri"
          properties = {
            ipamPoolPrefixAllocations = [
              {
                numberOfIpAddresses = "256"
                pool = {
                  id = azapi_resource.ipam_org_pool_prod_bu.id
                }
              }
            ]
          }
        },
        {
          name = "snet-sec"
          properties = {
            ipamPoolPrefixAllocations = [
              {
                numberOfIpAddresses = "256"
                pool = {
                  id = azapi_resource.ipam_org_pool_prod_bu.id
                }
              }
            ]
          }
        }
      ]
    },
    tags = local.tags
  }
}

# Create an Azure RBAC Role assignment granting the user the ability to use the BU IPAM pool
#
resource "azurerm_role_assignment" "ipam_pool_user_bu_pool" {
  depends_on = [
    azapi_resource.ipam_org_pool_prod_bu
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_demo_avnm.name}${var.user_object_id}${azapi_resource.ipam_org_pool_prod_bu.name}pooluser")
  scope                = azapi_resource.ipam_org_pool_prod_bu.id
  role_definition_name = "IPAM Pool User"
  principal_id         = var.user_object_id
}

##### Create a child Azure Virtual Network Manager instance and supporting resources
#####

# Create a child Azure Virtual Network Manager instance
#
module "avnm_bu" {
  depends_on = [
    azurerm_resource_group.rg_demo_avnm,
    module.workload1-vnet-prod,
    module.workload1-vnet-nonprod,
    module.workload1-vnet-pci,
    module.transit-vnet-prod,
    module.transit-vnet-nonprod,
    module.workload1-vm-db-prod,
    module.workload1-vm-db-nonprod
  ]
  source = "./manager"

  name                = "avnmbu${random_string.unique.result}"
  location            = var.location_prod
  resource_group_name = azurerm_resource_group.rg_demo_avnm.name
  law_resource_id     = module.law.id

  description = "The BU Azure Virtual Network Manager instance"

  management_scope = {
    subscription_ids = [
      data.azurerm_subscription.current.subscription_id
    ]
  }
  configurations_supported = [
    "SecurityAdmin"
  ]

  tags = local.tags
}

# Create Network Groups used in the child Azure Virtual Network Manager instance
#
resource "azurerm_network_manager_network_group" "network_group_bu_spoke_prod" {
  name               = "ng-spoke-prod-bu"
  description        = "The network group for BU spokes in production"
  network_manager_id = module.avnm_bu.id
}

# Add the production BU spoke virtual network to the network group
#
resource "azurerm_network_manager_static_member" "static_member_bu_spoke_prod" {
  name                      = "member${module.workload1-vnet-prod.name}"
  network_group_id          = azurerm_network_manager_network_group.network_group_bu_spoke_prod.id
  target_virtual_network_id = module.workload1-vnet-prod.id
}

# Create BU Security Admin Configuration
#
resource "azapi_resource" "security_config_bu" {
  depends_on = [
    module.avnm_bu,
    azurerm_network_manager_network_group.network_group_bu_spoke_prod,

  ]
  type                      = "Microsoft.Network/networkManagers/securityAdminConfigurations@2024-05-01"
  name                      = "cfg-sec"
  parent_id                 = module.avnm_bu.id
  schema_validation_enabled = true

  body = {
    properties = {
      description = "The security configuration for a business unit"
      applyOnNetworkIntentPolicyBasedServices = [
        "AllowRulesOnly"
      ]
      networkGroupAddressSpaceAggregationOption = "Manual"
    }
  }
}

# Create Azure Virtual Network Manager BU Security Admin Rule Collections
#
resource "azurerm_network_manager_admin_rule_collection" "rule_collection_bu_sec_prod" {
  name                            = "rc-prod"
  description                     = "The rule collection for production BU spokes"
  security_admin_configuration_id = azapi_resource.security_config_bu.id
  network_group_ids = [
    azurerm_network_manager_network_group.network_group_bu_spoke_prod.id
  ]
}

# Create Security Admin Rule for BU production rule collection
#
resource "azapi_resource" "security_admin_rule_allow_remote_access_prod_bu" {
  depends_on = [
    module.avnm_bu,
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
      description = "Allow access from all source to the BU servers",
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
        "2222"
      ],
      access    = "Allow",
      priority  = 2000,
      direction = "Inbound"
    }
  }
}

