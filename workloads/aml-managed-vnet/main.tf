########## Create resource group and Log Analytics Workspace
##########

## Create resource group the resources in this deployment will be deployed to
##
resource "azurerm_resource_group" "rg_work" {

  name     = "rgaml${var.location_code}${var.random_string}"
  location = var.location

  tags = var.tags
}
 
## Create a Log Analytics Workspace where resources in this deployment will send their diagnostic logs
##
resource "azurerm_log_analytics_workspace" "law" {
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
resource "azurerm_monitor_diagnostic_setting" "diag_law" {
  depends_on = [
    azurerm_log_analytics_workspace.law
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_log_analytics_workspace.law.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "Audit"
  }
  enabled_log {
    category = "SummaryLogs"
  }
}

########## Create resources required by AML workspace
##########

## Create Application Insights for AML Workspace
##
resource "azurerm_application_insights" "app_insights_aml" {
  depends_on = [
    azurerm_log_analytics_workspace.law
  ]
  name                = "${local.app_insights_prefix}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_work.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "other"
}

## Create an Azure Container Registry instance for AML Workspace
##
module "container_registry_aml" {
  source              = "../../modules/container-registry"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  # Resource logs for the Container Registry will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.law.id

  # Module has incoming public access disabled by default with trusted Azure Services bypass
  default_network_action = "Deny"
  bypass_network_rules   = "AzureServices"
}

## Create storage account which will be used as the default storage account for the AML workspace. The storage account will block public access
## and use resource access rules to allow the AML hub and projects. Key-based authentication will be disabled to enforce Entra ID authentication
## and Azure RBAC authorization. Key-based authentication will be disabled to enforce Entra ID authentication and Azure RBAC authorization.
module "storage_account_aml" {

  source              = "../../modules/storage-account"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  # Resource logs for all endpoints the storage account will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.law.id

  # Disable storage access keys
  key_based_authentication = false

  # Block public access and use resource rules to allow the AI Foundry Hub and projects to access the storage account through the Microsoft public backbone 
  # using a managed identity.
  network_access_default = "Deny"
  resource_access = [
    {
      endpoint_resource_id = "/subscriptions/${var.sub_id_dns}/resourcegroups/*/providers/Microsoft.MachineLearningServices/workspaces/*"
    }
  ]
}

## Create Key Vault which will hold secrets for the AML workspace. Public access will be disabled with the Trusted Services Exception to allow
## the AI Foundry instance to access the Key Vault for retrieval of secrets.
##
module "keyvault_aml" {
  source              = "../../modules/key-vault"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  purpose             = var.purpose
  tags                = var.tags

  # Resource logs for the Key Vault will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.law.id

  # The user specified here will have the Azure RBAC Key Vault Administrator role over the Azure Key Vault instance
  kv_admin_object_id = var.user_object_id

  # Disable public access and allow the Trusted Azure Service firewall exception
  firewall_default_action = "Deny"
  firewall_bypass         = "AzureServices"
}

########## Create the user-assigned managed identity for the AML workspace and the the necessary role assignments. 
########## This section is only executed if the user specifies that a user-assigned managed identity should be created
########## using the user_assigne_managed_identity variable

## Create the user-assigned managed identity for the AML workspace
##
resource "azurerm_user_assigned_identity" "umi_aml" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_resource_group.rg_work,
    azurerm_application_insights.app_insights_aml,
    module.storage_account_aml,
    module.keyvault_aml
  ]

  name                = "${local.umi_prefix}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rg_work.name
  location            = var.location

  tags = var.tags
}

## Pause for 10 seconds to allow the managed identity that was created to be replicated
##
resource "time_sleep" "wait_umi_aml_creation" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_aml[0]
  ]
  create_duration = "10s"
}

## Assign the managed identity the Azure AI Administrator role on the resource group
## This resource group should contain the Application Insights, Container Registry, Storage Account (default),
## and Key Vault used by the AI Foundry instance being created
resource "azurerm_role_assignment" "umi_aml_rg_aiadministrator" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    time_sleep.wait_umi_aml_creation[0]
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${azurerm_user_assigned_identity.umi_aml[0].name}aiadmin")
  scope                = azurerm_resource_group.rg_work.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml[0].principal_id
}

## Create Azure RBAC role assignments on the default storage account for the AML Hub user-assigned managed identity 
## to assign Blob Data Contributor and File Data Privileged Contributor roles. This enables the AML Hub identity to create
## the necessary blob containers and file shares required by projects
resource "azurerm_role_assignment" "umi_aml_st_blob_data_contributor" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_aml_rg_aiadministrator[0]
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${module.storage_account_aml.name}${azurerm_user_assigned_identity.umi_aml[0].name}blobdata")
  scope                = module.storage_account_aml.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml[0].principal_id
}

resource "azurerm_role_assignment" "umi_aml_st_file_data_contributor" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_aml_st_blob_data_contributor[0]
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${module.storage_account_aml.name}${azurerm_user_assigned_identity.umi_aml[0].name}filedata")
  scope                = module.storage_account_aml.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.umi_aml[0].principal_id
}

## Create Azure RBAC role assignment on AML key vault for the AML workspace user-assigned managed identity
## to assign the Key Vault Administrator role. This enabled the AML identity to create and managed secrets in the key vault
## for connections
resource "azurerm_role_assignment" "umi_aml_kv_admin" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_aml_st_file_data_contributor[0]
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${module.keyvault_aml.name}${azurerm_user_assigned_identity.umi_aml[0].name}kvadmin")
  scope                = module.keyvault_aml.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.umi_aml[0].principal_id
}

## Create Azure RBAC role assignment on the resource group for the AML workspace user-assigned managed identity
## to assign the Azure AI Enterprise Network Connection Approver role. This is required for the workspace to create
## the managed private endpoints in the managed virtual network
resource "azurerm_role_assignment" "umi_aml_rg_azure_ai_ent_net_conn_app" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_aml_kv_admin[0]
  ]

  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${azurerm_user_assigned_identity.umi_aml[0].name}entnetconnapp")
  scope                = azurerm_resource_group.rg_work.id
  role_definition_name = "Azure AI Enterprise Network Connection Approver"
  principal_id         = azurerm_user_assigned_identity.umi_aml[0].principal_id
}

## Pause for 120 seconds to allow the role assignments to be replicated
##
resource "time_sleep" "wait_umi_role_assignments" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_role_assignment.umi_aml_rg_azure_ai_ent_net_conn_app[0]
  ]
  create_duration = "120s"
}

########## Create the Azure Machine Learning Workspace and its child resources
##########

## Create the Azure Machine Learning Workspace in a managed vnet configuration
##
resource "azapi_resource" "aml_workspace" {
  depends_on = [
    azurerm_resource_group.rg_work,
    azurerm_application_insights.app_insights_aml,
    module.storage_account_aml,
    module.keyvault_aml,
    module.container_registry_aml,
    time_sleep.wait_umi_role_assignments
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-06-01"
  name                      = "${local.aml_workspace_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rg_work.id
  location                  = var.location
  schema_validation_enabled = false

  body = {

    # Set the AML workspace to use a user-assigned managed identity if specified, otherwise use a system-assigned managed identity
    identity = var.managed_identity == "user_assigned" ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.umi_aml[0].id}" = {}
      }
      } : {
      type = "SystemAssigned"
    }

    # Create a non hub-based AML workspace
    kind = "Default"

    properties = {
      description = "Azure Machine Learning Workspace for testing"
      # The version of the managed network model to use; unsure what v2 is
      managedNetworkKind = "V1"
      # The resources that will be associated with the AML Workspace
      applicationInsights = azurerm_application_insights.app_insights_aml.id
      keyVault            = module.keyvault_aml.id
      storageAccount      = module.storage_account_aml.id
      containerRegistry   = module.container_registry_aml.id
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
      # Set the primary user assigned managed identity for the AML workspace
      primaryUserAssignedIdentity = var.managed_identity == "user_assigned" ? azurerm_user_assigned_identity.umi_aml[0].id : null
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
resource "azurerm_monitor_diagnostic_setting" "diag_aml_workspace" {
  depends_on = [
    azapi_resource.aml_workspace,
    azurerm_log_analytics_workspace.law
  ]

  name                       = "diag-base"
  target_resource_id         = azapi_resource.aml_workspace.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

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

########## Create a Private Endpoints workspace required resources including default storage account
########## Key Vault, and Container Registry

## Create Private Endpoints in the customer virtual network for default storage account for blob and file, 
## Key Vault, and Container Registry
module "private_endpoint_st_default_blob_aml" {
  depends_on = [
    module.storage_account_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "blob"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  ]
}

module "private_endpoint_st_default_file_aml" {
  depends_on = [
    module.private_endpoint_st_default_blob_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "file"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  ]
}

module "private_endpoint_st_default_table_aml" {
  depends_on = [
    module.private_endpoint_st_default_file_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "table"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
  ]
}

module "private_endpoint_st_default_queue_aml" {
  depends_on = [
    module.private_endpoint_st_default_table_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "queue"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
  ]
}

module "private_endpoint_kv_aml" {
  depends_on = [
    module.private_endpoint_st_default_queue_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.keyvault_aml.name
  resource_id      = module.keyvault_aml.id
  subresource_name = "vault"


  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  ]
}

module "private_endpoint_container_registry_aml" {
  depends_on = [
    module.private_endpoint_kv_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = module.container_registry_aml.name
  resource_id      = module.container_registry_aml.id
  subresource_name = "registry"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  ]
}

######### Create Private Endpoint for AML Workspace and the A record for the AML Workspace compute instances
#########

## Create Private Endpoint for AML Workspace
##
module "private_endpoint_aml_workspace" {
  depends_on = [
    module.private_endpoint_container_registry_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = azurerm_resource_group.rg_work.name
  tags                = var.tags

  resource_name    = azapi_resource.aml_workspace.name
  resource_id      = azapi_resource.aml_workspace.id
  subresource_name = "amlworkspace"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.api.azureml.ms",
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.notebooks.azure.net"
  ]
}

## Create the A record for the AML Workspace compute instances only if it doesn't already exist
## Using null_resource with Azure CLI to avoid count dependency issues
##
resource "null_resource" "aml_workspace_compute_instance_dns" {
  depends_on = [
    module.private_endpoint_aml_workspace
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Check if the DNS A record already exists
      if ! az network private-dns record-set a show \
        --resource-group "${var.resource_group_name_dns}" \
        --zone-name "instances.azureml.ms" \
        --name "*.${var.location}" \
        --subscription "${var.sub_id_dns}" >/dev/null 2>&1; then
        
        # Create the DNS A record if it doesn't exist
        az network private-dns record-set a create \
          --resource-group "${var.resource_group_name_dns}" \
          --zone-name "instances.azureml.ms" \
          --name "*.${var.location}" \
          --subscription "${var.sub_id_dns}"
        
        # Add the private endpoint IP to the record set
        az network private-dns record-set a add-record \
          --resource-group "${var.resource_group_name_dns}" \
          --zone-name "instances.azureml.ms" \
          --record-set-name "*.${var.location}" \
          --ipv4-address "${module.private_endpoint_aml_workspace.private_endpoint_ip}" \
          --subscription "${var.sub_id_dns}"
        
        echo "DNS A record created for *.${var.location} in instances.azureml.ms"
      else
        echo "DNS A record for *.${var.location} already exists in instances.azureml.ms"
      fi
    EOT
  }

  # Trigger when the private endpoint IP changes
  triggers = {
    private_endpoint_ip = module.private_endpoint_aml_workspace.private_endpoint_ip
    location           = var.location
    resource_group     = var.resource_group_name_dns
    subscription       = var.sub_id_dns
  }
}

##### Create non-human role assignments
#####
 
resource "time_sleep" "wait_aml_workspace_identities" {
  depends_on = [
    azapi_resource.aml_workspace
  ]
  create_duration = "10s"
}

## Create role assignments granting Azure AI Enterprise Network Connection Approver role over the resource group to the AML Workspace's
## system-managed identity or user-assigned managed identity
resource "azurerm_role_assignment" "ai_network_connection_approver" {
  count = var.managed_identity == "system_assigned" ? 1 : 0

  depends_on = [
    time_sleep.wait_aml_workspace_identities
  ]
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${azapi_resource.aml_workspace.output.identity.principalId}netapprover")
  scope                = azurerm_resource_group.rg_work.id
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
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${var.user_object_id}${azapi_resource.aml_workspace.name}aidev")
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
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${var.user_object_id}${azapi_resource.aml_workspace.name}computeoperator")
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
  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${var.user_object_id}${azapi_resource.aml_workspace.name}datascientist")
  scope                = azapi_resource.aml_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = var.user_object_id
}

## Create role assignments for the data scientist granting them the Storage Blob Data Contributor and Storage File Data Privileged Contributor roles
## over the default storage account
##
#resource "azurerm_role_assignment" "blob_perm_default_sa" {
#  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${var.user_object_id}${module.storage_account_aml.name}blob")
#  scope                = module.storage_account_aml.id
#  role_definition_name = "Storage Blob Data Contributor"
#  principal_id         = var.user_object_id
#}

#resource "azurerm_role_assignment" "file_perm_default_sa" {
#  name                 = uuidv5("dns", "${azurerm_resource_group.rg_work.name}${var.user_object_id}${module.storage_account_aml.name}file")
#  scope                = module.storage_account_aml.id
#  role_definition_name = "Storage File Data Privileged Contributor"
#  principal_id         = var.user_object_id
#}

