##### Create scaffolding
#####

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rgwork" {

  name     = "rgaml${var.location_code}${var.random_string}"
  location = var.location

  tags = var.tags
}
 
## Create a Log Analytics Workspace where resources in this deployment will send their diagnostic logs
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.location_code}${var.random_string}"
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

## Configure diagnostic settings for Log Analytics Workspace
##
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

##### Create resources required by AML workspace
#####

## Create Application Insights for AML Workspace
##
resource "azurerm_application_insights" "aml-appins" {
  depends_on = [
    azurerm_log_analytics_workspace.log_analytics_workspace
  ]
  name                = "${local.app_insights_prefix}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rgwork.name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics_workspace.id
  application_type    = "other"
}

## Create an Azure Container Registry instance for AML Workspace
##
module "container_registry" {
  source              = "../../modules/container-registry"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  law_resource_id     = azurerm_log_analytics_workspace.log_analytics_workspace.id

  tags = var.tags
}

## Create storage account which will be default storage account for AML Workspace
##
module "storage_account_default" {

  source                   = "../../modules/storage-account"
  purpose                  = var.purpose
  random_string            = var.random_string
  location                 = var.location
  location_code            = var.location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags = var.tags
  
  # Identity controls
  key_based_authentication = false

  # Networking controls
  allow_blob_public_access = false
  network_access_default = "Deny"
  network_trusted_services_bypass = [ 
    "None"
   ]
  resource_access = [
    {
      endpoint_resource_id = "/subscriptions/${var.sub_id}/resourcegroups/*/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  ]
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

## Create Key Vault which will hold secrets for the AML workspace and assign user the Key Vault Administrator role over it
##
module "keyvault_aml" {

  source              = "../../modules/key-vault"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  purpose             = var.purpose
  law_resource_id     = azurerm_log_analytics_workspace.log_analytics_workspace.id
  tags                = var.tags

  kv_admin_object_id = var.user_object_id

  firewall_default_action = "Deny"
  firewall_bypass         = "AzureServices"
}

##### Create the Azure Machine Learning Workspace and its child resources
#####

## Create the Azure Machine Learning Workspace in a managed vnet configuration
##
resource "azapi_resource" "aml_workspace" {
  depends_on = [
    azurerm_resource_group.rgwork,
    azurerm_application_insights.aml-appins,
    module.storage_account_default,
    module.keyvault_aml,
    module.container_registry
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-04-01-preview"
  name                      = "${local.aml_workspace_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rgwork.id
  location                  = var.location
  schema_validation_enabled = false

  body = {

    # Create the AML Workspace with a system-assigned managed identity
    identity = {
      type = "SystemAssigned"
    }

    # Create a non hub-based AML workspace
    kind = "Default"

    properties = {
      description = "Azure Machine Learning Workspace for testing"

      # The version of the managed network model to use; unsure what v2 is
      managedNetworkKind = "V1"

      # The resources that will be associated with the AML Workspace
      applicationInsights = azurerm_application_insights.aml-appins.id
      keyVault            = module.keyvault_aml.id
      storageAccount      = module.storage_account_default.id
      containerRegistry   = module.container_registry.id

      # Block access to the AML Workspace over the public endpoint
      publicNetworkAccess = "disabled"

      # Configure the AML workspace to use the managed virtual network model
      managedNetwork = {
        # Managed virtual network will block all outbound traffic unless explicitly allowed
        isolationMode = "AllowOnlyApprovedOutbound"
        # Use Azure Firewall Standard SKU to support FQDN-based rules
        firewallSku   = "Standard"

        # Create a series of outbound rules to allow access to other private endpoints and FQDNs on the Internet
        outboundRules = { 
          # Create required FQDN rules to support usage of Python package managers such as pip and conda
          AllowPypi = {
            type        = "FQDN"
            destination = "pypi.org"
            category    = "UserDefined"
          }
          AllowPythonHostedWildcard = {
            type        = "FQDN"
            destination = "*.pythonhosted.org"
            category    = "UserDefined"
          }
          AllowAnacondaCom = {
            type        = "FQDN"
            destination = "anaconda.com"
            category    = "UserDefined"
          }
          AllowAnacondaComWildcard = {
            type        = "FQDN"
            destination = "*.anaconda.com"
            category    = "UserDefined"
          }
          AllowAnacondaOrgWildcard = {
            type        = "FQDN"
            destination = "*.anaconda.org"
            category    = "UserDefined"
          }
          # Create fqdn rules to allow for pulling Docker images like Python, Jupyter, and other images
          AllowDockerIo = {
            type    = "FQDN"
            destination = "docker.io"
            category    = "UserDefined"
          }
          AllowDockerIoWildcard = {
            type    = "FQDN"
            destination = "*.docker.io"
            category    = "UserDefined"
          }
          AllowDockerComWildcard = {
            type    = "FQDN"
            destination = "*.docker.com"
            category    = "UserDefined"
          }
          AllowDockerCloudFlareProduction = {
            type    = "FQDN"
            destination = "production.cloudflare.docker.com"
            category    = "UserDefined"
          }

          # Create fqdn rules to allow for using models from HuggingFace
          AllowCdnAuth0Com = {
            type    = "FQDN"
            destination = "cdn.auth0.com"
            category    = "UserDefined"
          }
          AllowCdnHuggingFaceCo = {
            type    = "FQDN"
            destination = "cdn-lfs.huggingface.co"
            category    = "UserDefined"
          }

          # Create fqdn rules to support usage of SSH to compute instances in a managed virtual network from Visual Studio Code
          AllowVsCodeDevWildcard = {
            type        = "FQDN"
            destination = "*.vscode.dev"
            category    = "UserDefined"
          }
          AllowVsCodeBlob = {
            type        = "FQDN"
            destination = "vscode.blob.core.windows.net"
            category    = "UserDefined"
          }
          AllowGalleryCdnWildcard = {
            type        = "FQDN"
            destination = "*.gallerycdn.vsassets.io"
            category    = "UserDefined"
          }
          AllowRawGithub = {
            type        = "FQDN"
            destination = "raw.githubusercontent.com"
            category    = "UserDefined"
          }
          AllowVsCodeUnpkWildcard = {
            type        = "FQDN"
            destination = "*.vscode-unpkg.net"
            category    = "UserDefined"
          }
          AllowVsCodeCndWildcard = {
            type        = "FQDN"
            destination = "*.vscode-cdn.net"
            category    = "UserDefined"
          }
          AllowVsCodeExperimentsWildcard = {
            type        = "FQDN"
            destination = "*.vscodeexperiments.azureedge.net"
            category    = "UserDefined"
          }
          AllowDefaultExpTas = {
            type        = "FQDN"
            destination = "default.exp-tas.com"
            category    = "UserDefined"
          }
          AllowCodeVisualStudio = {
            type        = "FQDN"
            destination = "code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowUpdateCodeVisualStudio = {
            type        = "FQDN"
            destination = "update.code.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsMsecndNet = {
            type        = "FQDN"
            destination = "*.vo.msecnd.net"
            category    = "UserDefined"
          }
          AllowMarketplaceVisualStudio = {
            type        = "FQDN"
            destination = "marketplace.visualstudio.com"
            category    = "UserDefined"
          }
          AllowVsCodeDownload = {
            type        = "FQDN"
            destination = "vscode.download.prss.microsoft.com"
            category    = "UserDefined"
          }
        }
      }
      # Allow the platform to grant the SMI for the workspace AI Administrator on the resource group the AML workspace
      # is deployed to.
      allowRoleAssignmentOnRG = true
      # The default storage account associated with AML workspace will use Entra ID for authentication instad of storage access keys
      systemDatastoresAuthMode = "identity"
      # Create the manage virtual network for the AML workspace upon creation vs waiting for the first compute resource to be created
      provisionNetworkNow = true
    }

    tags = var.tags
  }
  response_export_values = [
    "identity.principalId"
  ]
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create diagnostic settings for AML workspace
##
resource "azurerm_monitor_diagnostic_setting" "aml-diag-base" {
  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_log_analytics_workspace.log_analytics_workspace
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  enabled_log {
    category = "AmlComputeClusterNodeEvent"
  }
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  enabled_log {
    category = "AmlComputeCpuGpuUtilization"
  }
  enabled_log {
    category = "AmlRunStatusChangedEvent"
  }
  enabled_log {
    category = "ModelsChangeEvent"
  }
  enabled_log {
    category = "ModelsReadEvent"
  }
  enabled_log {
    category = "ModelsActionEvent"
  }
  enabled_log {
    category = "DeploymentReadEvent"
  }
  enabled_log {
    category = "DeploymentEventACI"
  }
  enabled_log {
    category = "DeploymentEventAKS"
  }
  enabled_log {
    category = "InferencingOperationAKS"
  }
  enabled_log {
    category = "InferencingOperationACI"
  }
  enabled_log {
    category = "EnvironmentChangeEvent"
  }
  enabled_log {
    category = "EnvironmentReadEvent"
  }
  enabled_log {
    category = "DataLabelChangeEvent"
  }
  enabled_log {
    category = "DataLabelReadEvent"
  }
  enabled_log {
    category = "ComputeInstanceEvent"
  }
  enabled_log {
    category = "DataStoreChangeEvent"
  }
  enabled_log {
    category = "DataStoreReadEvent"
  }
  enabled_log {
    category = "DataSetChangeEvent"
  }
  enabled_log {
    category = "DataSetReadEvent"
  }
  enabled_log {
    category = "PipelineChangeEvent"
  }
  enabled_log {
    category = "PipelineReadEvent"
  }
  enabled_log {
    category = "RunEvent"
  }
  enabled_log {
    category = "RunReadEvent"
  }
}

##### Create a Private Endpoints workspace required resources including default storage account
##### Key Vault, and Container Registry

## Create Private Endpoints in the customer virtual network for default storage account for blob and file, 
## Key Vault, and Container Registry
module "private_endpoint_st_default_blob" {
  depends_on = [
    module.storage_account_default
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "blob"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}

module "private_endpoint_st_default_file" {
  depends_on = [
    module.private_endpoint_st_default_blob
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "file"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  ]
}

module "private_endpoint_st_default_table" {
  depends_on = [
    module.private_endpoint_st_default_file
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "table"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
  ]
}

module "private_endpoint_st_default_queue" {
  depends_on = [
    module.private_endpoint_st_default_table
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.storage_account_default.name
  resource_id      = module.storage_account_default.id
  subresource_name = "queue"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
  ]
}

module "private_endpoint_kv" {
  depends_on = [
    module.private_endpoint_st_default_queue
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.keyvault_aml.name
  resource_id      = module.keyvault_aml.id
  subresource_name = "vault"


  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  ]
}

module "private_endpoint_container_registry" {
  depends_on = [
    module.private_endpoint_kv
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = module.container_registry.name
  resource_id      = module.container_registry.id
  subresource_name = "registry"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  ]
}

##### Create Private Endpoint for AML Workspace and the A record for the AML Workspace compute instances
#####

## Create Private Endpoint for AML Workspace
##
module "private_endpoint_aml_workspace" {
  depends_on = [
    module.private_endpoint_container_registry
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = azapi_resource.aml_workspace.name
  resource_id      = azapi_resource.aml_workspace.id
  subresource_name = "amlworkspace"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms",
    "/subscriptions/${var.sub_id}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.notebooks.azure.net"
  ]
}

## Create the A record for the AML Workspace compute instances
##
resource "azurerm_private_dns_a_record" "aml_workspace_compute_instance" {
  depends_on = [
    module.private_endpoint_aml_workspace
  ]

  name                = "*.${var.location}"
  zone_name           = "instances.azureml.ms"
  resource_group_name = var.resource_group_name_dns
  ttl                 = 10
  records             = [
    module.private_endpoint_aml_workspace.private_endpoint_ip
  ]
}

##### Create non-human role assignments
#####
 
resource "time_sleep" "wait_aml_workspace_identities" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  create_duration = "10s"
}

## Create role assignments granting Reader role over the resource group to AML Workspace's
## system-managed identity
resource "azurerm_role_assignment" "rg_reader" {
  depends_on = [
    time_sleep.wait_aml_workspace_identities
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${azapi_resource.aml_workspace.output.identity.principalId}reader")
  scope                = azurerm_resource_group.rgwork.id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.aml_workspace.output.identity.principalId
}

## Create role assignments granting Azure AI Enterprise Network Connection Approver role over the resource group to the AML Workspace's
## system-managed identity
resource "azurerm_role_assignment" "ai_network_connection_approver" {
  depends_on = [
    azurerm_role_assignment.rg_reader
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${azapi_resource.aml_workspace.output.identity.principalId}netapprover")
  scope                = azurerm_resource_group.rgwork.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azapi_resource.aml_workspace.output.identity.principalId
}

##### Create human role assignments
#####

## Create Azure RBAC Role Assignment granting the Azure AI Developer Role to the user.
## This allows the user to deploy models from the catalog to serverless compute resources
##
resource "azurerm_role_assignment" "wk_perm_ai_developer" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${azapi_resource.aml_workspace.name}aidev")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "Azure AI Developer"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Compute Operator role to the user.
## This allows the user to perform all actions on compute resources within the workspace.
##
resource "azurerm_role_assignment" "wk_perm_compute_operator" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${azapi_resource.aml_workspace.name}computeoperator")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Compute Operator"
  principal_id         = var.user_object_id
}

## Create Azure RBAC Role Assignment granting the Azure Machine Learning Data Scientist role to the user.
## This allows the user to perform all actions except for creating compute resources.
##
resource "azurerm_role_assignment" "wk_perm_data_scientist" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${azapi_resource.aml_workspace.name}datascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.user_object_id
}

## Create role assignments for the data scientist granting them the Storage Blob Data Contributor and Storage File Data Privileged Contributor roles
## over the default storage account
##
resource "azurerm_role_assignment" "blob_perm_default_sa" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.storage_account_default.name}blob")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_object_id
}

resource "azurerm_role_assignment" "file_perm_default_sa" {
  name                 = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.user_object_id}${module.storage_account_default.name}file")
  scope                = module.storage_account_default.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = var.user_object_id
}

