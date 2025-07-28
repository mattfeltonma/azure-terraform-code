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

# Create resource group
#
resource "azurerm_resource_group" "rgwork" {

  name     = "rgoyod${var.location_code}${random_string.unique.result}"
  location = var.location

  tags = var.tags
}

# Create a Log Analytics Workspace
#
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "${local.law_prefix}${var.purpose}${var.location_code}${random_string.unique.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rgwork.name

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

# Configure diagnostic settings
#
resource "azurerm_monitor_diagnostic_setting" "law-diag-base" {
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

# Create an Azure AI Search instance
#
module "ai_search" {
  
  source              = "../../modules/ai-search"
  purpose             = var.purpose
  random_string       = random_string.unique.result
  resource_group_name = azurerm_resource_group.rgwork.name
  resource_group_id   = azurerm_resource_group.rgwork.id
  location            = var.location
  location_code       = var.location_code
  tags = var.tags

  # Configure Search-specific settings
  sku = "standard"
 
  # Configure network settings
  allowed_ips = [
    {
      value = var.your_ip
    }
  ]
  public_network_access = "enabled"
  trusted_services_bypass = "AzureServices"

  # Configure logging
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

# Create an Azure OpenAI instance
#
module "openai" {
  depends_on = [
  ]

  source              = "../../modules/aoai"
  purpose             = var.purpose
  random_string       = random_string.unique.result
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = local.openai_region
  location_code       = local.openai_region_code

  allowed_ips = [
    var.your_ip
  ]
  allowed_fqdn_list = [
    "${module.ai_search.name}.search.windows.net",
    "${module.storage_account_oyod.name}.blob.core.windows.net"
  ]
  public_network_access = true

  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  tags = var.tags
}

# Create storage account which will contain the data we upload to be used with the on your own data feature
#
module "storage_account_oyod" {

  source              = "../../modules/storage-account"
  purpose             = var.purpose
  random_string       = random_string.unique.result
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rgwork.name

  key_based_authentication = false

  cors_rules = [
    {
      allowed_origins    = ["*"]
      allowed_methods    = ["GET", "OPTIONS", "POST", "PUT"]
      allowed_headers    = ["*"]
      max_age_in_seconds = 200
      exposed_headers    = ["*"]
    }
  ]

  allowed_ips = [
    var.your_ip
  ]
  resource_access = [
    {
      endpoint_resource_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourcegroups/*/providers/Microsoft.Search/searchServices/*"
    },
    {
      endpoint_resource_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourcegroups/*/providers/Microsoft.CognitiveServices/accounts/*"
    }
  ]
  tags = var.tags

  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

# Pause for 60 seconds to allow the system-managed identities to replicate
#
resource "time_sleep" "wait" {
  depends_on = [
    module.storage_account_oyod,
    module.openai,
    module.ai_search
  ]

  create_duration = "60s"
}

###### Create non-human role assignments
######

# Create role assignment to allow Azure OpenAI Service instance system-managed identity to read data uploaded by user to blob storage and write embeddings to blob storage in the Azure Storage Account
#
resource "azurerm_role_assignment" "blob_perm_aoai" {
  depends_on = [ 
    time_sleep.wait 
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.openai.managed_identity_principal_id}${module.storage_account_oyod.name}blob")
  scope                = module.storage_account_oyod.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.openai.managed_identity_principal_id
}

# Create role assignment to allow Azure AI Search Service instance system-managed identity to fetch embeddings data from blob storage in the Azure Storage Account
#
resource "azurerm_role_assignment" "blob_perm_search" {
  depends_on = [ 
    azurerm_role_assignment.blob_perm_aoai 
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.ai_search.managed_identity_principal_id}${module.storage_account_oyod.name}blob")
  scope                = module.storage_account_oyod.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.ai_search.managed_identity_principal_id
}

# Create role assignment to allow Azure AI Search Service instance system-managed identity to interact with the Azure OpenAI Service instance
#
resource "azurerm_role_assignment" "aoai_perm_search" {
  depends_on = [ 
    azurerm_role_assignment.blob_perm_search 
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.ai_search.managed_identity_principal_id}${module.openai.name}account")
  scope                = module.openai.id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = module.ai_search.managed_identity_principal_id
}

# Create role assignment for Azure OpenAI Service instance system-managed identity to read from indexes created by user in Azure AI Search Service instance
#
resource "azurerm_role_assignment" "search_perm_aoai_data" {
  depends_on = [ 
    azurerm_role_assignment.aoai_perm_search 
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.openai.managed_identity_principal_id}${module.ai_search.name}searchServicedata")
  scope                = module.ai_search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = module.openai.managed_identity_principal_id
}

# Create role assignment for Azure OpenAI instance system-managed identity to create new search indexes in Azure AI Search Service instance
#
resource "azurerm_role_assignment" "search_perm_aoai_service" {
  depends_on = [ 
    azurerm_role_assignment.search_perm_aoai_data 
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.openai.managed_identity_principal_id}${module.ai_search.name}searchServiceservice")
  scope                = module.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = module.openai.managed_identity_principal_id
}

###### Create human role assignments
######
# Create role assignment to allowing user to create new blob containers for upload use case
#
resource "azurerm_role_assignment" "blob_mgmt_perm_user" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.storage_account_oyod.name}blobcont")
  scope                = module.storage_account_oyod.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.user_object_id
}

# Create role assignment to allow user to upload data to blob storage in the Azure Storage Account
#
resource "azurerm_role_assignment" "blob_data_perm_user" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.storage_account_oyod.name}blobdatacont")
  scope                = module.storage_account_oyod.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}

# Create role assignment to allow user to interact with the Azure OpenAI Service instance
#
resource "azurerm_role_assignment" "aoai_data_perm_user" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.openai.name}account")
  scope                = module.openai.id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = var.user_object_id
}

# Create role assignment for the user to allow the user to create new indexes
#
resource "azurerm_role_assignment" "search_perm_user_service" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.ai_search.name}searchService")
  scope                = module.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.user_object_id
}

# Create role assignment for the user to allow the user to read existing indexes
#
resource "azurerm_role_assignment" "search_perm_user_data" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.ai_search.name}searchServiceData")
  scope                = module.ai_search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = var.user_object_id
}