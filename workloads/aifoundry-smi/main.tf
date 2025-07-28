##### Create general resources
#####

## Create a Log Analytics Workspace that all resources specific to this workload will
## write configured resource logs and metrics to
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.workload_vnet_resource_group_name

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

##### Create AI Foundry resource with support for VNet injection
#####

## Create the Azure Foundry resource
##
resource "azapi_resource" "ai_foundry_resource" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = "aif${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = var.workload_vnet_resource_group_id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    kind = "AIServices",
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {

      # Support both Entra ID and API Key authentication for underlining Cognitive Services account
      disableLocalAuth = true

      # Specifies that this is an AI Foundry resource which will support AI Foundry projects
      allowProjectManagement = true

      # Set custom subdomain name for DNS names created for this Foundry resource
      customSubDomainName = "aif${var.purpose}${var.location_code}${var.random_string}"

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

## Create a deployment for OpenAI's GPT-4o
##
resource "azurerm_cognitive_deployment" "openai_deployment_gpt_4o" {
  depends_on = [
    azapi_resource.ai_foundry_resource
  ]

  name                 = "gpt-4o"
  cognitive_account_id = azapi_resource.ai_foundry_resource.id

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
    azapi_resource.ai_foundry_resource,
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
  resource_group_name = var.workload_vnet_resource_group_name
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
  resource_group_name = var.workload_vnet_resource_group_name
  resource_group_id   = var.workload_vnet_resource_group_id
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
  resource_group_name = var.workload_vnet_resource_group_name
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
  resource_group_name = var.workload_vnet_resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
  application_type    = "other"
}

## Create Grounding Search with Bing
##
resource "azapi_resource" "bing_grounding_search" {
  type                      = "Microsoft.Bing/accounts@2020-06-10"
  name                      = "bingaif${var.location_code}${var.random_string}"
  parent_id                 = var.workload_vnet_resource_group_id
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
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = var.workload_vnet_resource_group_name
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
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = var.workload_vnet_resource_group_name
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
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = var.workload_vnet_resource_group_name
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
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = var.workload_vnet_resource_group_name
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
    null_resource.add-subnet-delegation
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