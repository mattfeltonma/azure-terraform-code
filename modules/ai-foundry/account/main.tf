########## Create an Azure Key Vault instance and a key if customer-managed key encryption is specified
##########

## Create the Azure Key Vault instance which will be used to store the key to support CMK encryption of the AI Foundry account
## Allow an IP exception for the machine deploying the Terraform code to support redeployment
module "key_vault_aifoundry_cmk" {
  count = var.encryption == "cmk" ? 1 : 0

  source              = "../../key-vault"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  purpose             = var.purpose
  tags                = var.tags

  # Resource logs for the Key Vault will be sent to this Log Analytics Workspace
  law_resource_id = var.log_analytics_workspace_id

  # Enable RBAC authorization on the Key Vault
  rbac_enabled = true

  # The user specified here will have the Azure RBAC Key Vault Administrator role over the Azure Key Vault instance
  kv_admin_object_id = var.user_object_id

  # Disable public access and allow the Trusted Azure Service firewall exception
  firewall_default_action = "Deny"
  firewall_bypass         = "AzureServices"

  # Enable purge protection and soft delete to support the usage of CMK
  purge_protection           = true
  soft_delete_retention_days = 7

  # Allow the trusted IP where the Terraform is being deployed from access to the vault. Only necessary for my 
  firewall_ip_rules = [
    var.trusted_ip
  ]
}

## Create the CMK used to encrypt the Azure Foundry account
##

resource "azurerm_key_vault_key" "key_cmk_foundry" {
  count = var.encryption == "cmk" ? 1 : 0

  depends_on = [
    module.key_vault_aifoundry_cmk
  ]

  name         = "cmk-foundry"
  key_vault_id = module.key_vault_aifoundry_cmk[0].id
  key_type     = "RSA"

  # Key size is limited to 2048 as of 8/6/2025
  key_size = 2048
  key_opts = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
}

########## Create the user-assigned managed identity for the AI Foundry account
########## This section is only executed if the user specifies that a user-assigned managed identity should be created
########## via the managed_identity variable

## Create the user-assigned managed identity for the AI Foundry account
##
resource "azurerm_user_assigned_identity" "umi_foundry" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    module.key_vault_aifoundry_cmk,
    azurerm_key_vault_key.key_cmk_foundry
  ]

  name                = "${local.umi_prefix}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

## Pause for 10 seconds to allow the managed identity that was created to be replicated
##
resource "time_sleep" "wait_umi_foundry_creation" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_foundry
  ]
  create_duration = "10s"
}

## Create an Azure RBAC role assignment for the Key Vault Crypto User role on the Key Vault used for the CMK
## assigned to the AI Foundry account user-assigned managed identity
## Note this is not yet supported as of August 5th 2025
resource "azurerm_role_assignment" "umi_foundry_kv_cryto_user" {
  count = local.cmk_umi == true ? 1 : 0

  depends_on = [
    time_sleep.wait_umi_foundry_creation
  ]

  name                 = uuidv5("dns", "${var.resource_group_name}${module.key_vault_aifoundry_cmk[0].name}${azurerm_user_assigned_identity.umi_foundry[0].name}kvcryptouser")
  scope                = module.key_vault_aifoundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.umi_foundry[0].principal_id
}

## Pause for 120 seconds to allow the role assignments to be replicated
##
resource "time_sleep" "wait_umi_role_assignments" {
  count = local.cmk_umi == true ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_foundry_kv_cryto_user
  ]
  create_duration = "120s"
}

########## Create AI Foundry account with support for VNet injection
##########

## Create the Azure Foundry account
##
resource "azapi_resource" "ai_foundry_account" {
  depends_on = [
    module.key_vault_aifoundry_cmk,
    azurerm_key_vault_key.key_cmk_foundry,
    time_sleep.wait_umi_role_assignments
  ]

  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = "aif${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    kind = "AIServices",
    sku = {
      name = "S0"
    }

    # Assign a user-assigned managed identity or system-assigned managed identity based on the variable specified
    identity = var.managed_identity == "user_assigned" ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.umi_foundry[0].id) = {}
      }
      } : {
      type = "SystemAssigned"
    }

    properties = {

      # Specifies that this is an AI Foundry resource which will support AI Foundry projects
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = "aif${var.purpose}${var.location_code}${var.random_string}"

      # Set encryption settings based on whether PMK or CMK is specified
      encryption = local.cmk_umi == true ? {
        keySource = "Microsoft.KeyVault"
        keyVaultProperties = {
          keyName          = azurerm_key_vault_key.key_cmk_foundry[0].name
          keyVersion       = azurerm_key_vault_key.key_cmk_foundry[0].version
          keyVaultUri      = module.key_vault_aifoundry_cmk[0].vault_uri
          identityClientId = azurerm_user_assigned_identity.umi_foundry[0].client_id
        }
      } : null

      # Network-related controls
      # Disable public access but allow Trusted Azure Services exception
      publicNetworkAccess = var.public_network_access
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = var.network_default_action
      }

      # Enable VNet injection for Standard Agents
      networkInjections = var.subnet_id_agent != null ? [
        {
          scenario                   = "agent"
          subnetArmId                = var.subnet_id_agent
          useMicrosoftManagedNetwork = false
        }
      ] : null
    }
    tags = var.tags
  }

  response_export_values = [
    "identity.principalId",
    "properties.customSubDomainName"
  ]

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create an Azure RBAC role assignment for the Key Vault Crypto User role on the Key Vault used for the CMK
## assigned to the AI Foundry account system-assigned managed identity
resource "azurerm_role_assignment" "smi_foundry_kv_cryto_user" {
  count = local.cmk_smi == true ? 1 : 0

  depends_on = [
    azapi_resource.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${var.resource_group_name}${module.key_vault_aifoundry_cmk[0].name}${azapi_resource.ai_foundry_account.name}kvcryptouser")
  scope                = module.key_vault_aifoundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azapi_resource.ai_foundry_account.output.identity.principalId
}

## Wait 120 seconds for the Azure RBAC role assignments to replicate
##
resource "time_sleep" "wait_smi_role_assignments" {
  count = local.cmk_umi == true ? 1 : 0

  depends_on = [
    azurerm_role_assignment.smi_foundry_kv_cryto_user
  ]
  create_duration = "120s"
}

## Modify the Azure AI Foundry account to use a CMK if CMK is specified and a system-assigned managed identity is being used
##
resource "azurerm_cognitive_account_customer_managed_key" "ai_foundry_cmk" {
  count = local.cmk_smi == true ? 1 : 0

  depends_on = [
    time_sleep.wait_smi_role_assignments
  ]

  cognitive_account_id = azapi_resource.ai_foundry_account.id
  key_vault_key_id     = azurerm_key_vault_key.key_cmk_foundry[0].id
}

# Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "openai_deployment_gpt_4_1" {
  depends_on = [
    azapi_resource.ai_foundry_account,
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azapi_resource.ai_foundry_account.id

  sku {
    name     = "DataZoneStandard"
    capacity = 100
  }

  model {
    format = "OpenAI"
    name   = "gpt-4o"
  }
}

## Create a deployment for the text-embedding-3-large embededing model
##
resource "azurerm_cognitive_deployment" "openai_deployment_text_embedding_3_large" {
  depends_on = [
    azurerm_cognitive_deployment.openai_deployment_gpt_4_1
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azapi_resource.ai_foundry_account.id

  sku {
    name     = "Standard"
    capacity = 50
  }

  model {
    format = "OpenAI"
    name   = "text-embedding-3-large"
  }
}

## Create diagnostic settings for AI Foundry resource
##
resource "azurerm_monitor_diagnostic_setting" "diag_foundry_resource" {
  depends_on = [
    azapi_resource.ai_foundry_account
  ]

  name                       = "diag"
  target_resource_id         = azapi_resource.ai_foundry_account.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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

## Create Private Endpoint for AI Foundry account
##
module "private_endpoint_ai_foundry" {
  count = var.private_endpoint ? 1 : 0

  depends_on = [
    azapi_resource.ai_foundry_account,
    azurerm_cognitive_deployment.openai_deployment_gpt_4_1,
    azurerm_cognitive_deployment.openai_deployment_text_embedding_3_large
  ]

  source              = "../../private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  resource_name    = azapi_resource.ai_foundry_account.name
  resource_id      = azapi_resource.ai_foundry_account.id
  subresource_name = "account"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
  ]
}

##########  Create resources required by the AI Foundry resource to support Standard Agents with Virtual Network Injection
##########

## Create Cosmos DB account to store agent threads.
## DB account will support DocumentDB API and will have diagnostic settings enabled
## Deployed to one region with no failover to reduce costs
module "cosmos_db" {
  count = var.subnet_id_agent != null ? 1 : 0

  source              = "../../cosmosdb"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Resource logs for the Cosmos DB instance will be sent to this Log Analytics Workspace
  law_resource_id = var.log_analytics_workspace_id

  # Disable public access and block local authentication
  public_network_access_enabled = false
  local_authentication_disabled = true
}

## Create an Azure AI Search instance that will be used to store indexes and vector embeddings. 
## The instance will have public network access disabled
module "ai_search" {
  count = var.subnet_id_agent != null ? 1 : 0

  source              = "../../ai-search"
  purpose             = var.purpose
  random_string       = var.random_string
  resource_group_name = var.resource_group_name
  resource_group_id   = var.resource_group_id
  location            = var.location
  location_code       = var.location_code
  tags                = var.tags

  # Resource logs for the service will be sent to this Log Analytics Workspace
  law_resource_id = var.log_analytics_workspace_id

  # Use Standard SKU to allow for more features around private networking
  sku = "standard"

  # Disable public network access and restrict to Private Endpoints and allow trusted Azure services
  public_network_access   = "disabled"
  trusted_services_bypass = "AzureServices"
}

## Create Azure Storage Account to store files uploaded to AI Foundry projects and files generated by AI agents
##
module "storage_account" {
  count = var.subnet_id_agent != null ? 1 : 0

  source              = "../../storage-account"
  purpose             = "${var.purpose}default"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Use LRS replication to minimize costs
  storage_account_replication_type = "LRS"

  # Resource logs for the storage account will be sent to this Log Analytics Workspace
  law_resource_id = var.log_analytics_workspace_id

  # Disable storage access keys
  key_based_authentication = false

  # Disable public network access and restrict to Private Endpoints allow for trusted services bypass
  network_access_default = "Deny"
  network_trusted_services_bypass = [
    "AzureServices",
    "Metrics",
    "Logging"
  ]
}

########## Create optional resources to support the AI Foundry resource and Standard Agents
##########

## Create Application Insights instance
##
resource "azurerm_application_insights" "appins" {
  count = var.subnet_id_agent != null ? 1 : 0

  name                = "appinsaif${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.log_analytics_workspace_id
  application_type    = "other"
}

## Create Grounding Search with Bing
##
resource "azapi_resource" "bing_grounding_search" {
  count = var.subnet_id_agent != null ? 1 : 0

  type                      = "Microsoft.Bing/accounts@2020-06-10"
  name                      = "bingaif${var.location_code}${var.random_string}"
  parent_id                 = var.resource_group_id
  location                  = "global"
  schema_validation_enabled = false

  body = {
    sku = {
      name = "G1"
    }
    kind = "Bing.Grounding"
  }
}

########## Create Private Endpoints for BYO Standard Agent resources
##########

## Create Private Endpoint for CosmosDB
##
module "private_endpoint_cosmos_db" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    module.cosmos_db
  ]

  source              = "../../private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  resource_name    = module.cosmos_db[0].name
  resource_id      = module.cosmos_db[0].id
  subresource_name = "Sql"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
  ]
}

## Create Private Endpoint for AI Search
##
module "private_endpoint_ai_search" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    module.ai_search
  ]

  source              = "../../private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  resource_name    = module.ai_search[0].name
  resource_id      = module.ai_search[0].id
  subresource_name = "searchService"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
  ]
}

## Create Private Endpoint for Storage Account for blob endpoint
##
module "private_endpoint_storage_account" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    module.storage_account
  ]

  source              = "../../private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  resource_name    = module.storage_account[0].name
  resource_id      = module.storage_account[0].id
  subresource_name = "blob"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}

## Pause for 60 seconds to allow creation of Application Insights resource to replicate
## Application Insight instances created and integrated with Log Analytics can take time to replicate the resource
resource "time_sleep" "wait_appins" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    azurerm_application_insights.appins
  ]
  create_duration = "60s"
}

########## Create AI Foundry Project, connections to CosmosDB, AI Search, Storage Account, Grounding Search with Bing, and Application Insights
##########

## Create AI Foundry project using a moudule that creates the project, project connections, capabilities hosts, and Azure RBAC role assignments
##
module "ai_foundry_project_sample" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    azapi_resource.ai_foundry_account,
    module.private_endpoint_ai_foundry,
    module.private_endpoint_cosmos_db,
    module.private_endpoint_ai_search,
    module.private_endpoint_storage_account,
    time_sleep.wait_appins,
    azapi_resource.bing_grounding_search,
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk
  ]

  source                = "../project"
  resource_group_id     = azapi_resource.ai_foundry_account.parent_id
  resource_group_name   = provider::azapi::parse_resource_id("Microsoft.CognitiveServices/accounts", azapi_resource.ai_foundry_account.id).resource_group_name
  ai_foundry_account_id = azapi_resource.ai_foundry_account.id
  location              = var.location

  # Project name and description
  project_name        = "sample_project1"
  project_description = "This is a sample AI Foundry project"

  # Project connected resources
  cosmosdb_name              = module.cosmos_db[0].name
  cosmosdb_resource_id       = module.cosmos_db[0].id
  cosmosdb_document_endpoint = module.cosmos_db[0].endpoint

  aisearch_name        = module.ai_search[0].name
  aisearch_resource_id = module.ai_search[0].id

  storage_account_blob_endpoint = module.storage_account[0].endpoint_blob
  storage_account_name          = module.storage_account[0].name
  storage_account_resource_id   = module.storage_account[0].id

  application_insights_connection_string = azurerm_application_insights.appins[0].connection_string
  application_insights_name              = azurerm_application_insights.appins[0].name
  application_insights_resource_id       = azurerm_application_insights.appins[0].id

  bing_grounding_search_name             = azapi_resource.bing_grounding_search[0].name
  bing_grounding_search_resource_id      = azapi_resource.bing_grounding_search[0].id
  bing_grounding_search_subscription_key = data.azapi_resource_action.bing_api_keys[0].output.key1
}

## Added AI Foundry account purger to avoid running into InUseSubnetCannotBeDeleted-lock caused by the agent subnet delegation.
## The azapi_resource_action.purge_ai_foundry (only gets executed during destroy) purges the AI foundry account removing /subnets/snet-agent/serviceAssociationLinks/legionservicelink so the agent subnet can get properly removed.
## Credit for this to Sebastian Graf
resource "azapi_resource_action" "purge_ai_foundry" {
  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.location}/resourceGroups/${var.resource_group_name}/deletedAccounts/aifoundry${var.random_string}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"
}
