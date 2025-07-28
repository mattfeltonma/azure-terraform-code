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

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]

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

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]

  law_resource_id = module.law.id
}

## Create a transit services virtual network
##
module "transit-vnet-pri" {
  depends_on = [
    azurerm_resource_group.rgtran-pri,
    module.law,
    module.storage-account-flow-logs-pri
  ]

  source              = "../../modules/vnet/hub-and-spoke/transit-azfw"
  random_string       = random_string.unique.result
  location            = var.location_primary
  location_code       = local.location_code_primary
  resource_group_name = azurerm_resource_group.rgtran-pri.name

  address_space_vnet   = local.vnet_cidr_tr_pri
  subnet_cidr_gateway  = cidrsubnet(local.vnet_cidr_tr_pri, 3, 0)
  subnet_cidr_firewall = cidrsubnet(local.vnet_cidr_tr_pri, 3, 1)
  subnet_cidr_dns      = cidrsubnet(local.vnet_cidr_ss_pri, 3, 1)

  address_space_onpremises = var.address_space_onpremises
  address_space_apim = [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 4),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 4)
  ]
  address_space_amlcpt = [
    cidrsubnet(local.vnet_cidr_wl1_pri, 3, 5),
    cidrsubnet(local.vnet_cidr_wl2_pri, 3, 5)

  ]
  address_space_azure = var.address_space_cloud
  vnet_cidr_ss        = local.vnet_cidr_ss_pri
  vnet_cidr_wl = [
    local.vnet_cidr_wl1_pri,
    local.vnet_cidr_wl2_pri
  ]

  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_primary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

module "transit-vnet-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_resource_group.rgtran-sec,
    module.law,
    module.storage-account-flow-logs-sec
  ]

  source              = "../../modules/vnet/hub-and-spoke/transit-azfw"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgtran-sec[0].name

  address_space_vnet   = local.vnet_cidr_tr_sec
  subnet_cidr_gateway  = cidrsubnet(local.vnet_cidr_tr_sec, 3, 0)
  subnet_cidr_firewall = cidrsubnet(local.vnet_cidr_tr_sec, 3, 1)
  subnet_cidr_dns      = cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)

  address_space_onpremises = var.address_space_onpremises
  address_space_apim = [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 4),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 4)
  ]
  address_space_amlcpt = [
    cidrsubnet(local.vnet_cidr_wl1_sec, 3, 5),
    cidrsubnet(local.vnet_cidr_wl2_sec, 3, 5)
  ]
  address_space_azure = var.address_space_cloud
  vnet_cidr_ss        = local.vnet_cidr_ss_sec
  vnet_cidr_wl = [
    local.vnet_cidr_wl1_sec,
    local.vnet_cidr_wl2_sec
  ]

  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_secondary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  storage_account_id_flow_logs         = module.storage-account-flow-logs-sec[0].id
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

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

  hub_and_spoke = true

  address_space_vnet  = local.vnet_cidr_ss_pri
  subnet_cidr_bastion = cidrsubnet(local.vnet_cidr_ss_pri, 3, 0)
  subnet_cidr_dnsin   = cidrsubnet(local.vnet_cidr_ss_pri, 3, 1)
  subnet_cidr_dnsout  = cidrsubnet(local.vnet_cidr_ss_pri, 3, 2)
  subnet_cidr_tools   = cidrsubnet(local.vnet_cidr_ss_pri, 3, 3)
  subnet_cidr_pe      = cidrsubnet(local.vnet_cidr_ss_pri, 3, 4)
  fw_private_ip       = module.transit-vnet-pri.azfw_private_ip
  dns_servers = [
    module.transit-vnet-pri.azfw_private_ip
  ]
  name_hub                 = module.transit-vnet-pri.name
  resource_group_name_hub  = azurerm_resource_group.rgtran-pri.name
  vnet_id_hub              = module.transit-vnet-pri.id
  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud

  law_resource_id      = module.law.id
  law_workspace_id     = module.law.workspace_id
  law_workspace_region = module.law.location
  dce_id               = module.law.dce_id_primary
  dcr_id_windows       = module.law.dcr_id_windows

  storage_account_id_flow_logs         = module.storage-account-flow-logs-pri.id
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_primary}"
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

module "shared-vnet-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_resource_group.rgshared-sec,
    module.transit-vnet-sec
  ]

  source              = "../../modules/vnet/all/shared"
  random_string       = random_string.unique.result
  location            = var.location_secondary
  location_code       = local.location_code_secondary
  resource_group_name = azurerm_resource_group.rgshared-sec[0].name

  hub_and_spoke = true

  address_space_vnet  = local.vnet_cidr_ss_sec
  subnet_cidr_bastion = cidrsubnet(local.vnet_cidr_ss_sec, 3, 0)
  subnet_cidr_dnsin   = cidrsubnet(local.vnet_cidr_ss_sec, 3, 1)
  subnet_cidr_dnsout  = cidrsubnet(local.vnet_cidr_ss_sec, 3, 2)
  subnet_cidr_tools   = cidrsubnet(local.vnet_cidr_ss_sec, 3, 3)
  subnet_cidr_pe      = cidrsubnet(local.vnet_cidr_ss_sec, 3, 4)
  fw_private_ip       = module.transit-vnet-sec[0].azfw_private_ip
  dns_servers = [
    module.transit-vnet-sec[0].azfw_private_ip
  ]
  name_hub                 = module.transit-vnet-sec[0].name
  resource_group_name_hub  = azurerm_resource_group.rgtran-sec[0].name
  vnet_id_hub              = module.transit-vnet-sec[0].id
  address_space_onpremises = var.address_space_onpremises
  address_space_azure      = var.address_space_cloud

  law_resource_id      = module.law.id
  law_workspace_id     = module.law.workspace_id
  law_workspace_region = module.law.location
  dce_id               = module.law.dce_id_secondary
  dcr_id_windows       = module.law.dcr_id_windows

  storage_account_id_flow_logs         = module.storage-account-flow-logs-sec[0].id
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_secondary}"
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

  firewall_ip_rules = [
    var.trusted_ip
  ]

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
    module.private_dns_zones
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


## Modify the DNS Server settings of the Azure Firewall Policy
##
resource "null_resource" "update-policy-dns-pri" {
  depends_on = [
    module.private_dns_zones
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
    az network firewall policy update --ids ${module.transit-vnet-pri.policy_id} --dns-servers ${module.shared-vnet-pri.private_resolver_inbound_endpoint_ip}
    EOF
  }
}

resource "null_resource" "update-policy-dns-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    module.private_dns_zones
  ]
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
    az network firewall policy update --ids ${module.transit-vnet-sec[0].policy_id} --dns-servers ${module.shared-vnet-sec[0].private_resolver_inbound_endpoint_ip}
    EOF
  }
}

## Modify DNS Server Settings on transit virtual network
##
resource "azurerm_virtual_network_dns_servers" "dns-servers-pri" {
  depends_on = [
    null_resource.update-policy-dns-pri
  ]
  virtual_network_id = module.transit-vnet-pri.id
  dns_servers = [
    module.transit-vnet-pri.azfw_private_ip
  ]
}

resource "azurerm_virtual_network_dns_servers" "dns-servers-sec" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    null_resource.update-policy-dns-sec
  ]
  virtual_network_id = module.transit-vnet-sec[0].id
  dns_servers = [
    module.transit-vnet-sec[0].azfw_private_ip
  ]
}

## Create a workload virtual network
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
  workload_number     = 1

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
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_primary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
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
  workload_number     = 2

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
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_primary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
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
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_secondary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
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
  workload_number     = 2

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
  network_watcher_name                 = "${var.network_watcher_name_prefix}${var.location_secondary}"
  network_watcher_resource_group_name  = var.network_watcher_resource_group_name
  traffic_analytics_workspace_guid     = module.law.workspace_id
  traffic_analytics_workspace_id       = module.law.id
  traffic_analytics_workspace_location = module.law.location

  tags = local.tags
}

## If this is the second region, then peer the transit virtual networks together
##
resource "azurerm_virtual_network_peering" "peer-r2-to-r1" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    module.workload1-vnet-pri,
    module.workload2-vnet-pri,
    module.workload1-vnet-sec,
    module.workload2-vnet-sec
  ]
  name                         = "peer-${var.location_secondary}-to-${var.location_primary}"
  resource_group_name          = azurerm_resource_group.rgtran-sec[0].name
  virtual_network_name         = module.transit-vnet-sec[0].name
  remote_virtual_network_id    = module.transit-vnet-pri.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "peer-r1-to-r2" {
  count = var.multi_region == true ? 1 : 0

  depends_on = [
    azurerm_virtual_network_peering.peer-r2-to-r1
  ]
  name                         = "peer-${var.location_primary}-to-${var.location_secondary}"
  resource_group_name          = azurerm_resource_group.rgtran-pri.name
  virtual_network_name         = module.transit-vnet-pri.name
  remote_virtual_network_id    = module.transit-vnet-sec[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

## If this is the second region, update the route tables so that traffic can flow between the regions
##
resource "azurerm_route" "routes-primary" {
  depends_on = [
    azurerm_virtual_network_peering.peer-r1-to-r2
  ]

  for_each = var.multi_region == true ? local.secondary_region_vnet_cidrs : {}

  name                   = "${local.route_prefix}${each.key}${local.location_code_primary}"
  resource_group_name    = azurerm_resource_group.rgtran-pri.name
  route_table_name       = module.transit-vnet-pri.route_table_name_azfw
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.transit-vnet-sec[0].azfw_private_ip
}

resource "azurerm_route" "routes-secondary" {
  depends_on = [
    azurerm_virtual_network_peering.peer-r1-to-r2
  ]

  for_each = var.multi_region == true ? local.primary_region_vnet_cidrs : {}

  name                   = "${local.route_prefix}${each.key}${local.location_code_secondary}"
  resource_group_name    = azurerm_resource_group.rgtran-sec[0].name
  route_table_name       = module.transit-vnet-sec[0].route_table_name_azfw
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.transit-vnet-pri.azfw_private_ip
}
