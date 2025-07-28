##### Create core resources
#####

# Create a random string to establish a unique name for resources
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
resource "azurerm_resource_group" "rg_demo_nsp" {
  name     = "rgdemonsp${random_string.unique.result}"
  location = var.location
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

##### Create core infrastructure
#####

# Create Log Analytics Workspace and Data Collection Endpoints and Data Collection Rules
#
module "law" {
  depends_on = [
    azurerm_resource_group.rg_demo_nsp
  ]

  source                      = "../../modules/monitor/log-analytics-workspace"
  random_string               = random_string.unique.result
  purpose                     = local.law_purpose
  location_primary            = var.location
  location_code_primary       = local.location_code
  resource_group_name_primary = azurerm_resource_group.rg_demo_nsp.name
  tags                        = local.tags
}

# Create Storage Account for Flow Logs
#
module "storage_account_flow_logs" {
  depends_on = [
    azurerm_resource_group.rg_demo_nsp,
    module.law
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = local.tags

  law_resource_id = module.law.id
}

# Create a virtual network to use for virtual machine access
#
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.vnet_name}nsp${local.location_code}${random_string.unique.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags

  address_space = [local.vnet_cidr_wl]
  dns_servers   = ["168.63.129.16"]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-vnet-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_virtual_network.vnet.id
  log_analytics_workspace_id = module.law.id


  enabled_log {
    category = "VMProtectionAlerts"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_subnet" "subnet_app" {
  name                              = local.subnet_name_app
  resource_group_name               = azurerm_resource_group.rg_demo_nsp.name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [cidrsubnet(local.vnet_cidr_wl, 3, 1)]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_bastion" {
  name                              = local.subnet_name_bastion
  resource_group_name               = azurerm_resource_group.rg_demo_nsp.name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [cidrsubnet(local.vnet_cidr_wl, 3, 0)]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_svc" {
  name                              = local.subnet_name_svc
  resource_group_name               = azurerm_resource_group.rg_demo_nsp.name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [cidrsubnet(local.vnet_cidr_wl, 3, 2)]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

# Create Private DNS Zones
#
module "private_dns_zone_keyvault" {
  depends_on = [
    azurerm_virtual_network.vnet
  ]

  source              = "../../modules/dns/private-dns-zone"
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name

  name    = "privatelink.vaultcore.azure.net"
  vnet_id = azurerm_virtual_network.vnet.id

  tags = var.tags
}

# Create network security groups
#
module "nsg_app" {
  source              = "../../modules/network-security-group"
  purpose             = "nspapp"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags

  law_resource_id = module.law.id
  security_rules = [
  ]
}

module "nsg_bastion" {
  source              = "../../modules/network-security-group"
  purpose             = "nspbst"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags

  law_resource_id = module.law.id
  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow inbound HTTPS to allow for connections to Bastion"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow inbound HTTPS to allow for managemen of Bastion instances"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound HTTPS to allow Azure Load Balancer health probes"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowBastionHostCommunication"
      description                = "Allow data plane communication between Bastion hosts"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [8080, 5701]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all inbound traffic"
      priority                   = 2000
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowSshRdpOutbound"
      description                = "Allow Bastion hosts to SSH and RDP to virtual machines"
      priority                   = 1100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [22, 2222, 3389, 3390]
      source_address_prefix      = "*"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureCloudOutbound"
      description                = "Allow Bastion to connect to dependent services in Azure"
      priority                   = 1110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "*"
      destination_address_prefix = "AzureCloud"
    },
    {
      name                       = "AllowBastionCommunication"
      description                = "Allow data plane communication between Bastion hosts"
      priority                   = 1120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [8080, 5701]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowHttpOutbound"
      description                = "Allow Bastion to connect to dependent services on the Internet"
      priority                   = 1130
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = 80
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    },
    {
      name                       = "DenyAllOutbound"
      description                = "Deny all outbound traffic"
      priority                   = 2100
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

module "nsg_svc" {
  source              = "../../modules/network-security-group"
  purpose             = "nspsvc"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags

  law_resource_id = module.law.id
  security_rules = [
  ]
}

# Associate network security groups with subnets
#
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    module.nsg_app
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = module.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_bastion" {
  depends_on = [
    azurerm_subnet.subnet_bastion,
    module.nsg_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_bastion.id
  network_security_group_id = module.nsg_bastion.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    module.nsg_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = module.nsg_svc.id
}

# Create Azure Bastion instance
#
module "bastion" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion
  ]

  source              = "../../modules/bastion"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name

  sku             = "Standard"
  subnet_id       = azurerm_subnet.subnet_bastion.id
  law_resource_id = module.law.id

  tags = var.tags
}

# Create a user-assigned managed identity that will be used by virtual machine
#
module "managed_identity_vm" {
  source              = "../../modules/managed-identity"
  purpose             = "nspvm"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags
}

module "managed_identity_storage_account" {
  source              = "../../modules/managed-identity"
  purpose             = "nspst"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags
}

# Pause for 10 seconds to allow the managed identity that was created to be replicated
#
resource "time_sleep" "wait_umi_creation" {
  depends_on = [
    module.managed_identity_vm,
    module.managed_identity_storage_account
  ]

  create_duration = "10s"
}

# Create Key Vault which is enabled with Private Link
#
module "wl_keyvault_private_link" {
  depends_on = [
    azurerm_resource_group.rg_demo_nsp,
    module.managed_identity_vm,
    module.managed_identity_storage_account
  ]

  source              = "../../modules/key-vault"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  purpose             = "nspkv"
  law_resource_id     = module.law.id

  kv_admin_object_id      = var.key_vault_admin
  firewall_default_action = "Deny"
  firewall_ip_rules = [
    var.tf_server_ip
  ]

  purge_protection = true

  tags = local.tags
}

# Add a secret to the Key Vault with a Private Endpoint
#
resource "azurerm_key_vault_secret" "special_pl" {
  depends_on = [
    module.wl_keyvault_private_link
  ]
  name         = "special"
  value        = "privatelink"
  key_vault_id = module.wl_keyvault_private_link.id
}

# Add a key to be used for the storage account CMK
#
resource "azurerm_key_vault_key" "storage" {
  depends_on = [
    azurerm_key_vault_secret.special_pl
  ]
  name         = "storage"
  key_vault_id = module.wl_keyvault_private_link.id
  key_type     = "RSA"
  key_size     = 4096
  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}

# Create public IP address for the virtual machine
#
module "vm_public_ip_address" {
  source              = "../../modules/public-ip"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name

  purpose = "nsptool"
  law_resource_id = module.law.id

  tags                = var.tags
}

# Create Key Vault which is not enabled with Private Link
#
module "wl_keyvault_no_private_link" {
  depends_on = [
    azurerm_resource_group.rg_demo_nsp,
    module.managed_identity_vm,
    module.vm_public_ip_address
  ]

  source              = "../../modules/key-vault"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  purpose             = "nspkvnopl"
  law_resource_id     = module.law.id

  kv_admin_object_id      = var.key_vault_admin
  firewall_default_action = "Deny"
  firewall_ip_rules = [
    var.tf_server_ip,
    module.vm_public_ip_address.ip_address
  ]

  purge_protection = true

  tags = local.tags
}

# Add a secret to the Key Vault without a Private Endpoint
#
resource "azurerm_key_vault_secret" "special_no_pl" {
  depends_on = [
    module.wl_keyvault_private_link
  ]
  name         = "special"
  value        = "noprivatelink"
  key_vault_id = module.wl_keyvault_no_private_link.id
}

# Add a Private Endpoint for workload Key Vault that will include a Private Endpoint
#
module "private_endpoint_kv" {
  depends_on = [
    module.wl_keyvault_private_link,
    module.private_dns_zone_keyvault
  ]

  source              = "../../modules/private-endpoint"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  tags                = var.tags

  resource_name    = module.wl_keyvault_private_link.name
  resource_id      = module.wl_keyvault_private_link.id
  subresource_name = "vault"


  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_demo_nsp.name}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  ]
}

# Add role assignments to allow VM and Storage Account to secrets stored in the Key Vault
#
resource "azurerm_role_assignment" "umi_vm_kv_pl" {
  depends_on = [
    module.managed_identity_vm,
    module.wl_keyvault_private_link
  ]

  scope                = module.wl_keyvault_private_link.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity_vm.principal_id
}

resource "azurerm_role_assignment" "umi_vm_kv_nopl" {
  depends_on = [
    module.managed_identity_vm,
    module.wl_keyvault_no_private_link
  ]

  scope                = module.wl_keyvault_no_private_link.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity_vm.principal_id
}

resource "azurerm_role_assignment" "umi_st_kv" {
  depends_on = [
    module.managed_identity_storage_account,
    module.wl_keyvault_private_link
  ]

  scope                = module.wl_keyvault_private_link.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = module.managed_identity_storage_account.principal_id
}

# Pause for 120 seconds to allow RBAC assignments to propagate
#
resource "time_sleep" "wait_role_assignments" {
  depends_on = [
    azurerm_role_assignment.umi_vm_kv_pl,
    azurerm_role_assignment.umi_vm_kv_nopl,
    azurerm_role_assignment.umi_st_kv,

  ]

  create_duration = "120s"
}

# Create a storage account with a CMK
#
resource "azurerm_storage_account" "storage_account" {
  name                = "stnsp${local.location_code}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name
  location            = var.location
  tags                = var.tags

  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  identity {
    type = "UserAssigned"
    identity_ids = [
      module.managed_identity_storage_account.id
    ]
  }

  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.storage.id
    user_assigned_identity_id = module.managed_identity_storage_account.id
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]

    ip_rules = [
      var.tf_server_ip
    ]
  }

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

# Configure diagnostic settings for the storage account and the blob endpoint
#
resource "azurerm_monitor_diagnostic_setting" "diag-storage-base" {

  depends_on = [azurerm_storage_account.storage_account]

  name                       = "diag-base"
  target_resource_id         = azurerm_storage_account.storage_account.id
  log_analytics_workspace_id = module.law.id

  metric {
    category = "Transaction"
  }

  metric {
    category = "Capacity"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-blob" {

  depends_on = [
    azurerm_storage_account.storage_account,
  azurerm_monitor_diagnostic_setting.diag-storage-base]

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/blobServices/default"
  log_analytics_workspace_id = module.law.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
  }

  metric {
    category = "Capacity"
  }
}

# Create the flow log and enable traffic analytics
#
resource "azapi_resource" "vnet_flow_log" {
  depends_on = [
    azurerm_virtual_network.vnet
  ]

  type      = "Microsoft.Network/networkWatchers/flowLogs@2023-11-01"
  name      = "flnsp${local.location_code}${random_string.unique.result}"
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.network_watcher_resource_group_name}/providers/Microsoft.Network/networkWatchers/${var.network_watcher_name}${var.location}"

  body = {
    properties = {
      enabled = local.flow_logs_enabled
      format = {
        type    = "JSON"
        version = 2
      }

      retentionPolicy = {
        enabled = local.flow_logs_retention_policy_enabled
        days    = local.flow_logs_retention_days
      }

      storageId        = module.storage_account_flow_logs.id
      targetResourceId = azurerm_virtual_network.vnet.id

      flowAnalyticsConfiguration = {
        networkWatcherFlowAnalyticsConfiguration = {
          enabled                  = local.traffic_analytics_enabled
          trafficAnalyticsInterval = local.traffic_analytics_interval_in_minutes
          workspaceId              = module.law.workspace_id
          workspaceRegion          = module.law.location
          workspaceResourceId      = module.law.id
        }
      }
    }
  }
  tags = var.tags
}

# Create a Linux tool server
#
module "linux_tool" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_app,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    module.managed_identity_vm
  ]

  source              = "../../modules/virtual-machine/ubuntu-tools"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_demo_nsp.name

  purpose        = "nsptool"
  admin_username = var.admin_username
  admin_password = var.admin_password
  identities = {
    type         = "UserAssigned"
    identity_ids = [module.managed_identity_vm.id]
  }

  vm_size = var.sku_vm_size
  image_reference = {
    publisher = local.image_preference_publisher
    offer     = local.image_preference_offer
    sku       = local.image_preference_sku
    version   = local.image_preference_version
  }

  subnet_id                     = azurerm_subnet.subnet_app.id
  private_ip_address_allocation = "Static"
  nic_private_ip_address        = cidrhost(cidrsubnet(local.vnet_cidr_wl, 3, 1), 20)
  public_ip_address_id = module.vm_public_ip_address.id

  law_resource_id = module.law.id
  dce_id          = module.law.dce_id_primary
  dcr_id          = module.law.dcr_id_linux

  tags = var.tags
}

##### Create Network Security Perimeter and supporting resources
#####

# Create Network Security Perimeter and configure its diagnostic settings
#
resource "azapi_resource" "nsp_st_cmk" {
  depends_on = [
    module.linux_tool,
    azurerm_storage_account.storage_account,
    module.wl_keyvault_private_link,
    module.private_endpoint_kv
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2023-07-01-preview"
  name      = "nspstcmk${local.location_code}${random_string.unique.result}"
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_demo_nsp.name}"
  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "diag-nsp" {
  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_st_cmk.id
  log_analytics_workspace_id = module.law.id


  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category =  "NspPublicOutboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspIntraPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesAllowed"
  }

  enabled_log {
    category = "NspPublicOutboundResourceRulesDenied"
  }

  enabled_log {
    category = "NspPrivateInboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterOutboundAllowed"
  }

  enabled_log {
    category = "NspCrossPerimeterInboundAllowed"
  }

  enabled_log {
    category = "NspOutboundAttempt"
  }
}

# Create two profiles in the NSP. One profile will be used for the Key Vault and other for the storage account. Each profile will have different access rules
#
resource "azapi_resource" "profile_kv_cmk" {
  depends_on = [
    azapi_resource.nsp_st_cmk
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2023-07-01-preview"
  name      = "profilekv"
  location  = var.location
  parent_id = azapi_resource.nsp_st_cmk.id
  tags = var.tags
}

resource "azapi_resource" "profile_st_cmk" {
  depends_on = [
    azapi_resource.nsp_st_cmk
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2023-07-01-preview"
  name      = "profilest"
  location  = var.location
  parent_id = azapi_resource.nsp_st_cmk.id
  tags = var.tags
}

# Create access rules for the profile applied to the storage account. The storage account will be accessible by the VM's public IP address.
#
resource "azapi_resource" "access_rule_st_cmk" {
  depends_on = [
    azapi_resource.profile_st_cmk
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2023-07-01-preview"
  name      = "access-rule-trusted-machines"
  location  = var.location
  parent_id = azapi_resource.profile_st_cmk.id

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        module.vm_public_ip_address.ip_address,
        var.tf_server_ip
      ]

    }
  }
  tags = var.tags
}

# Create a resource associations
#
resource "azapi_resource" "assoc_kv_pl" {
  depends_on = [
    azapi_resource.profile_st_cmk
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2023-07-01-preview"
  name      = "ass${module.wl_keyvault_private_link.name}"
  location  = var.location
  parent_id = azapi_resource.nsp_st_cmk.id

  body = {
    properties = {
      accessMode = "Learning"
      privateLinkResource = {
        id = module.wl_keyvault_private_link.id
      }
      profile = {
        id = azapi_resource.profile_kv_cmk.id
      }
    }
  }
  tags = var.tags
}

resource "azapi_resource" "assoc_st" {
  depends_on = [
    azapi_resource.profile_st_cmk
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2023-07-01-preview"
  name      = "ass${azurerm_storage_account.storage_account.name}"
  location  = var.location
  parent_id = azapi_resource.nsp_st_cmk.id

  body = {
    properties = {
      accessMode = "Learning"
      privateLinkResource = {
        id = azurerm_storage_account.storage_account.id
      }
      profile = {
        id = azapi_resource.profile_st_cmk.id
      }
    }
  }
  tags = var.tags
}