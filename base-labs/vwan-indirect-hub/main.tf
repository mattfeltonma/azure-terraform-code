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
resource "azurerm_resource_group" "rgtran-pri" {
  name     = "rgtr${local.location_code_primary}${random_string.unique.result}"
  location = var.location_primary
  tags     = local.tags
}

resource "azurerm_resource_group" "rgshared-pri" {
  name     = "rgsh${local.location_code_primary}${random_string.unique.result}"
  location = var.location_primary
  tags     = local.tags
}

resource "azurerm_resource_group" "rgwork-pri" {
  name     = "rgwl${local.location_code_primary}${random_string.unique.result}"
  location = var.location_primary

  tags = local.tags
}

resource "azurerm_resource_group" "rgtran-sec" {
  count = var.multi_region == true ? 1 : 0

  name     = "rgtr${local.location_code_secondary}${random_string.unique.result}"
  location = var.location_secondary
  tags     = local.tags
}

resource "azurerm_resource_group" "rgshared-sec" {
  count = var.multi_region == true ? 1 : 0

  name     = "rgsh${local.location_code_secondary}${random_string.unique.result}"
  location = var.location_secondary
  tags     = local.tags
}

resource "azurerm_resource_group" "rgwork-sec" {
  count = var.multi_region == true ? 1 : 0

  name     = "rgwl${local.location_code_secondary}${random_string.unique.result}"
  location = var.location_secondary
  tags     = local.tags
}

## Grant the Terraform identity access to Key Vault secrets, certificates, and keys all Key Vaults
##
resource "azurerm_role_assignment" "assign-tf-pri" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgshared-pri.id}${data.azurerm_client_config.identity_config.object_id}")
  scope                = azurerm_resource_group.rgshared-pri.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.identity_config.object_id
}

resource "azurerm_role_assignment" "assign-tf-sec" {
  count = var.multi_region == true ? 1 : 0

  name                 = uuidv5("dns", "${azurerm_resource_group.rgshared-sec[0].id}${data.azurerm_client_config.identity_config.object_id}")
  scope                = azurerm_resource_group.rgshared-sec[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.identity_config.object_id
}

## Create Log Analytics Workspace and Data Collection Endpoints and Data Collection Rules for Windows and Linux in primary region
##
module "law" {
  depends_on = [
    azurerm_resource_group.rgshared-pri
  ]

  source                        = "../../modules/monitor/log-analytics-workspace"
  random_string                 = random_string.unique.result
  purpose                       = local.law_purpose
  location_primary              = var.location_primary
  location_secondary            = var.location_secondary
  location_code_primary         = local.location_code_primary
  location_code_secondary       = local.location_code_secondary
  resource_group_name_primary   = azurerm_resource_group.rgshared-pri.name
  resource_group_name_secondary = var.multi_region ? try(azurerm_resource_group.rgshared-sec[0].name, null) : null
  tags                          = local.tags
}

## Create Storage Account for Flow Logs
##
module "storage-account-flow-logs-pri" {
  depends_on = [
    azurerm_resource_group.rgshared-pri,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgshared-pri.name
  tags                = local.tags

  network_trusted_services_bypass = ["AzureServices, Logging, Metrics"]

  law_resource_id = module.law.id
}

module "storage-account-flow-logs-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_resource_group.rgshared-sec,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgshared-sec[0].name
  tags                = local.tags

  network_trusted_services_bypass = ["AzureServices, Logging, Metrics"]

  law_resource_id = module.law.id
}

## Create a VWAN
##
module "vwan" {
  depends_on = [
    azurerm_resource_group.rgtran-pri,
    module.law,
    module.storage-account-flow-logs-pri
  ]

  source              = "../../modules/vwan-resources/vwan"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgtran-pri.name

  allow-branch = true
  tags         = local.tags
}

## Create VWAN Hubs
##
module "vwan-hub-pri" {
  depends_on = [
    module.vwan
  ]

  source              = "../../modules/vwan-resources/vwan-hub"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgtran-pri.name

  vwan_id       = module.vwan.id
  address_space = local.vnet_cidr_vwanh_pri
  vpn_gateway   = true

  routing_preference = "ASPath"

  law_resource_id = module.law.id

  tags = local.tags
}

module "vwan-hub-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    module.vwan
  ]

  source              = "../../modules/vwan-hub"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgtran-sec[0].name

  vwan_id       = module.vwan.id
  address_space = local.vnet_cidr_vwanh_sec
  vpn_gateway   = true

  law_resource_id = module.law.id

  tags = local.tags
}

## Create an indirect hub virtual network with a Linux NVA
##
module "transit-vnet-pri" {
  depends_on = [
    azurerm_resource_group.rgtran-pri,
    module.vwan-hub-pri,
    module.law,
    module.storage-account-flow-logs-pri
  ]

  source              = "../../modules/vnet/vwan/transit-nva"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgtran-pri.name

  # Address spaces of other resources
  address_space_azure      = var.address_space_cloud
  address_space_onpremises = var.address_space_onpremises
  vnet_cidr_ss             = local.vnet_cidr_ss_pri
  vnet_cidr_wl1            = local.vnet_cidr_wl1_pri
  vnet_cidr_wl2            = local.vnet_cidr_wl2_pri

  # Settings for this virtual network that is being created
  address_space_vnet           = local.vnet_cidr_tr_pri
  subnet_cidr_firewall_private = cidrsubnet(local.vnet_cidr_tr_pri, 3, 0)
  subnet_cidr_firewall_public  = cidrsubnet(local.vnet_cidr_tr_pri, 3, 1)

  # Settings for the Virtual WAN Connection
  vwan_hub_id                    = module.vwan-hub-pri.id
  vwan_associated_route_table_id = module.vwan-hub-pri.default_route_table_id
  vwan_propagate_route_table_ids = [module.vwan-hub-pri.default_route_table_id]
  vwan_propagate_route_labels    = ["default"]
  vwan_propagate_static_routes   = true

  # Settings for Network Watcher
  network_watcher_name                 = var.network_watcher_name
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  # Settings for the NVA
  admin_username = var.admin_username
  admin_password = var.admin_password
  dce_id         = module.law.dce_id_primary
  dcr_id_linux   = module.law.dcr_id_linux
  asn_router     = local.asn_router_r1
  vm_size_nva    = var.sku_vm_size

  tags = local.tags
}

module "transit-vnet-sec" {
  depends_on = [
    azurerm_resource_group.rgtran-sec,
    module.vwan-hub-sec,
    module.law,
    module.storage-account-flow-logs-sec
  ]

  count = var.multi_region == true ? 1 : 0

  source              = "../../modules/vnet/vwan/transit-nva"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgtran-sec.name

  # Address spaces of other resources
  address_space_azure      = var.address_space_cloud
  address_space_onpremises = var.address_space_onpremises
  vnet_cidr_ss             = local.vnet_cidr_ss_pri
  vnet_cidr_wl1            = local.vnet_cidr_wl1_pri
  vnet_cidr_wl2            = local.vnet_cidr_wl2_pri

  # Settings for this virtual network that is being created
  address_space_vnet           = local.vnet_cidr_tr_pri
  subnet_cidr_firewall_private = cidrsubnet(local.vnet_cidr_tr_pri, 3, 0)
  subnet_cidr_firewall_public  = cidrsubnet(local.vnet_cidr_tr_pri, 3, 1)

  # Settings for the Virtual WAN Connection
  vwan_hub_id                    = module.vwan-hub-pri.id
  vwan_associated_route_table_id = module.vwan-hub-pri.default_route_table_id
  vwan_propagate_route_table_ids = [module.vwan-hub-pri.default_route_table_id]
  vwan_propagate_route_labels    = ["default"]
  vwan_propagate_static_routes   = true

  # Settings for Network Watcher
  network_watcher_name                 = var.network_watcher_name
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  # Settings for the NVA
  admin_username = var.admin_username
  admin_password = var.admin_password
  dce_id         = module.law.dce_id_primary
  dcr_id_linux   = module.law.dcr_id_linux
  asn_router     = local.asn_router_r1
  vm_size_nva    = var.sku_vm_size

  tags = local.tags
}

## Create a shared services virtual network
##
module "shared-vnet-pri" {
  depends_on = [
    azurerm_resource_group.rgshared-pri,
    module.transit-vnet-pri
  ]

  source              = "../../modules/vnet/all/shared"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgshared-pri.name

  # Configure settings to connect the Shared Services virtual network the transit virtual network
  # and use the NVA as a firewall for access to the Internet
  hub_and_spoke           = true
  name_hub                = module.transit-vnet-pri.name
  resource_group_name_hub = azurerm_resource_group.rgtran-pri.name
  vnet_id_hub             = module.transit-vnet-pri.id
  fw_private_ip           = module.transit-vnet-pri.firewall_ilb_ip

  # Settings used to configure the Shared Services virtual network
  address_space_vnet  = local.vnet_cidr_ss_pri
  subnet_cidr_bastion = cidrsubnet(local.vnet_cidr_ss_pri, 3, 0)
  subnet_cidr_dnsin   = cidrsubnet(local.vnet_cidr_ss_pri, 3, 1)
  subnet_cidr_dnsout  = cidrsubnet(local.vnet_cidr_ss_pri, 3, 2)
  subnet_cidr_tools   = cidrsubnet(local.vnet_cidr_ss_pri, 3, 3)
  subnet_cidr_pe      = cidrsubnet(local.vnet_cidr_ss_pri, 3, 4)
  
  # DNS Proxy is not being used so set Shared Services VNet to use the inbound endpoint for DNS
  dns_proxy = false

  # Pass the address space for on-premises and all of Azure to be used in Network Security Groups
  # for the Private DNS Resolver
  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud

  # Pass the Log Analytics Workspace information to the template to be used for
  # diagnostic settings and configured Data Collection Endpoints and Rules for the tools virtual machine
  law_resource_id      = module.law.id
  law_workspace_id     = module.law.workspace_id
  law_workspace_region = module.law.location
  dce_id               = module.law.dce_id_primary
  dcr_id_windows       = module.law.dcr_id_windows

  # Configure Network Watcher settings for VNet Flow Logs
  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_primary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  # Settings for the tools virtual machine
  sku_tools_size = var.sku_vm_size
  sku_tools_os   = var.sku_tools_os
  admin_username = var.admin_username
  admin_password = var.admin_password

  tags = local.tags
}

module "shared-vnet-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_resource_group.rgshared-sec,
    module.transit-vnet-sec[0]
  ]

  source              = "../../modules/vnet/all/shared"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgshared-sec[0].name

  # Configure settings to connect the Shared Services virtual network the transit virtual network
  # and use the NVA as a firewall for access to the Internet
  hub_and_spoke           = false
  name_hub                = module.transit-vnet-sec[0].name
  resource_group_name_hub = azurerm_resource_group.rgtran-sec[0].name
  vnet_id_hub             = module.transit-vnet-sec[0].id
  fw_private_ip           = module.transit-vnet-sec[0].firewall_ilb_ip

  # Settings used to configure the Shared Services virtual network
  address_space_vnet  = local.vnet_cidr_ss_sec
  subnet_cidr_bastion = cidrsubnet(local.vnet_cidr_ss_sec, 3, 0)
  subnet_cidr_dnsin   = cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)
  subnet_cidr_dnsout  = cidrsubnet(local.vnet_cidr_ss_sec, 3, 2)
  subnet_cidr_tools   = cidrsubnet(local.vnet_cidr_ss_sec, 3, 3)
  subnet_cidr_pe      = cidrsubnet(local.vnet_cidr_ss_sec, 3, 4)
  
  # DNS Proxy is not being used so set Shared Services VNet to use the inbound endpoint for DNS
  dns_proxy           = true

  # Pass the address space for on-premises and all of Azure to be used in Network Security Groups
  # for the Private DNS Resolver
  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud


  # Pass the Log Analytics Workspace information to the template to be used for
  # diagnostic settings and configured Data Collection Endpoints and Rules for the tools virtual machine
  law_resource_id      = module.law.id
  law_workspace_id     = module.law.workspace_id
  law_workspace_region = module.law.location
  dce_id               = module.law.dce_id_secondary
  dcr_id_windows       = module.law.dcr_id_windows

  # Configure Network Watcher settings for VNet Flow Logs
  storage_account_id_flow_logs         = module.storage-account-flow-logs-sec[0].id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_secondary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  # Settings for the tools virtual machine
  sku_tools_size = var.sku_vm_size
  sku_tools_os   = var.sku_tools_os
  admin_username = var.admin_username
  admin_password = var.admin_password

  tags = local.tags
}

## Create centralized Azure Key Vault
##
module "central-keyvault" {
  depends_on = [
    azurerm_resource_group.rgshared-pri
  ]

  source                  = "../../modules/key-vault"
  random_string           = random_string.unique.result
  location                = var.location_primary
  location_code           = local.location_code_primary
  resource_group_name     = azurerm_resource_group.rgshared-pri.name
  purpose                 = "cnt"
  law_resource_id         = module.law.id
  kv_admin_object_id      = var.key_vault_admin
  firewall_default_action = "Allow"

  tags = local.tags
}

## Add virtual machine user and password to Azure Key Vault
##
resource "azurerm_key_vault_secret" "vm-credentials" {
  depends_on = [
    module.central-keyvault
  ]
  name = "vm-credentials"
  value = jsonencode({
    admin_username = var.admin_username
    admin_password = var.admin_password
  })
  key_vault_id = module.central-keyvault.id
}

## Create Private DNS Zones and Virtual Network Links
##
module "private_dns_zones" {
  depends_on = [
    azurerm_resource_group.rgshared-pri,
    module.shared-vnet-pri
  ]

  source              = "../../modules/dns/private-dns-zone"
  resource_group_name = azurerm_resource_group.rgshared-pri.name

  for_each = {
    for zone in local.private_dns_namespaces_with_regional_zones :
    zone => zone
  }

  name    = each.value
  vnet_id = module.shared-vnet-pri.id

  tags = local.tags
}

## If the second region is being deployed, create virtual network links to the existing Private DNS Zones
##
resource "azurerm_private_dns_zone_virtual_network_link" "link-second-region" {
  depends_on = [
    module.private_dns_zones,
    module.shared-vnet-sec[0]
  ]
  for_each = var.multi_region == true ? {
    for zone in local.private_dns_namespaces_with_regional_zones :
    zone => zone
  } : {}

  name                  = "${each.value}-r2link"
  resource_group_name   = azurerm_resource_group.rgshared-pri.name
  private_dns_zone_name = each.value
  virtual_network_id    = module.shared-vnet-sec[0].id
  registration_enabled  = false
  tags                  = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Modify DNS Server Settings on transit virtual network
##
resource "azurerm_virtual_network_dns_servers" "dns-servers-pri" {
  depends_on = [
    module.private_dns_zones
  ]
  virtual_network_id = module.transit-vnet-pri.id
  dns_servers = [
    module.shared-vnet-pri.private_resolver_inbound_endpoint_ip
  ]
}

resource "azurerm_virtual_network_dns_servers" "dns-servers-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.link-second-region
  ]
  virtual_network_id = module.transit-vnet-sec[0].id
  dns_servers = [
    module.shared-vnet-sec[0].private_resolver_inbound_endpoint_ip
  ]
}

## Create the workload virtual networks
##
module "workload1-vnet-pri" {
  depends_on = [
    azurerm_resource_group.rgwork-pri,
    module.shared-vnet-pri,
    azurerm_virtual_network_dns_servers.dns-servers-pri
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgwork-pri.name
  workload_number = 1

  address_space_vnet = local.vnet_cidr_wl1_pri
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 0)
  subnet_cidr_data   = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 1)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 2)
  subnet_cidr_agw    = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 3)
  subnet_cidr_apim   = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 4)
  subnet_cidr_amlcpt = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 5)
  subnet_cidr_mgmt   = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 6)
  subnet_cidr_vint   = cidrsubnet(local.vnet_cidr_wl1_pri, 3, 7)


  fw_private_ip = module.transit-vnet-pri.azfw_private_ip
  dns_servers = [
    module.transit-vnet-pri.azfw_private_ip
  ]
  name_hub                   = module.transit-vnet-pri.name
  resource_group_name_hub    = azurerm_resource_group.rgtran-pri.name
  vnet_id_hub                = module.transit-vnet-pri.id
  name_shared                = module.shared-vnet-pri.name
  resource_group_name_shared = azurerm_resource_group.rgshared-pri.name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_primary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

module "workload2-vnet-pri" {
  depends_on = [
    module.workload1-vnet-pri
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgwork-pri.name
  workload_number = 2

  address_space_vnet = local.vnet_cidr_wl2_pri
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 0)
  subnet_cidr_data   = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 1)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 2)
  subnet_cidr_agw    = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 3)
  subnet_cidr_apim   = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 4)
  subnet_cidr_amlcpt = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 5)
  subnet_cidr_mgmt   = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 6)
  subnet_cidr_vint   = cidrsubnet(local.vnet_cidr_wl2_pri, 3, 7)


  fw_private_ip = module.transit-vnet-pri.azfw_private_ip
  dns_servers = [
    module.transit-vnet-pri.azfw_private_ip
  ]
  name_hub                   = module.transit-vnet-pri.name
  resource_group_name_hub    = azurerm_resource_group.rgtran-pri.name
  vnet_id_hub                = module.transit-vnet-pri.id
  name_shared                = module.shared-vnet-pri.name
  resource_group_name_shared = azurerm_resource_group.rgshared-pri.name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_primary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

module "workload1-vnet-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_resource_group.rgwork-sec,
    module.shared-vnet-sec,
    azurerm_virtual_network_dns_servers.dns-servers-sec
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgwork-sec[0].name

  address_space_vnet = local.vnet_cidr_wl1_sec
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 0)
  subnet_cidr_data   = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 1)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 2)
  subnet_cidr_agw    = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 3)
  subnet_cidr_apim   = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 4)
  subnet_cidr_amlcpt = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 5)
  subnet_cidr_mgmt   = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 6)
  subnet_cidr_vint   = cidrsubnet(local.vnet_cidr_wl1_sec, 3, 7)

  fw_private_ip = module.transit-vnet-sec[0].azfw_private_ip
  dns_servers = [
    module.transit-vnet-sec[0].azfw_private_ip
  ]
  name_hub                   = module.transit-vnet-sec[0].name
  resource_group_name_hub    = azurerm_resource_group.rgtran-sec[0].name
  vnet_id_hub                = module.transit-vnet-sec[0].id
  name_shared                = azurerm_resource_group.rgshared-pri.name
  resource_group_name_shared = azurerm_resource_group.rgshared-pri.name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage-account-flow-logs-sec[0].id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_secondary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

module "workload2-vnet-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    module.workload1-vnet-sec
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgwork-sec[0].name
  workload_number = 2

  address_space_vnet = local.vnet_cidr_wl2_sec
  subnet_cidr_app    = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 0)
  subnet_cidr_data   = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 1)
  subnet_cidr_svc    = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 2)
  subnet_cidr_agw    = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 3)
  subnet_cidr_apim   = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 4)
  subnet_cidr_amlcpt = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 5)
  subnet_cidr_mgmt   = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 6)
  subnet_cidr_vint   = cidrsubnet(local.vnet_cidr_wl2_sec, 3, 7)

  fw_private_ip = module.transit-vnet-sec[0].azfw_private_ip
  dns_servers = [
    module.transit-vnet-sec[0].azfw_private_ip
  ]
  name_hub                   = module.transit-vnet-sec[0].name
  resource_group_name_hub    = azurerm_resource_group.rgtran-sec[0].name
  vnet_id_hub                = module.transit-vnet-sec[0].id
  name_shared                = azurerm_resource_group.rgshared-pri.name
  resource_group_name_shared = azurerm_resource_group.rgshared-pri.name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage-account-flow-logs-sec[0].id
  network_watcher_resource_id          = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location_secondary}"
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}
