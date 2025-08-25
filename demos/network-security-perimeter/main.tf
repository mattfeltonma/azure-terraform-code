########## Core infrastructure
##########

## Create a random string to establish a unique name for resources
##
resource "random_string" "unique" {
  length      = 3
  min_numeric = 3
  numeric     = true
  special     = false
  lower       = true
  upper       = false
}

## Create resource group where resources from this template will be deployed to
##
resource "azurerm_resource_group" "rg_work" {
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

## Create a log analytics workspace where the resources in this environment will deliver logs to
##
module "log_analytics_workspace" {
  depends_on = [
    azurerm_resource_group.rg_work
  ]

  source                      = "../../modules/monitor/log-analytics-workspace"
  random_string               = random_string.unique.result
  purpose                     = "nsp"
  location_primary            = var.location
  location_code_primary       = local.location_code
  resource_group_name_primary = azurerm_resource_group.rg_work.name
  tags                        = local.tags
}

## Create a storage account to store virtual network flow logs
##
module "storage_account_flow_logs" {
  depends_on = [
    azurerm_resource_group.rg_work,
    module.log_analytics_workspace
  ]

  source              = "../../modules/storage-account"
  purpose             = "flv"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = local.tags

  network_trusted_services_bypass = ["AzureServices", "Logging", "Metrics"]

  law_resource_id = module.log_analytics_workspace.id
}

## Create a virtual network for the resources deployed to this demo
## 
resource "azurerm_virtual_network" "vnet" {
  name                = "vnetnsp${local.location_code}${random_string.unique.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  address_space = [
    var.address_space_vnet
  ]

  # Use the wireserver for DNS resolution
  dns_servers = [
    "168.63.129.16"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Enable virtual network flow logs
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "flvnet${local.location_code}${random_string.unique.result}"
  network_watcher_name = "${var.network_watcher_name}${var.location}"
  resource_group_name  = var.network_watcher_resource_group_name

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet.id

  # Enable VNet Flow Logs and use version 2
  enabled = true
  version = 2

  # Send the flow logs to a storage account and retain them for 7 days
  storage_account_id = module.storage_account_flow_logs.id
  retention_policy {
    enabled = true
    days    = 7
  }

  # Send the flow logs to Traffic Analytics and send every 10 minutes
  traffic_analytics {
    enabled               = true
    workspace_id          = module.log_analytics_workspace.workspace_id
    workspace_region      = module.log_analytics_workspace.location
    workspace_resource_id = module.log_analytics_workspace.id
    interval_in_minutes   = 10
  }


  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a subnet for the virtual machine
##
resource "azurerm_subnet" "subnet_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg_work.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet
  address_prefixes = [cidrsubnet(var.address_space_vnet, 2, 1)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create a subnet for the Azure Bastion
##
resource "azurerm_subnet" "subnet_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg_work.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet  
  address_prefixes = [cidrsubnet(var.address_space_vnet, 2, 0)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create a subnet for the Private Endpoints
##
resource "azurerm_subnet" "subnet_svc" {
  name                 = "snet-svc"
  resource_group_name  = azurerm_resource_group.rg_work.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet
  address_prefixes = [cidrsubnet(var.address_space_vnet, 2, 2)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create Private DNS Zones for services that will be used in this lab
##
module "private_dns_zones" {
  for_each = local.private_dns_zones

  depends_on = [
    azurerm_virtual_network.vnet
  ]

  source              = "../../modules/dns/private-dns-zone"
  resource_group_name = azurerm_resource_group.rg_work.name

  name    = each.value
  vnet_id = azurerm_virtual_network.vnet.id

  tags = var.tags
}

## Create network security group for the virtual machine subnet
##
module "nsg_vm" {
  source              = "../../modules/network-security-group"
  purpose             = "nspvm"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  law_resource_id = module.log_analytics_workspace.id
  security_rules = [
  ]
}

## Associate the network security group with the virtual machine subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_vm" {
  depends_on = [
    azurerm_subnet.subnet_vm,
    module.nsg_vm
  ]

  subnet_id                 = azurerm_subnet.subnet_vm.id
  network_security_group_id = module.nsg_vm.id
}

## Create a network security group for the Azure Bastion subnet
##
module "nsg_bastion" {
  source              = "../../modules/network-security-group"
  purpose             = "nspbst"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  law_resource_id = module.log_analytics_workspace.id
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

## Associate the network security group with the Azure Bastion subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_bastion" {
  depends_on = [
    azurerm_subnet.subnet_bastion,
    module.nsg_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_bastion.id
  network_security_group_id = module.nsg_bastion.id
}

## Create a network security group for the subnet where the Private Endpoints will be deployed to
##
module "nsg_svc" {
  source              = "../../modules/network-security-group"
  purpose             = "nspsvc"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  law_resource_id = module.log_analytics_workspace.id
  security_rules = [
  ]
}

## Associate the network security group with the subnet where the Private Endpoints will be deployed to
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    module.nsg_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = module.nsg_svc.id
}


## Create Azure Bastion instance to allow for remote access to the virtual machines
##
module "bastion" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion
  ]

  source              = "../../modules/bastion"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name

  sku             = "Basic"
  subnet_id       = azurerm_subnet.subnet_bastion.id
  law_resource_id = module.log_analytics_workspace.id

  tags = var.tags
}

## Create a user-assigned managed identity that will be associated to the virtual machine and used
## to authenticate to the resources in this lab
module "managed_identity_vm" {
  source              = "../../modules/managed-identity"
  purpose             = "nspvm"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags
}

## Create a Windows tool server
##
module "vm_windows_tool" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_vm,
    module.managed_identity_vm
  ]

  source              = "../../modules/virtual-machine/windows-tools"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name

  purpose        = "nsptool"
  admin_username = var.admin_username
  admin_password = var.admin_password
  identities = {
    type         = "UserAssigned"
    identity_ids = [module.managed_identity_vm.id]
  }

  vm_size = var.sku_vm_size

  subnet_id                     = azurerm_subnet.subnet_vm.id
  private_ip_address_allocation = "Dynamic"
  public_ip_address_enable      = true

  # Configure the Log Analytics integration for the virtual machine resources
  log_analytics_workspace_id = module.log_analytics_workspace.id
  dce_id                     = module.log_analytics_workspace.dce_id_primary
  dcr_id                     = module.log_analytics_workspace.dcr_id_windows

  tags = var.tags
}

########## Demo 1
########## Create two Key Vault instances with one allowing public network access and allowing
########## access only through a Private Endpoint.


## Create Key Vault which will host a secret and be accessible via public endpoint
##
module "key_vault_public_secret_demo1" {
  depends_on = [
    azurerm_resource_group.rg_work,
  ]

  source              = "../../modules/key-vault"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  purpose             = "nsppub"
  law_resource_id     = module.log_analytics_workspace.id

  # The object id listed here will be assigned the Key Vault Administrator RBAC role
  kv_admin_object_id = var.key_vault_admin_object_id

  # Block public access but allow exceptions for trusted Azure services and the IP of the machine
  # deploying the Terraform code
  firewall_default_action = "Allow"

  # Disable purge protection
  purge_protection = false

  tags = local.tags
}

## Add a secret to the Key Vault that supports public network access
##
resource "azurerm_key_vault_secret" "secret_public_demo1" {
  depends_on = [
    module.key_vault_public_secret_demo1
  ]
  name         = "secret-public-word"
  value        = "banana"
  key_vault_id = module.key_vault_public_secret_demo1.id
}

## Create Key Vault which will host a secret and be accessible only via a Private Endpoint
## Add an IP-based exception for the machine deploying the Terraform code to support re-deployments
module "key_vault_private_secret_demo1" {
  depends_on = [
    azurerm_resource_group.rg_work
  ]

  source              = "../../modules/key-vault"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  purpose             = "nsppriv"
  law_resource_id     = module.log_analytics_workspace.id

  # The object id listed here will be assigned the Key Vault Administrator RBAC role
  kv_admin_object_id = var.key_vault_admin_object_id

  # Block public access but allow exceptions for trusted Azure services and the IP of the machine
  # deploying the Terraform code
  firewall_default_action = "Deny"
  firewall_ip_rules       = [var.trusted_ip]

  # Disable purge protection
  purge_protection = false

  tags = local.tags
}

## Add a secret to the Key Vault that supports network access through a Private Endpoint
##
resource "azurerm_key_vault_secret" "secret_private_demo1" {
  depends_on = [
    module.key_vault_private_secret_demo1
  ]
  name         = "secret-private-word"
  value        = "orange"
  key_vault_id = module.key_vault_private_secret_demo1.id
}

## Create a Private Endpoint for the Key Vault instance that supports network access
## through a Private Endpoint.
module "private_endpoint_key_vault_private_secret_demo1" {
  depends_on = [
    module.key_vault_private_secret_demo1,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc
  ]

  source              = "../../modules/private-endpoint"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.key_vault_private_secret_demo1.name
  resource_id      = module.key_vault_private_secret_demo1.id
  subresource_name = "vault"

  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  ]
}

## Pause for 10 seconds to allow the managed identities created to be replicated through Entra ID
##
resource "time_sleep" "wait_umi_creation_vm" {
  depends_on = [
    module.managed_identity_vm
  ]

  create_duration = "10s"
}

## Add role assignments to allow VM to retrieve secrets from the Key Vault
##
resource "azurerm_role_assignment" "umi_vm_key_vault_private_secret_demo1" {
  depends_on = [
    module.managed_identity_vm,
    module.key_vault_private_secret_demo1,
    time_sleep.wait_umi_creation_vm
  ]

  scope                = module.key_vault_private_secret_demo1.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity_vm.principal_id
}

resource "azurerm_role_assignment" "umi_vm_key_vault_public_secret_demo1" {
  depends_on = [
    module.managed_identity_vm,
    module.key_vault_public_secret_demo1,
    time_sleep.wait_umi_creation_vm
  ]

  scope                = module.key_vault_public_secret_demo1.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity_vm.principal_id
}

## Pause for 120 seconds to allow RBAC assignments to propagate
##
resource "time_sleep" "wait_umi_rbac_creation_vm" {
  depends_on = [
    azurerm_role_assignment.umi_vm_key_vault_private_secret_demo1,
    azurerm_role_assignment.umi_vm_key_vault_public_secret_demo1
  ]

  create_duration = "120s"
}

########## Demo 2
########## Create Key Vaults and Storage Accounts for Storage / Key Vault demonstration
##########

## Create Key Vault which will host the CMK for the storage account and will block public access
##
module "key_vault_demo2" {
  depends_on = [
    azurerm_resource_group.rg_work,
  ]

  source              = "../../modules/key-vault"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  purpose             = "nspd2"
  law_resource_id     = module.log_analytics_workspace.id

  # The object id listed here will be assigned the Key Vault Administrator RBAC role
  kv_admin_object_id = var.key_vault_admin_object_id

  # Block public access but allow exceptions for trusted Azure services and the IP of the machine
  # deploying the Terraform code
  firewall_bypass         = "AzureServices"
  firewall_default_action = "Deny"
  firewall_ip_rules = [
    var.trusted_ip
  ]

  # Enable soft delete and purge protection to support CMK
  soft_delete_retention_days = 7
  purge_protection           = true

  tags = local.tags
}

## Add a key to be used for the storage account CMK
##
resource "azurerm_key_vault_key" "storage_key_demo2" {
  depends_on = [
    module.key_vault_demo2
  ]
  name         = "storage"
  key_vault_id = module.key_vault_demo2.id
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

## Create a user-assigned managed identity that will be associated to the storage account and used
## to authenticate to the key vault to retrieve the CMK
module "managed_identity_storage_account_demo2" {
  source              = "../../modules/managed-identity"
  purpose             = "nspstdemo2"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags
}

## Pause for 10 seconds to allow RBAC assignments to propagate
##
resource "time_sleep" "wait_umi_creation_storage_demo2" {
  depends_on = [
    module.managed_identity_storage_account_demo2
  ]

  create_duration = "10s"
}

## Add role assignments to allow the storage account to retrieve the CMK from the Key Vault
##
resource "azurerm_role_assignment" "umi_storage_cmk_demo2" {
  depends_on = [
    module.managed_identity_storage_account_demo2,
    module.key_vault_demo2,
    time_sleep.wait_umi_creation_storage_demo2
  ]

  scope                = module.key_vault_demo2.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = module.managed_identity_storage_account_demo2.principal_id
}

## Pause for 120 seconds to allow RBAC assignments to propagate
##
resource "time_sleep" "wait_umi_rbac_creation_storage_demo2" {
  depends_on = [
    azurerm_role_assignment.umi_storage_cmk_demo2
  ]

  create_duration = "120s"
}

## Create a storage account that will be used to demonstrate CMK
##
resource "azurerm_storage_account" "storage_account_cmk_demo2" {
  name                = "stnsp${local.location_code}${var.location}"
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = var.location
  tags                = var.tags

  identity {
    type = "UserAssigned"
    identity_ids = [
      module.managed_identity_storage_account_demo2.id
    ]
  }

  # Configure basic storage config settings
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable storage access key
  shared_access_key_enabled = false

  # Block any public access of blobs
  allow_nested_items_to_be_public = false

  # Block all public network access
  network_rules {
    default_action = "Deny"
  }



  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Demo 3 
########## Create an Azure AI Search and Azure Storage instance to demonstrate import and vectorize
########## 

## Create an Azure AI Search instance that will be used to demonstrate integration with the storage account
##
module "ai_search_demo3" {
  depends_on = [
    azurerm_resource_group.rg_work,
    module.log_analytics_workspace
  ]

  source              = "../../modules/ai-search"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  resource_group_id   = azurerm_resource_group.rg_work.id
  purpose             = "nsp"
  tags                = var.tags

  sku = "standard"

  # Resource logs for the Azure AI Services will be sent to this Log Analytics Workspace
  law_resource_id = module.log_analytics_workspace.id
}

## Create a Private Endpoint for the AI Search instance
##
module "private_endpoint_ai_search_demo3" {
  depends_on = [
    module.ai_search_demo3,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    module.private_dns_zones
  ]

  source              = "../../modules/private-endpoint"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.ai_search_demo3.name
  resource_id      = module.ai_search_demo3.id
  subresource_name = "searchService"

  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.search.azure.com"
  ]
}

## Create an Azure OpenAI instance
##
module "openai" {
  depends_on = [
    azurerm_resource_group.rg_work,
    module.log_analytics_workspace
  ]

  source              = "../../modules/aoai"
  purpose             = "nsp"
  random_string       = random_string.unique.result
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = "westus3"
  location_code       = "wus3"

  # Block public network access and allow machine deploying Terraform through resource firewall
  allowed_ips = [
    var.trusted_ip
  ]
  public_network_access = false

  # Send logs created by service to this Log Analytics Workspace
  law_resource_id = module.log_analytics_workspace.id

  tags = var.tags
}

## Create Private Endpoint for AI Foundry account
##
module "private_endpoint_openai" {
  depends_on = [
    module.openai,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    module.private_dns_zones
  ]

  source              = "../../modules/private-endpoint"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.openai.name
  resource_id      = module.openai.id
  subresource_name = "account"

  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
  ]
}

## Create a storage account that will store a file consumed by AI Search
##`
module "storage_account_ai_search_data_demo3" {
  depends_on = [
    module.ai_search_demo3
  ]

  source              = "../../modules/storage-account"
  purpose             = "aisdata"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = local.tags

  # Add IP exception to allow Terraform to access data plane
  allowed_ips = [
    var.trusted_ip
  ]

  law_resource_id = module.log_analytics_workspace.id
}

## Create a Private Endpoint for the blob endpoint for the Storage Account where AI Search will pull its data from
##
module "private_endpoint_storage_account_ai_search_data_blob_demo3" {
  depends_on = [
    module.storage_account_ai_search_data_demo3,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    module.private_dns_zones
  ]

  source              = "../../modules/private-endpoint"
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = local.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_ai_search_data_demo3.name
  resource_id      = module.storage_account_ai_search_data_demo3.id
  subresource_name = "blob"

  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}

## Create a blob container in the storage account named data where file will be uploaded
##
resource "azurerm_storage_container" "blob_data" {
  name                  = "data"
  storage_account_id    = module.storage_account_ai_search_data_demo3.id
  container_access_type = "private"
}

## Create an Azure RBAC role assignment for the Storage Blob Data Contributor to the storage account
## to the system-assigned managed identity associated with the AI Search instance
resource "azurerm_role_assignment" "smi_aisearch_storage_blob_data_contributor" {
  depends_on = [
    module.ai_search_demo3,
    module.storage_account_ai_search_data_demo3
  ]

  scope                = module.storage_account_ai_search_data_demo3.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.ai_search_demo3.managed_identity_principal_id
}

########### Network Security Perimeter resources
###########

##### Create the Network Security Perimeter resources for Demo 1
#####

## Create Network Security Perimeter that will be used for Key Vaults and virtual machines
##
resource "azapi_resource" "nsp_demo1" {
  depends_on = [
    azurerm_resource_group.rg_work
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspdemo2${local.location_code}${random_string.unique.result}"
  location  = var.location
  parent_id = azurerm_resource_group.rg_work.id
  tags      = var.tags
}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_demo1" {
  depends_on = [
    azapi_resource.nsp_demo1
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_demo1.id
  log_analytics_workspace_id = module.log_analytics_workspace.id

  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesAllowed"
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

## Create a profile of which the Key Vault with network access restricted to a Private Endpoint will be added
## The Key Vault with public network access will be added interactively through the demo
resource "azapi_resource" "profile_nsp_key_vault_demo1" {
  depends_on = [
    azapi_resource.nsp_demo1
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pfkeyvault"
  location  = var.location
  parent_id = azapi_resource.nsp_demo1.id
  tags      = var.tags
}

## Associate the Key Vault with access restricted to a Private Endpoint to the profile
##
resource "azapi_resource" "assoc_key_vault_private_demo1" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_demo1
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "asrkeyvault"
  location                  = var.location
  parent_id                 = azapi_resource.nsp_demo1.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = module.key_vault_private_secret_demo1.id
      }
      profile = {
        id = azapi_resource.profile_nsp_key_vault_demo1.id
      }
    }
    tags = var.tags
  }

}

## Create an access rule allowing the machine deploying the Terraform continued access
## to the Key Vaults for redeployment
resource "azapi_resource" "access_rule_key_vault_demo1" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_demo1
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name      = "acrkeyvault"
  location  = var.location
  parent_id = azapi_resource.profile_nsp_key_vault_demo1.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        "${var.trusted_ip}/32"
      ]
    }
    tags = var.tags
  }
}

##### Create the Network Security Perimeter resources for Demo 2
#####

## Create Network Security Perimeter that will be used to demonstrate the storage account and CMK
##
resource "azapi_resource" "nsp_demo2" {
  depends_on = [
    azurerm_resource_group.rg_work
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspdemo1${local.location_code}${random_string.unique.result}"
  location  = var.location
  parent_id = azurerm_resource_group.rg_work.id
  tags      = var.tags
}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_demo2" {
  depends_on = [
    azapi_resource.nsp_demo2
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_demo2.id
  log_analytics_workspace_id = module.log_analytics_workspace.id

  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesAllowed"
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

## Create a profile that the storage account will be associated to. The storage account will be associated interactively through the demo
##
resource "azapi_resource" "profile_nsp_storage_demo2" {
  depends_on = [
    azapi_resource.nsp_demo2
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pfstorage"
  location  = var.location
  parent_id = azapi_resource.nsp_demo2.id
  tags      = var.tags
}

## Create a profile that the Key Vault will be associated to
##
resource "azapi_resource" "profile_nsp_key_vault_demo2" {
  depends_on = [
    azapi_resource.nsp_demo2
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pfkeyvault"
  location  = var.location
  parent_id = azapi_resource.nsp_demo2.id
  tags      = var.tags
}

## Associate the Key Vault instance to the profile to block all access to the Key Vault
##
resource "azapi_resource" "assoc_key_vault_demo2" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_demo2
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "asrkeyvault"
  location                  = var.location
  parent_id                 = azapi_resource.nsp_demo2.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = module.key_vault_demo2.id
      }
      profile = {
        id = azapi_resource.profile_nsp_key_vault_demo2.id
      }
    }
    tags = var.tags
  }

}

## Create an access rule allowing the machine deploying the Terraform continued access to the Key Vault
##
resource "azapi_resource" "access_rule_key_vault_demo2" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_demo2
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "acrkeyvault"
  location                  = var.location
  parent_id                 = azapi_resource.profile_nsp_key_vault_demo2.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        "${var.trusted_ip}/32"
      ]
    }
    tags = var.tags
  }

}

##### Create the Network Security Perimeter resources for Demo 3
#####

## Create Network Security Perimeter that will be used for the AI Search and Azure Storage resources
##
resource "azapi_resource" "nsp_demo3" {
  depends_on = [
    azurerm_resource_group.rg_work
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters@2024-07-01"
  name      = "nspdemo3${local.location_code}${random_string.unique.result}"
  location  = var.location
  parent_id = azurerm_resource_group.rg_work.id
  tags      = var.tags
}

## Create diagnostic settings for Network Security Perimeter
##
resource "azurerm_monitor_diagnostic_setting" "diag_nsp_demo3" {
  depends_on = [
    azapi_resource.nsp_demo3
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.nsp_demo3.id
  log_analytics_workspace_id = module.log_analytics_workspace.id

  enabled_log {
    category = "NspPublicInboundPerimeterRulesAllowed"
  }

  enabled_log {
    category = "NspPublicInboundPerimeterRulesDenied"
  }

  enabled_log {
    category = "NspPublicOutboundPerimeterRulesAllowed"
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

## Create a profile in the Network Security Perimeter that will be associated to the AI Search instance
## The AI Search instance will be associated interactively through the demo
##
resource "azapi_resource" "profile_nsp_ai_search_demo3" {
  depends_on = [
    azapi_resource.nsp_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pfaisearch"
  location  = var.location
  parent_id = azapi_resource.nsp_demo3.id
  tags      = var.tags
}

## Create an access rule allowing the AI Search instance added to the profile as part of the demo
## to communicate with the OpenAI models
resource "azapi_resource" "access_rule_ai_search_openai" {
  depends_on = [
    azapi_resource.profile_nsp_ai_search_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name      = "acropenai"
  location  = var.location
  parent_id = azapi_resource.profile_nsp_ai_search_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Outbound"
      fullyQualifiedDomainNames = [
        "${module.openai.name}.openai.azure.com"
      ]

    }
    tags = var.tags
  }

}

## Create a profile in the Network Security Perimeter that will be associated to the Storage Account
##
resource "azapi_resource" "profile_nsp_storage_demo3" {
  depends_on = [
    azapi_resource.nsp_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pfstorage"
  location  = var.location
  parent_id = azapi_resource.nsp_demo3.id
  tags      = var.tags
}

## Associate the Storage Account to the profile
##
resource "azapi_resource" "assoc_storage_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_storage_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name      = "asrstorage"
  location  = var.location
  parent_id = azapi_resource.nsp_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = module.storage_account_ai_search_data_demo3.id
      }
      profile = {
        id = azapi_resource.profile_nsp_storage_demo3.id
      }
    }
    tags = var.tags
  }

}

## Create an access rule allowing the machine deploying the Terraform continued access
## to blob storage for deployments
resource "azapi_resource" "access_rule_blob_storage_public_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_storage_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name      = "acrblobstorage"
  location  = var.location
  parent_id = azapi_resource.profile_nsp_storage_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        "${var.trusted_ip}/32"
      ]
    }
    tags = var.tags
  }

}
