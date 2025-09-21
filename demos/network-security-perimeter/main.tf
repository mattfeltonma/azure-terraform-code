#################### Create core resources
####################

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
  location = var.region
  tags     = var.tags
}

#################### Create resources used for logging
####################

## Create a Log Analytics Workspace for resources to centrally log to
##
resource "azurerm_log_analytics_workspace" "law" {
  name                = "lawnsp${local.region_code}${random_string.unique.result}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

## Create a storage account to store VNet flow logs for each environment
##
resource "azurerm_storage_account" "storage_account_flow_log" {
  name                = "stflowlognsp${local.region_code}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = var.region
  tags                = var.tags

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
    ip_rules = [var.trusted_ip]
  }
}

## Configure diagnostic settings for blob and table endpoints for the storage accounts
##
resource "azurerm_monitor_diagnostic_setting" "diag_blob" {
  depends_on = [
    azurerm_storage_account.storage_account_flow_log
  ]

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.storage_account_flow_log.id}/blobServices/default"
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
    azurerm_storage_account.storage_account_flow_log,
    azurerm_monitor_diagnostic_setting.diag_blob
  ]

  name                       = "diag-table"
  target_resource_id         = "${azurerm_storage_account.storage_account_flow_log.id}/tableServices/default"
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

#################### Create infrastructure
####################
module "infrastructure" {
  source = "./modules/infrastructure"

  region                              = var.region
  region_code                         = local.region_code
  random_string                       = random_string.unique.result
  resource_group_name_workload        = azurerm_resource_group.rg_work.name
  resource_group_name_network_watcher = var.network_watcher_resource_group_name
  address_space_vnet                  = [var.address_space_vnet]
  vm_admin_username                   = var.vm_admin_username
  vm_admin_password                   = var.vm_admin_password
  vm_sku_size                         = var.sku_vm_size
  storage_account_vnet_flow_logs      = azurerm_storage_account.storage_account_flow_log.id
  law_workspace_id                    = azurerm_log_analytics_workspace.law.id
  law_region                          = var.region
  law_resource_id                     = azurerm_log_analytics_workspace.law.id
  tags                                = var.tags
}

#################### Create demos
####################

########## Demo 1
########## Create two Key Vault instances with one allowing public network access and allowing
########## access only through a Private Endpoint.

##### Create publicly accessible Key Vault
#####

## Create Key Vault which will host a secret and be accessible via public endpoint
##
resource "azurerm_key_vault" "key_vault_public_demo1" {
  name                = "kvnsppubdemo1${local.region_code}${random_string.unique.result}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name

  sku_name  = "Premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  enable_rbac_authorization       = true

  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Allow"
    bypass         = null
    ip_rules       = []
  }
  tags = var.tags
}

## Assign user Key Vault Administrator permissions on Key Vault instance
##
resource "azurerm_role_assignment" "role_assignment_key_vault_public_kv_admin_user_demo1" {
  depends_on = [ 
    azurerm_key_vault.key_vault_public_demo1
  ]
  name                 = uuidv5("dns", "${azurerm_key_vault.key_vault_public_demo1.name}${var.object_id_user}")
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.key_vault_public_demo1.name}"
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.object_id_user
}

## Create diagnostic settings for Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_public_demo1" {
  depends_on = [ 
    azurerm_key_vault.key_vault_public_demo1,
    azurerm_role_assignment.role_assignment_key_vault_public_kv_admin_user_demo1
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_key_vault.key_vault_public_demo1.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

## Add a secret to the Key Vault that supports public network access
##
resource "azurerm_key_vault_secret" "secret_public_demo1" {
  depends_on = [
    azurerm_key_vault.key_vault_public_demo1
  ]
  name         = "secret-public-word"
  value        = "banana"
  key_vault_id = azurerm_key_vault.key_vault_public_demo1.id
}

## Create role assignment granting Key Vault Secrets User to virtual machine
## user-assigned managed identity
resource "azurerm_role_assignment" "umi_vm_key_vault_public_secret_demo1" {
  depends_on = [
    module.infrastructure
  ]

  scope                = azurerm_key_vault.key_vault_public_demo1.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.infrastructure.vm_managed_identity
}

## Create Private Endpoint for public Key Vault
##
resource "azurerm_private_endpoint" "pe_key_vault_public_demo1" {
  name                = "pe${azurerm_key_vault.key_vault_public_demo1.name}vaults"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  subnet_id           = module.infrastructure.subnet_svc_id

  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_public_demo1.name}vaults"

  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_public_demo1.name}vaults"
    private_connection_resource_id = azurerm_key_vault.key_vault_public_demo1.id
    subresource_names = ["vaults"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azurerm_key_vault.key_vault_public_demo1.name}"
    private_dns_zone_ids = ["${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
  }

  tags = var.tags
}

##### Create privately accessible Key Vault
#####

## Create Key Vault which will host a secret and be accessible only via a Private Endpoint
## Add an IP-based exception for the machine deploying the Terraform code to support re-deployments
resource "azurerm_key_vault" "key_vault_private_demo1" {
  name                = "kvnsppridemo1${local.region_code}${random_string.unique.result}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name

  sku_name  = "Premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  enable_rbac_authorization       = true

  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Deny"
    bypass         = null
    ip_rules       = [var.trusted_ip]
  }
  tags = var.tags
}

## Assign user Key Vault Administrator permissions on Key Vault instance
##
resource "azurerm_role_assignment" "role_assignment_key_vault_private_kv_admin_user_demo1" {
  depends_on = [ 
    azurerm_key_vault.key_vault_private_demo1
  ]
  name                 = uuidv5("dns", "${azurerm_key_vault.key_vault_private_demo1.name}${var.object_id_user}")
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.key_vault_private_demo1.name}"
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.object_id_user
}

## Create diagnostic settings for Key Vault
##
resource "azurerm_monitor_diagnostic_setting" "diag_key_vault_private_demo1" {
  depends_on = [ 
    azurerm_key_vault.key_vault_private_demo1,
    azurerm_role_assignment.role_assignment_key_vault_private_kv_admin_user_demo1
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_key_vault.key_vault_private_demo1.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
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

## Create role assignment granting Key Vault Secrets User to virtual machine
## user-assigned managed identity
resource "azurerm_role_assignment" "umi_vm_key_vault_private_secret_demo1" {
  depends_on = [
    module.infrastructure
  ]

  scope                = azurerm_key_vault.key_vault_private_demo1.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.infrastructure.vm_managed_identity
}

## Create Private Endpoint for private Key Vault
##
resource "azurerm_private_endpoint" "pe_key_vault_private_demo1" {
  name                = "pe${azurerm_key_vault.key_vault_private_demo1.name}vaults"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  subnet_id           = module.infrastructure.subnet_svc_id

  custom_network_interface_name = "nic${azurerm_key_vault.key_vault_private_demo1.name}vaults"

  private_service_connection {
    name                           = "peconn${azurerm_key_vault.key_vault_private_demo1.name}vaults"
    private_connection_resource_id = azurerm_key_vault.key_vault_private_demo1.id
    subresource_names = ["vaults"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azurerm_key_vault.key_vault_private_demo1.name}"
    private_dns_zone_ids = ["${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
  }

  tags = var.tags
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
resource "azurerm_key_vault" "key_vault_demo2" {
  name                = "kvnspdemo2${local.region_code}${random_string.unique.result}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name

  sku_name  = "Premium"
  tenant_id = data.azurerm_subscription.current.tenant_id

  enable_rbac_authorization       = true

  soft_delete_retention_days  = 7
  purge_protection_enabled    = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = [var.trusted_ip]
  }
  tags = var.tags
}

## Add a key to be used for the storage account CMK
##
resource "azurerm_key_vault_key" "storage_key_demo2" {
  depends_on = [
    azurerm_key_vault.key_vault_demo2
  ]
  name         = "storage"
  key_vault_id = azurerm_key_vault.key_vault_demo2.id 
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
resource "azurerm_user_assigned_identity" "umi_storage_account_demo2" {
  location            = var.region
  name                = "umistnsp${local.region_code}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_work.name

  tags = var.tags
}

## Pause for 10 seconds to allow RBAC assignments to propagate
##
resource "time_sleep" "wait_umi_creation_storage_demo2" {
  depends_on = [
    azurerm_user_assigned_identity.umi_storage_account_demo2
  ]

  create_duration = "10s"
}

## Add role assignments to allow the storage account to retrieve the CMK from the Key Vault
##
resource "azurerm_role_assignment" "umi_storage_cmk_demo2" {
  depends_on = [
    azurerm_user_assigned_identity.umi_storage_account_demo2,
    azurerm_key_vault.key_vault_demo2,
    time_sleep.wait_umi_creation_storage_demo2
  ]

  scope                = azurerm_key_vault.key_vault_demo2.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.umi_storage_account_demo2.principal_id
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
  name                = "stnspdemo2${local.region_code}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = var.region
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
}

########## Demo 3 
########## Create an Azure AI Search and Azure Storage instance to demonstrate import and vectorize
########## 

## Create an Azure AI Search instance that will be used to demonstrate integration with the storage account
##
resource "azapi_resource" "ai_search_demo3" {
  type                      = "Microsoft.Search/searchServices@2024-03-01-preview"
  name                      = "aisnsp${local.region_code}${random_string.unique.result}"
  parent_id                 = azurerm_resource_group.rg_work.id
  location                  = var.region
  schema_validation_enabled = true

  body = {
    sku = {
      name = "standard"
    }

    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # Search-specific properties
      replicaCount = 1
      partitionCount = 1
      hostingMode = "default"
      semanticSearch = "standard"

      # Identity-related controls
      disableLocalAuth = false
      authOptions = {
        aadOrApiKey = {
                aadAuthFailureMode = "http401WithBearerChallenge"
        }
      }
      # Networking-related controls
      publicNetworkAccess = "disabled"
      networkRuleSet = {
        bypass = "AzureServices"
        ipRules = [var.trusted_ip]
      }
    }
    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]
}

## Create diagnostic settings for the Azure AI Search service
##
resource "azurerm_monitor_diagnostic_setting" "diag_base_aisearch_demo3" {
  depends_on = [
    azapi_resource.ai_search_demo3
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.ai_search_demo3.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "OperationLogs"
  }
}

## Create a Private Endpoint for the AI Search instance
##
resource "azurerm_private_endpoint" "pe_ai_search_demo3" {
  name                = "pe${azapi_resource.ai_search_demo3.name}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  subnet_id           = module.infrastructure.subnet_svc_id

  custom_network_interface_name = "nic${azapi_resource.ai_search_demo3.name}"

  private_service_connection {
    name                           = "peconn${azapi_resource.ai_search_demo3.name}"
    private_connection_resource_id = azapi_resource.ai_search_demo3.id
    subresource_names = ["searchServices"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azapi_resource.ai_search_demo3.name}"
    private_dns_zone_ids = ["${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.search.azure.net"]
  }

  tags = var.tags
}

## Create an Azure OpenAI instance
##
resource "azapi_resource" "ai_foundry_account_demo3" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = "aifnsp${local.region_code}${random_string.unique.result}"
  parent_id                 = azurerm_resource_group.rg_work.id
  location                  = var.region
  schema_validation_enabled = false

  body = {
    kind = "AIServices",
    sku = {
      name = "S0"
    }

    # Assign a system-assigned managed identity
    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # Specifies that this is an AI Foundry resource which will support AI Foundry projects
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = "aifnsp${local.region_code}${random_string.unique.result}"

      # Network-related controls
      # Disable public access but allow Trusted Azure Services exception
      publicNetworkAccess = "Disabled"
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
      }
    }
    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]
}

## Enable diagnostic settings for AI Foundry account
##
resource "azurerm_monitor_diagnostic_setting" "diag_foundry_resource_demo3" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]

  name                       = "diag"
  target_resource_id         = azapi_resource.ai_foundry_account_demo3.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "AzureOpenAIRequestUsage"
  }

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Trace"
  }
}

## Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "openai_deployment_gpt_4_1_demo3" {
  depends_on = [
    azapi_resource.ai_foundry_account_demo3,
    azurerm_monitor_diagnostic_setting.diag_foundry_resource_demo3
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azapi_resource.ai_foundry_account_demo3.id

  sku {
    name     = "Standard"
    capacity = 10
  }

  model {
    format = "OpenAI"
    name   = "gpt-4o"
  }
}

## Create a deployment for the text-embedding-3-large embededing model
##
resource "azurerm_cognitive_deployment" "openai_deployment_text_embedding_3_large_demo3" {
  depends_on = [
    azurerm_cognitive_deployment.openai_deployment_gpt_4_1_demo3
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azapi_resource.ai_foundry_account_demo3.id

  sku {
    name     = "Standard"
    capacity = 50
  }

  model {
    format = "OpenAI"
    name   = "text-embedding-3-large"
  }
}

## Create Private Endpoint for AI Foundry account
##
resource "azurerm_private_endpoint" "pe_foundry_demo3" {
  depends_on = [ 
    module.infrastructure,
    azapi_resource.ai_foundry_account_demo3
   ]

  name                = "pe${azapi_resource.ai_foundry_account_demo3.name}accounts"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  subnet_id           = module.infrastructure.subnet_svc_id

  custom_network_interface_name = "nic${azapi_resource.ai_foundry_account_demo3.name}accounts"

  private_service_connection {
    name                           = "peconn${azapi_resource.ai_foundry_account_demo3.name}accounts"
    private_connection_resource_id = azapi_resource.ai_foundry_account_demo3.id
    subresource_names = ["accounts"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azapi_resource.ai_foundry_account_demo3.name}"
    private_dns_zone_ids = [
      "${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    ]
  }

  tags = var.tags
}

## Create a storage account that will store a file consumed by AI Search
##`
resource "azurerm_storage_account" "storage_account_ai_search_data_demo3" {
  name                = "stnspdemo3ais${local.region_code}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = var.region
  tags                = var.tags

  # Configure basic storage config settings
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable storage access key
  shared_access_key_enabled = false

  # Block any public access of blobs
  allow_nested_items_to_be_public = false

  # Block all public network access but allow trusted Azure services
  network_rules {
    default_action = "Deny"
    ip_rules       = [var.trusted_ip]
    bypass = [ "AzureServices"  ]
  }
}

## Create a Private Endpoint for the blob endpoint for the Storage Account where AI Search will pull its data from
##
resource "azurerm_private_endpoint" "pe_storage_account_demo3" {
  depends_on = [ 
    module.infrastructure,
    azurerm_storage_account.storage_account_ai_search_data_demo3
   ]

  name                = "pe${azurerm_storage_account.storage_account_ai_search_data_demo3.name}blob"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_work.name
  subnet_id           = module.infrastructure.subnet_svc_id

  custom_network_interface_name = "nic${azurerm_storage_account.storage_account_ai_search_data_demo3.name}blob"

  private_service_connection {
    name                           = "peconn${azurerm_storage_account.storage_account_ai_search_data_demo3.name}blob"
    private_connection_resource_id = azurerm_storage_account.storage_account_ai_search_data_demo3.id
    subresource_names = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "zoneconn${azurerm_storage_account.storage_account_ai_search_data_demo3.name}"
    private_dns_zone_ids = [
      "${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.rg_work.name}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  tags = var.tags
}

## Create a blob container in the storage account named data where file will be uploaded
##
resource "azurerm_storage_container" "blob_data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.storage_account_ai_search_data_demo3.id
  container_access_type = "private"
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
  name      = "nspdemo1${local.region_code}${random_string.unique.result}"
  location  = var.region
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
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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
##
resource "azapi_resource" "profile_nsp_private_key_vault_demo1" {
  depends_on = [
    azapi_resource.nsp_demo1
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pprivatekeyvault"
  location  = var.region
  parent_id = azapi_resource.nsp_demo1.id
  tags      = var.tags
}

## Create a profile of which the Key Vault with public network access restricted to an IP address will be added
##
resource "azapi_resource" "profile_nsp_public_key_vault_demo1" {
  depends_on = [
    azapi_resource.nsp_demo1
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "ppublickeyvault"
  location  = var.region
  parent_id = azapi_resource.nsp_demo1.id
  tags      = var.tags
}

## Create a profile of which the Log Analytics Workspace will be added with unrestricted network access
##
resource "azapi_resource" "profile_nsp_log_analytics_demo1" {
  depends_on = [
    azapi_resource.nsp_demo1
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "ploganalytics"
  location  = var.region
  parent_id = azapi_resource.nsp_demo1.id
  tags      = var.tags
}

## Associate the Key Vault with access restricted to a Private Endpoint to the profile
##
resource "azapi_resource" "assoc_key_vault_private_demo1" {
  depends_on = [
    azapi_resource.profile_nsp_private_key_vault_demo1,
    azurerm_key_vault_secret.secret_private_demo1
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raprivatekeyvault"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo1.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = module.key_vault_private_secret_demo1.id
      }
      profile = {
        id = azapi_resource.profile_nsp_private_key_vault_demo1.id
      }
    }
    tags = var.tags
  }

}

## Create an access rule under the public profile restricting public network access to a trusted IP
##
resource "azapi_resource" "access_rule_public_key_vault_demo1" {
  depends_on = [
    azapi_resource.profile_nsp_public_key_vault_demo1
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arkeyvault"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_public_key_vault_demo1.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        "${[var.trusted_ips[0]]}/32"
      ]
    }
    tags = var.tags
  }
}

## Associate the Log Analytics Workspace with unrestricted network access to the profile
##
resource "azapi_resource" "assoc_log_analytics_demo1" {
  depends_on = [
    azapi_resource.profile_nsp_log_analytics_demo1,
    azurerm_log_analytics_workspace.law
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raloganalytics"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo1.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Learning"
      resource = {
        id = azurerm_log_analytics_workspace.law.id
      }
      profile = {
        id = azapi_resource.profile_nsp_log_analytics_demo1.id
      }
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
  name      = "nspdemo2${local.region_code}${random_string.unique.result}"
  location  = var.region
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
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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
  name      = "pstorage"
  location  = var.region
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
  name      = "pkeyvault"
  location  = var.region
  parent_id = azapi_resource.nsp_demo2.id
  tags      = var.tags
}

## Create a profile of which the Log Analytics Workspace will be added with unrestricted network access
##
resource "azapi_resource" "profile_nsp_log_analytics_demo2" {
  depends_on = [
    azapi_resource.nsp_demo2
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "ploganalytics"
  location  = var.region
  parent_id = azapi_resource.nsp_demo2.id
  tags      = var.tags
}

## Associate the Key Vault instance to the profile to block all access to the Key Vault
##
resource "azapi_resource" "assoc_key_vault_demo2" {
  depends_on = [
    azapi_resource.profile_nsp_key_vault_demo2,
    azurerm_key_vault_key.storage_key_demo2
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rakeyvault"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo2.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azurerm_key_vault.storage_key_vault.id
      }
      profile = {
        id = azapi_resource.profile_nsp_key_vault_demo2.id
      }
    }
    tags = var.tags
  }

}

## Associate the Log Analytics Workspace with unrestricted network access to the profile
##
resource "azapi_resource" "assoc_log_analytics_demo2" {
  depends_on = [
    azapi_resource.profile_nsp_log_analytics_demo2,
    azurerm_log_analytics_workspace.law
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raloganalytics"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo2.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Learning"
      resource = {
        id = azurerm_log_analytics_workspace.law.id
      }
      profile = {
        id = azapi_resource.profile_nsp_log_analytics_demo2.id
      }
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
  name      = "nspdemo3${local.region_code}${random_string.unique.result}"
  location  = var.region
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

## Create a profile in the Network Security Perimeter that will be associated with the AI Search, Azure Storage, and Azure OpenAI resources
## The AI Search instance will be associated within the demo
resource "azapi_resource" "profile_nsp_all_ai_resources_demo3" {
  depends_on = [
    azapi_resource.nsp_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "pallresources"
  location  = var.region
  parent_id = azapi_resource.nsp_demo3.id
  tags      = var.tags
}

## Create a profile of which the Log Analytics Workspace will be added with unrestricted network access
##
resource "azapi_resource" "profile_nsp_log_analytics_demo3" {
  depends_on = [
    azapi_resource.nsp_demo3
  ]

  type      = "Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01"
  name      = "ploganalytics"
  location  = var.region
  parent_id = azapi_resource.nsp_demo3.id
  tags      = var.tags
}

## Create a resource association to associate the Azure OpenAI instance with the Network Security Perimeter profile
##
resource "azapi_resource" "assoc_foundry_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_all_ai_resources_demo3
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rafoundry"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Learning"
      privateLinkResource = {
        id = azapi_resource.foundry_demo3.id
      }
      profile = {
        id = azapi_resource.profile_nsp_all_ai_resources_demo3.id
      }
    }
    tags = var.tags
  }

}

## Create a resource association to associate the Storage Account with the Network Security Perimeter profile
##
resource "azapi_resource" "assoc_storage_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_all_resources_demo3
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "rastorage"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = module.storage_account_ai_search_data_demo3.id
      }
      profile = {
        id = azapi_resource.profile_nsp_all_resources_demo3.id
      }
    }
    tags = var.tags
  }

}

## Create a resource association to associate the AI Search instance with the Network Security Perimeter profile
##
resource "azapi_resource" "assoc_ai_search_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_all_ai_resources_demo3
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2024-07-01"
  name                      = "raaisearch"
  location                  = var.region
  parent_id                 = azapi_resource.nsp_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      accessMode = "Enforced"
      privateLinkResource = {
        id = azapi_resource.ai_search_demo3.id
      }
      profile = {
        id = azapi_resource.profile_nsp_all_ai_resources_demo3.id
      }
    }
    tags = var.tags
  }

}

## Create an access rule allowing the trusted IP to access the services over the public IPs
## 
resource "azapi_resource" "access_rule_trusted_ip_demo3" {
  depends_on = [
    azapi_resource.profile_nsp_all_ai_resources_demo3
  ]

  type                      = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"
  name                      = "arallresources"
  location                  = var.region
  parent_id                 = azapi_resource.profile_nsp_all_ai_resources_demo3.id
  schema_validation_enabled = false

  body = {
    properties = {
      direction = "Inbound"
      addressPrefixes = [
        "${var.trusted_ips[0]}/32"
      ]
    }
    tags = var.tags
  }
}
