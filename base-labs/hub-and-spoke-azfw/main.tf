## Create a random string
##
resource "random_string" "unique" {
  length  = 3
  numeric = true
  lower   = true
  upper   = false
  special = false
}

## Create resource groups
##
resource "azurerm_resource_group" "rgtran" {
  for_each = local.regions

  name     = "rgtr${local.region_abbreviations[each.value]}${random_string.unique.result}"
  location = each.value
  tags     = local.tags
}

resource "azurerm_resource_group" "rgshared" {
  for_each = local.regions

  name     = "rgsh${local.region_abbreviations[each.value]}${random_string.unique.result}"
  location = each.value
  tags     = local.tags
}

resource "azurerm_resource_group" "rgwork" {
  for_each = local.regions

  name     = "rgwl${local.region_abbreviations[each.value]}${random_string.unique.result}"
  location = each.value
  tags     = local.tags
}

## Grant the Terraform identity access to Key Vault secrets, certificates, and keys all Key Vaults
##
resource "azurerm_role_assignment" "tf_key_vault_admin" {
  for_each = local.regions

  scope                = azurerm_resource_group.rgshared[each.key].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.identity_config.object_id
}

## Create Log Analytics Workspace (centralized in primary region only)
##
module "law" {
  depends_on = [
    azurerm_resource_group.rgshared
  ]

  source                        = "../../modules/monitor/log-analytics-workspace"
  random_string                 = random_string.unique.result
  purpose                       = local.law_purpose
  location_primary              = var.location_primary
  location_secondary            = var.location_secondary
  location_code_primary         = local.location_code_primary
  location_code_secondary       = local.location_code_secondary
  resource_group_name_primary   = azurerm_resource_group.rgshared["primary"].name
  resource_group_name_secondary = var.multi_region ? azurerm_resource_group.rgshared["secondary"].name : null
  tags                          = local.tags
}

## Create Storage Accounts for Flow Logs
##
module "storage_account_flow_logs" {
  for_each = local.regions

  depends_on = [
    azurerm_resource_group.rgshared,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = each.value
  location_code       = local.region_abbreviations[each.value]
  resource_group_name = azurerm_resource_group.rgshared[each.key].name
  tags                = local.tags

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]
  law_resource_id                  = module.law.id
}

## Create Transit Virtual Networks (Hub)
##
module "transit_vnet" {
  for_each = local.regions

  depends_on = [
    azurerm_resource_group.rgtran,
    module.law,
    module.storage_account_flow_logs
  ]

  source              = "../../modules/vnet/hub-and-spoke/transit-azfw"
  random_string       = random_string.unique.result
  location            = each.value
  location_code       = local.region_abbreviations[each.value]
  resource_group_name = azurerm_resource_group.rgtran[each.key].name

  # Dynamic CIDR allocation based on region
  address_space_vnet   = each.key == "primary" ? local.vnet_cidr_tr_pri : local.vnet_cidr_tr_sec
  subnet_cidr_gateway  = each.key == "primary" ? cidrsubnet(local.vnet_cidr_tr_pri, 3, 0) : cidrsubnet(local.vnet_cidr_tr_sec, 3, 0)
  subnet_cidr_firewall = each.key == "primary" ? cidrsubnet(local.vnet_cidr_tr_pri, 3, 1) : cidrsubnet(local.vnet_cidr_tr_sec, 3, 1)
  subnet_cidr_dns      = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 1) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)

  address_space_onpremises = var.address_space_onpremises
  address_space_apim = each.key == "primary" ? [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 4),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 4)
  ] : [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 4),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 4)
  ]
  address_space_amlcpt = each.key == "primary" ? [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 5),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 5)
  ] : [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 5),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 5)
  ]
  
  address_space_azure = var.address_space_cloud
  vnet_cidr_ss        = each.key == "primary" ? local.vnet_cidr_ss_pri : local.vnet_cidr_ss_sec
  vnet_cidr_wl = each.key == "primary" ? [
    local.vnet_cidr_wl1_pri,
    local.vnet_cidr_wl2_pri
  ] : [
    local.vnet_cidr_wl1_sec,
    local.vnet_cidr_wl2_sec
  ]

  network_watcher_name                 = "${var.network_watcher_name_prefix}${each.value}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  storage_account_id_flow_logs         = module.storage_account_flow_logs[each.key].id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

## Create Shared Services Virtual Networks
##
module "shared_vnet" {
  for_each = local.regions

  depends_on = [
    azurerm_resource_group.rgshared,
    module.transit_vnet
  ]

  source              = "../../modules/vnet/all/shared"
  random_string       = random_string.unique.result
  location            = each.value
  location_code       = local.region_abbreviations[each.value]
  resource_group_name = azurerm_resource_group.rgshared[each.key].name

  hub_and_spoke = true

  # Dynamic CIDR allocation
  address_space_vnet  = each.key == "primary" ? local.vnet_cidr_ss_pri : local.vnet_cidr_ss_sec
  subnet_cidr_bastion = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 0) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 0)
  subnet_cidr_dnsin   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 1) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)
  subnet_cidr_dnsout  = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 2) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 2)
  subnet_cidr_tools   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 3) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 3)
  subnet_cidr_pe      = each.key == "primary" ? cidrsubnet(local.vnet_cidr_ss_pri, 3, 4) : cidrsubnet(local.vnet_cidr_ss_sec, 3, 4)
  
  fw_private_ip = module.transit_vnet[each.key].azfw_private_ip
  dns_servers   = [module.transit_vnet[each.key].azfw_private_ip]
  
  name_hub                 = module.transit_vnet[each.key].name
  resource_group_name_hub  = azurerm_resource_group.rgtran[each.key].name
  vnet_id_hub              = module.transit_vnet[each.key].id
  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud

  law_resource_id      = module.law.id
  law_workspace_id     = module.law.workspace_id
  law_workspace_region = module.law.location
  dce_id               = each.key == "primary" ? module.law.dce_id_primary : module.law.dce_id_secondary
  dcr_id_windows       = module.law.dcr_id_windows

  storage_account_id_flow_logs         = module.storage_account_flow_logs[each.key].id
  network_watcher_name                 = "${var.network_watcher_name_prefix}${each.value}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  sku_tools_size = var.sku_tools_size
  sku_tools_os   = var.sku_tools_os
  admin_username = var.admin_username
  admin_password = var.admin_password

  tags = local.tags
}


## Create Private DNS Zones and Virtual Network Links
##
module "private_dns_zones" {
  depends_on = [
    azurerm_resource_group.rgshared["primary"],
    module.shared_vnet
  ]

  source              = "../../modules/dns/private-dns-zone"
  resource_group_name = azurerm_resource_group.rgshared["primary"].name

  for_each = {
    for zone in local.private_dns_namespaces_with_regional_zones :
    zone => zone
  }

  name    = each.value
  vnet_id = module.shared_vnet["primary"].id

  tags = local.tags
}

## If the second region is being deployed, create virtual network links to the existing Private DNS Zones
##
resource "azurerm_private_dns_zone_virtual_network_link" "link-second-region" {
  depends_on = [
    module.private_dns_zones
  ]
  for_each = var.multi_region == true ? {
    for zone in local.private_dns_namespaces_with_regional_zones :
    zone => zone
  } : {}

  name                  = "${each.value}-r2link"
  resource_group_name   = azurerm_resource_group.rgshared["primary"].name
  private_dns_zone_name = each.value
  virtual_network_id    = module.shared_vnet["secondary"].id
  registration_enabled  = false
  tags                  = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create Workload Virtual Networks
##
module "workload_vnet_1" {
  for_each = local.regions

  depends_on = [
    azurerm_resource_group.rgwork,
    module.shared_vnet,
    azurerm_virtual_network_dns_servers.dns_servers
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = each.value
  location_code       = local.region_abbreviations[each.value]
  resource_group_name = azurerm_resource_group.rgwork[each.key].name
  workload_number     = "1"

  address_space_vnet = each.key == "primary" ? local.vnet_cidr_wl1_pri : local.vnet_cidr_wl1_sec
  subnet_cidr_app    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 0) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 0)
  subnet_cidr_data   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 1) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 1)
  subnet_cidr_svc    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 2) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 2)
  subnet_cidr_agw    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 3) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 3)
  subnet_cidr_apim   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 4) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 4)
  subnet_cidr_amlcpt = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 5) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 5)
  subnet_cidr_mgmt   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 6) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 6)
  subnet_cidr_vint   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl1_pri, 3, 7) : cidrsubnet(local.vnet_cidr_wl1_sec, 3, 7)

  fw_private_ip = module.transit_vnet[each.key].azfw_private_ip
  dns_servers   = [module.transit_vnet[each.key].azfw_private_ip]
  
  name_hub                   = module.transit_vnet[each.key].name
  resource_group_name_hub    = azurerm_resource_group.rgtran[each.key].name
  vnet_id_hub                = module.transit_vnet[each.key].id
  name_shared                = module.shared_vnet["primary"].name
  resource_group_name_shared = azurerm_resource_group.rgshared["primary"].name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage_account_flow_logs[each.key].id
  network_watcher_name                 = "${var.network_watcher_name_prefix}${each.value}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

module "workload_vnet_2" {
  for_each = local.regions

  depends_on = [
    azurerm_resource_group.rgwork,
    module.shared_vnet,
    azurerm_virtual_network_dns_servers.dns_servers
  ]

  source              = "../../modules/vnet/hub-and-spoke/workload-standard"
  random_string       = random_string.unique.result
  location            = each.value
  location_code       = local.region_abbreviations[each.value]
  resource_group_name = azurerm_resource_group.rgwork[each.key].name
  workload_number     = "2"

  address_space_vnet = each.key == "primary" ? local.vnet_cidr_wl2_pri : local.vnet_cidr_wl2_sec
  subnet_cidr_app    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 0) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 0)
  subnet_cidr_data   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 1) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 1)
  subnet_cidr_svc    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 2) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 2)
  subnet_cidr_agw    = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 3) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 3)
  subnet_cidr_apim   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 4) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 4)
  subnet_cidr_amlcpt = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 5) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 5)
  subnet_cidr_mgmt   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 6) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 6)
  subnet_cidr_vint   = each.key == "primary" ? cidrsubnet(local.vnet_cidr_wl2_pri, 3, 7) : cidrsubnet(local.vnet_cidr_wl2_sec, 3, 7)

  fw_private_ip = module.transit_vnet[each.key].azfw_private_ip
  dns_servers   = [module.transit_vnet[each.key].azfw_private_ip]
  
  name_hub                   = module.transit_vnet[each.key].name
  resource_group_name_hub    = azurerm_resource_group.rgtran[each.key].name
  vnet_id_hub                = module.transit_vnet[each.key].id
  name_shared                = module.shared_vnet["primary"].name
  resource_group_name_shared = azurerm_resource_group.rgshared["primary"].name
  sub_id_shared              = data.azurerm_subscription.current.subscription_id

  law_resource_id = module.law.id

  storage_account_id_flow_logs         = module.storage_account_flow_logs[each.key].id
  network_watcher_name                 = "${var.network_watcher_name_prefix}${each.value}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

## Create centralized Azure Key Vault (Primary region only)
##
module "central_keyvault" {
  depends_on = [
    azurerm_resource_group.rgshared
  ]

  source                  = "../../modules/key-vault"
  random_string           = random_string.unique.result
  location                = var.location_primary
  location_code           = local.location_code_primary
  resource_group_name     = azurerm_resource_group.rgshared["primary"].name
  purpose                 = "cnt"
  law_resource_id         = module.law.id
  kv_admin_object_id      = var.key_vault_admin
  firewall_default_action = "Allow"

  firewall_ip_rules = [var.trusted_ip]
  tags              = local.tags
}

## Add virtual machine credentials to Azure Key Vault (separate secrets)
##
resource "azurerm_key_vault_secret" "vm_username" {
  depends_on = [module.central_keyvault]
  
  name         = "vm-admin-username"
  value        = var.admin_username
  key_vault_id = module.central_keyvault.id
  content_type = "username"
}

resource "azurerm_key_vault_secret" "vm_password" {
  depends_on = [module.central_keyvault]
  
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = module.central_keyvault.id
  content_type = "password"
}

## DNS Configuration Updates
##
resource "null_resource" "update_firewall_dns_policy" {
  for_each = local.regions

  depends_on = [module.private_dns_zones]
  
  triggers = {
    firewall_policy_id = module.transit_vnet[each.key].policy_id
    dns_resolver_ip    = module.shared_vnet[each.key].private_resolver_inbound_endpoint_ip
  }
  
  provisioner "local-exec" {
    command = "az network firewall policy update --ids ${module.transit_vnet[each.key].policy_id} --dns-servers ${module.shared_vnet[each.key].private_resolver_inbound_endpoint_ip}"
  }
}

resource "azurerm_virtual_network_dns_servers" "dns_servers" {
  for_each = local.regions

  depends_on = [null_resource.update_firewall_dns_policy]
  
  virtual_network_id = module.transit_vnet[each.key].id
  dns_servers        = [module.transit_vnet[each.key].azfw_private_ip]
}
