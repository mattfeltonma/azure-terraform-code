########## Create resource group and Log Analytics Workspace
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_work" {

  name     = "rgaif${var.location_code}${var.random_string}"
  location = var.location

  tags = var.tags
}

## Create a Log Analytics Workspace that all resources specific to this workload will
## write configured resource logs and metrics to
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_work.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Configure diagnostic settings for Log Analytics Workspace
##
resource "azurerm_monitor_diagnostic_setting" "diag_log_analytics_workspace" {
  depends_on = [azurerm_log_analytics_workspace.log_analytics_workspace]

  name                       = "diag-base"
  target_resource_id         = azurerm_log_analytics_workspace.log_analytics_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "Audit"
  }
  enabled_log {
    category = "SummaryLogs"
  }
}

########## Create an Azure Key Vault instance and a key if customer-managed key encryption is specified
##########
##########

## Create the Azure Key Vault instance which will be used to store the key to support CMK encryption of the AI Foundry account
##
module "keyvault_aifoundry_cmk" {
  count = var.encryption == "cmk" ? 1 : 0

  source              = "../../modules/key-vault"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  purpose             = var.purpose
  tags                = var.tags

  # Resource logs for the Key Vault will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

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

  # Allow the trusted IP where the Terraform is being deployed from access to the vault
  firewall_ip_rules = [
    var.trusted_ip
  ]
}

## Create the CMK used to encrypt the Azure Foundry account
##
resource "azurerm_key_vault_key" "key_cmk_foundry" {
  count = var.encryption == "cmk" ? 1 : 0

  depends_on = [
    module.keyvault_aifoundry_cmk
  ]

  name         = "cmk-foundry"
  key_vault_id = module.keyvault_aifoundry_cmk[0].id
  key_type     = "RSA"

  key_size = 2048
  key_opts = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
}

########## Create the user-assigned managed identity for the AI Foundry account and the the necessary role assignments. 
########## This section is only executed if the user specifies that a user-assigned managed identity should be created
########## using the user_assigne_managed_identity variable

## Create the user-assigned managed identity for the AI Foundry account
##
resource "azurerm_user_assigned_identity" "umi_foundry" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_work,
    module.keyvault_aifoundry_cmk,
    azurerm_key_vault_key.key_cmk_foundry
  ]

  name                = "${local.umi_prefix}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_work.name
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

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${module.keyvault_aifoundry_cmk[0].name}${azurerm_user_assigned_identity.umi_foundry[0].name}kvcryptouser")
  scope                = module.keyvault_aifoundry_cmk[0].id
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
resource "azapi_resource" "ai_foundry_resource" {
  depends_on = [
    azurerm_resource_group.rg_work,
    module.keyvault_aifoundry_cmk,
    azurerm_key_vault_key.key_cmk_foundry,
    time_sleep.wait_umi_role_assignments
  ]

  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = "aif${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_work.id
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
          keyVaultUri      = module.keyvault_aifoundry_cmk[0].vault_uri
          identityClientId = azurerm_user_assigned_identity.umi_foundry[0].client_id
        }
      } : null

      # Network-related controls
      # Disable public access but allow Trusted Azure Services exception
      publicNetworkAccess = "Disabled"
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
      }

      # Enable VNet injection for Standard Agents
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = var.subnet_id_agent
          useMicrosoftManagedNetwork = false
        }
      ]
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
    azapi_resource.ai_foundry_resource
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${module.keyvault_aifoundry_cmk[0].name}${azapi_resource.ai_foundry_resource.name}kvcryptouser")
  scope                = module.keyvault_aifoundry_cmk[0].id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azapi_resource.ai_foundry_resource.output.identity.principalId
}

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

  cognitive_account_id = azapi_resource.ai_foundry_resource.id
  key_vault_key_id = azurerm_key_vault_key.key_cmk_foundry[0].id
}

# Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "openai_deployment_gpt_4o" {
  depends_on = [
    azapi_resource.ai_foundry_resource,
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azapi_resource.ai_foundry_resource.id

  sku {
    name     = "DataZoneStandard"
    capacity = 300
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
    azurerm_cognitive_deployment.openai_deployment_gpt_4o
  ]

  name                 = "text-embedding-3-large"
  cognitive_account_id = azapi_resource.ai_foundry_resource.id

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
    azapi_resource.ai_foundry_resource
  ]

  name                       = "diag"
  target_resource_id         = azapi_resource.ai_foundry_resource.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

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

#####  Create resources required by the AI Foundry resource to support Standard Agents with Virtual Network Injection
#####

## Setup delegation on the subnet that will be used for Standard Agent Vnet injection
## This command is only run the first time the template is deployed
##
resource "null_resource" "add-subnet-delegation" {
  provisioner "local-exec" {
    command = <<EOF
    az network vnet subnet update --ids ${var.subnet_id_agent} --delegation 'Microsoft.App/Environments'
    EOF
  }
}

## Create Cosmos DB account to store agent threads.
## DB account will support DocumentDB API and will have diagnostic settings enabled
## Deployed to one region with no failover to reduce costs
module "cosmos_db" {
  source              = "../../modules/cosmosdb"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  # Resource logs for the Cosmos DB instance will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  # Disable public access and block local authentication
  public_network_access_enabled = false
  local_authentication_disabled = true
}

## Create an Azure AI Search instance that will be used to store indexes and vector embeddings. 
## The instance will have public network access disabled
module "ai_search" {

  source              = "../../modules/ai-search"
  purpose             = var.purpose
  random_string       = var.random_string
  resource_group_name = azurerm_resource_group.rg_work.name
  resource_group_id   = azurerm_resource_group.rg_work.id
  location            = var.location
  location_code       = var.location_code
  tags                = var.tags

  # Resource logs for the service will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  # Use Standard SKU to allow for more features around private networking
  sku = "standard"

  # Disable public network access and restrict to Private Endpoints and allow trusted Azure services
  public_network_access   = "disabled"
  trusted_services_bypass = "AzureServices"

}

## Create Azure Storage Account to store files uploaded to AI Foundry projects and files generated by AI agents
##
module "storage_account_default" {
  source              = "../../modules/storage-account"
  purpose             = "${var.purpose}default"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  # Use LRS replication to minimize costs
  storage_account_replication_type = "LRS"

  # Resource logs for the storage account will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

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

##### Create optional resources to support the AI Foundry resource and Standard Agents
#####

## Create Application Insights instance
##
resource "azurerm_application_insights" "appins" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace
  ]
  name                = "appinsaif${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_work.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
  application_type    = "other"
}

## Create Grounding Search with Bing
##
resource "azapi_resource" "bing_grounding_search" {
  type                      = "Microsoft.Bing/accounts@2020-06-10"
  name                      = "bingaif${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_work.id
  location                  = "global"
  schema_validation_enabled = false

  body = {
    sku = {
      name = "G1"
    }
    kind = "Bing.Grounding"
  }
}

##### Create Private Endpoints for resources
#####

## Create Private Endpoint for AI Foundry resource
##
module "private_endpoint_ai_foundry" {
  depends_on = [
    azapi_resource.ai_foundry_resource,
    azurerm_cognitive_deployment.openai_deployment_gpt_4o,
    azurerm_cognitive_deployment.openai_deployment_text_embedding_3_large
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = azapi_resource.ai_foundry_resource.name
  resource_id      = azapi_resource.ai_foundry_resource.id
  subresource_name = "account"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
  ]
}

## Create Private Endpoint for CosmosDB
##
module "private_endpoint_cosmos_db" {
  depends_on = [
    module.cosmos_db
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.cosmos_db.name
  resource_id      = module.cosmos_db.id
  subresource_name = "Sql"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
  ]
}

## Create Private Endpoint for AI Search
##
module "private_endpoint_ai_search" {
  depends_on = [
    module.ai_search
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.ai_search.name
  resource_id      = module.ai_search.id
  subresource_name = "searchService"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
  ]
}

## Create Private Endpoint for Storage Account for blob endpoint
##
module "private_endpoint_storage_account_default" {
  depends_on = [
    module.storage_account_default
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "blob"

  subnet_id = var.subnet_id_private_endpoints
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}

## Pause for 30 seconds to allow creation of Application Insights resource to replicate
## Application Insight instances created and integrated with Log Analytics can take time to replicate the resource
resource "time_sleep" "wait_appins" {
  depends_on = [
    azurerm_application_insights.appins
  ]
  create_duration = "60s"
}

##### Create AI Foundry Project, connections to CosmosDB, AI Search, Storage Account, Grounding Search with Bing, and Application Insights
#####

## Create AI Foundry project using a moudule that creates the project, project connections, capabilities hosts, and Azure RBAC role assignments
##
module "ai_foundry_project_sample" {
  depends_on = [
    azapi_resource.ai_foundry_resource,
    module.private_endpoint_ai_foundry,
    module.private_endpoint_cosmos_db,
    module.private_endpoint_ai_search,
    module.private_endpoint_storage_account_default,
    time_sleep.wait_appins,
    azapi_resource.bing_grounding_search,
    null_resource.add-subnet-delegation,
    azurerm_cognitive_account_customer_managed_key.ai_foundry_cmk
  ]

  source              = "../../modules/ai-foundry/project"
  resource_group_id   = azapi_resource.ai_foundry_resource.parent_id
  resource_group_name = provider::azapi::parse_resource_id("Microsoft.CognitiveServices/accounts", azapi_resource.ai_foundry_resource.id).resource_group_name
  ai_foundry_resource_id = azapi_resource.ai_foundry_resource.id
  location            = var.location

  # Project name and description
  project_name        = "sample_project1"
  project_description = "This is a sample AI Foundry project"

  # Project connected resources
  cosmosdb_name = module.cosmos_db.name
  cosmosdb_resource_id = module.cosmos_db.id
  cosmosdb_document_endpoint = module.cosmos_db.endpoint

  aisearch_name = module.ai_search.name
  aisearch_resource_id = module.ai_search.id

  storage_account_blob_endpoint = module.storage_account_default.endpoint_blob
  storage_account_name = module.storage_account_default.name
  storage_account_resource_id = module.storage_account_default.id

  application_insights_connection_string = azurerm_application_insights.appins.connection_string
  application_insights_name = azurerm_application_insights.appins.name
  application_insights_resource_id = azurerm_application_insights.appins.id

  bing_grounding_search_name = azapi_resource.bing_grounding_search.name
  bing_grounding_search_resource_id = azapi_resource.bing_grounding_search.id
  bing_grounding_search_subscription_key = data.azapi_resource_action.bing_api_keys.output.key1
}

##### Create Azure RBAC role assignments to support Import and Vectorize function of AI Search
#####
resource "azurerm_role_assignment" "cognitive_services_openai_user_ai_search_service" {
  depends_on = [
    azapi_resource.ai_foundry_resource,
    module.ai_search
  ]
  name                 = uuidv5("dns", "${module.ai_search.managed_identity_principal_id}${azapi_resource.ai_foundry_resource.name}openaiuser")
  scope                = azapi_resource.ai_foundry_resource.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.ai_search.managed_identity_principal_id
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_search_service" {
  depends_on = [
    azapi_resource.ai_foundry_resource,
    module.storage_account_default
  ]
  name                 = uuidv5("dns", "${module.ai_search.managed_identity_principal_id}${module.storage_account_default.name}blobdatacontributor")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.ai_search.managed_identity_principal_id
}

##### Create role assignments for human users
#####

## Create a role assignment granting a user the Azure AI User role which will allow the user
## the ability to utilize the AI Foundry project
resource "azurerm_role_assignment" "ai_foundry_user" {
  name                 = uuidv5("dns", "${var.user_object_id}${azapi_resource.ai_foundry_resource.name}user")
  scope                = module.ai_foundry_project_sample.id
  role_definition_name = "Azure AI User"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Storage Blob Data Contributor role which will allow the user
## to upload files to the Storage Account used by the AI Foundry project
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  name                 = uuidv5("dns", "${var.user_object_id}${module.storage_account_default.name}blobdatacont")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Search Service Contributor role which will allow the user
## to create and manage indexes in the AI Search Service
resource "azurerm_role_assignment" "aisearch_user_service_contributor" {
  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_search.name}servicecont")
  scope                = module.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Search Index Data Contributor role which will allow the user
## to create new records in existing indexes in an AI Search Service
resource "azurerm_role_assignment" "aisearch_user_data_contributor" {
  depends_on = [
    azurerm_role_assignment.aisearch_user_service_contributor
  ]
  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_search.name}datacont")
  scope                = module.ai_search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.user_object_id
}

## Added AI Foundry account purger to avoid running into InUseSubnetCannotBeDeleted-lock caused by the agent subnet delegation.
## The azapi_resource_action.purge_ai_foundry (only gets executed during destroy) purges the AI foundry account removing /subnets/snet-agent/serviceAssociationLinks/legionservicelink so the agent subnet can get properly removed.
## Credit for this to Sebastian Graf
resource "azapi_resource_action" "purge_ai_foundry" {
  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${azurerm_resource_group.rg_work.location}/resourceGroups/${azurerm_resource_group.rg_work.name}/deletedAccounts/aifoundry${var.random_string}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"
}
