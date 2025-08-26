########## Create resource group and Log Analytics Workspace
##########
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

######### Create the Azure AI Foundry resource that supports Standard Agents
#########
#########

## Create the AI Foundry account
##
module "ai_foundry_account" {
  source              = "../../modules/ai-foundry/account"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  resource_group_id   = azurerm_resource_group.rg_work.id
  purpose             = var.purpose
  tags                = var.tags

  # Provide the information the existing Private DNS Zones
  resource_group_name_dns = var.resource_group_name_dns
  sub_id_dns              = var.sub_id_dns

  # Provide encryption information
  # (As of 8/6/2025) Note that user-assigned managed identities are not yet supported for CMK encryption
  # so there isn't much use of using an UMI at this time
  managed_identity = "system_assigned"
  encryption       = var.encryption
  # This user is granted Key Vault Administrator over the Key Vault and this is only necessary for this sample code
  user_object_id   = var.user_object_id

  # Provide the subnet that has been delegated for the Standard Agent and the subnet where Private Endpoints
  # for Standard Agent resources will be created
  subnet_id_agent             = var.subnet_id_agent
  subnet_id_private_endpoints = var.subnet_id_private_endpoints

  # Provide the IP address for the machine deploying the Terraform code giving it access to the Azure Key Vault instance
  # This is only necessary for this sample code
  trusted_ip =  var.trusted_ip

  # Provide the resource ID of the Log Analytics Workspace the resources deployed to will deliver logs to
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

########## Create required human role assignments
##########

## Create a role assignment granting a user the Azure AI User role which will allow the user
## the ability to utilize the sample AI Foundry project
resource "azurerm_role_assignment" "ai_foundry_user" {
  depends_on = [ 
    module.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_foundry_account.foundry_project_id}user")
  scope                = module.ai_foundry_account.foundry_project_id
  role_definition_name = "Azure AI User"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Cognitive Services User role which will allow the user
## to use the various Playgrounds such as the Speech Playground
resource "azurerm_role_assignment" "cognitive_services_user" {
  depends_on = [
    module.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_foundry_account.foundry_account_name}cognitiveservicesuser")
  scope                = module.ai_foundry_account.foundry_account_id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.user_object_id
}

########## Create optional non-human role assignments to support import and vectorize feature of AI Search
##########

resource "azurerm_role_assignment" "cognitive_services_openai_user_ai_search_service" {
  depends_on = [
    module.ai_foundry_account
  ]
  name                 = uuidv5("dns", "${module.ai_foundry_account.managed_identity_principal_id_ai_search}${module.ai_foundry_account.foundry_account_name}openaiuser")
  scope                = module.ai_foundry_account.foundry_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.ai_foundry_account.managed_identity_principal_id_ai_search
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_search_service" {
  depends_on = [ 
    module.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${module.ai_foundry_account.managed_identity_principal_id_ai_search}${module.ai_foundry_account.storage_account_name}blobdatacontributor")
  scope                = module.ai_foundry_account.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.ai_foundry_account.managed_identity_principal_id_ai_search
}

########## Create optional human role assignments to support import and vectorize feature of AI Search
##########

## Create a role assignment granting a user the Search Service Contributor role which will allow the user
## to create and manage indexes in the AI Search Service
resource "azurerm_role_assignment" "aisearch_user_service_contributor" {
  depends_on = [ 
    module.ai_foundry_account
  ]

  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_foundry_account.ai_search_name}servicecont")
  scope                = module.ai_foundry_account.ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.user_object_id
}

## Create a role assignment granting a user the Search Index Data Contributor role which will allow the user
## to create new records in existing indexes in an AI Search Service
resource "azurerm_role_assignment" "aisearch_user_data_contributor" {
  count = var.subnet_id_agent != null ? 1 : 0

  depends_on = [
    azurerm_role_assignment.aisearch_user_service_contributor
  ]
  name                 = uuidv5("dns", "${var.user_object_id}${module.ai_foundry_account.ai_search_name}datacont")
  scope                = module.ai_foundry_account.ai_search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.user_object_id
}