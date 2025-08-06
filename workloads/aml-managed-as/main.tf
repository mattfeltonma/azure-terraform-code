########## Create resource group and Log Analytics Workspace
##########
  
## Create a Log Analytics Workspace where resources in this deployment will send their diagnostic logs
##
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.workspace_resource_group_name

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
  resource_group_name = var.workspace_resource_group_name
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  # Resource logs for the Container Registry will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  # Module has incoming public access disabled by default with trusted Azure Services bypass
  default_network_action = "Deny"
  bypass_network_rules   = "AzureServices"
}

# Create storage account which will be used as the default storage account for the AML workspace. The storage account will block public access
# and use resource access rules to allow the AML hub and projects. Key-based authentication will be disabled to enforce Entra ID authentication
# and Azure RBAC authorization. Key-based authentication will be disabled to enforce Entra ID authentication and Azure RBAC authorization.
module "storage_account_aml" {

  source              = "../../modules/storage-account"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  # Resource logs for all endpoints the storage account will be sent to this Log Analytics Workspace
  law_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

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

# Create Key Vault which will hold secrets for the AML workspace. Public access will be disabled with the Trusted Services Exception to allow
# the AI Foundry instance to access the Key Vault for retrieval of secrets.
#
resource "azurerm_key_vault" "kv" {
  name                = "kv${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.workspace_resource_group_name

  sku_name  = local.sku_name
  tenant_id = data.azurerm_subscription.current.tenant_id

  enabled_for_deployment          = local.deployment_vm
  enabled_for_template_deployment = local.deployment_template
  enable_rbac_authorization       = true

  enabled_for_disk_encryption = false
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  depends_on = [ 
    azurerm_key_vault.kv
  ]

  name                       = "diag-base"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

########## Create the user-assigned managed identity for the AML workspace and the the necessary role assignments. 
########## This section is only executed if the user specifies that a user-assigned managed identity should be created
########## using the user_assigne_managed_identity variable

# Create the user-assigned managed identity for the AML workspace
#
resource "azurerm_user_assigned_identity" "umi_aml" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_application_insights.aml-appins,
    module.storage_account_aml,
    azurerm_key_vault.kv
  ]

  name                = "${local.umi_prefix}${var.purpose}${var.location_code}${var.random_string}"
  resource_group_name = var.workspace_resource_group_name
  location            = var.location

  tags = var.tags
}
 
# Pause for 10 seconds to allow the managed identity that was created to be replicated
#
resource "time_sleep" "wait_umi_aml_creation" {
  count = var.managed_identity == "user_assigned" ? 1 : 0

  depends_on = [
    azurerm_user_assigned_identity.umi_aml[0]
  ]
  create_duration = "10s"
}

##### Create the Azure Machine Learning Workspace and its child resources
#####

## Create the Azure Machine Learning Workspace in a managed vnet configuration
##
resource "azapi_resource" "aml_workspace" {
  depends_on = [
    azurerm_application_insights.aml-appins,
    module.storage_account_aml,
    azurerm_key_vault.kv,
    module.container_registry,
    time_sleep.wait_umi_aml_creation
  ]

  type                      = "Microsoft.MachineLearningServices/workspaces@2025-06-01"
  name                      = "${local.aml_workspace_prefix}${var.purpose}${var.location_code}${var.random_string}"
  parent_id                 = var.workspace_resource_group_id
  location                  = var.location
  schema_validation_enabled = false

  body = {

    # Set the hub to use a user-assigned managed identity if specified, otherwise use a system-assigned managed identity
    identity = var.managed_identity == "user_assigned" ? {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.umi_aml[0].id}" = {}
      }
      } : {
      type = "SystemAssigned"
      userAssignedIdentities = {}
    }

    # Create a non hub-based AML workspace
    kind = "Default"

    properties = {
      description = "Azure Machine Learning Workspace for testing"

      # The version of the managed network model to use; unsure what v2 is
      managedNetworkKind = "V1"

      # The resources that will be associated with the AML Workspace
      applicationInsights = azurerm_application_insights.aml-appins.id
      keyVault            = azurerm_key_vault.kv.id
      storageAccount      = module.storage_account_aml.id
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
          managed_pe_nonprod_registry = {
            category = "UserDefined"
            type = "PrivateEndpoint"
            destination = {
              serviceResourceId = var.registry_id_nonprod
              subresourceTarget = "amlregistry"
            }
          }

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
    module.storage_account_aml
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.workload_vnet_location
  location_code       = var.workload_vnet_location_code
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "blob"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "file"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "table"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = module.storage_account_aml.name
  resource_id      = module.storage_account_aml.id
  subresource_name = "queue"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = azurerm_key_vault.kv.name
  resource_id      = azurerm_key_vault.kv.id
  subresource_name = "vault"


  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
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
  resource_group_name = var.workspace_resource_group_name
  tags                = var.tags

  resource_name    = module.container_registry.name
  resource_id      = module.container_registry.id
  subresource_name = "registry"

  subnet_id = var.subnet_id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
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
  resource_group_name = var.workspace_resource_group_name
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



