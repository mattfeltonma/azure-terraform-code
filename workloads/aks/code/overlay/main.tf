########## Create Container Registry for AKS and its Private Endpoint
##########

## Create an Azure Container Registery which will be used to store images for the cluster
##
resource "azurerm_container_registry" "acr" {
  name                = "acraks${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name
  location            = var.region

  sku                    = "Premium"
  admin_enabled          = false
  anonymous_pull_enabled = false

  identity {
    type = "SystemAssigned"
  }

  public_network_access_enabled = false
  network_rule_set {
    default_action = "Deny"
  }
  network_rule_bypass_option = "AzureServices"

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = var.law_resource_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}


## Create a private endpoint for the Container Registry in the private endpoint subnet
##
resource "azurerm_private_endpoint" "pe" {
  name                = "pe${azurerm_container_registry.acr.name}registry"
  location            = var.region
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id_pe

  custom_network_interface_name = "nicpe${azurerm_container_registry.acr.name}registry"

  private_service_connection {
    name                           = "connpe${azurerm_container_registry.acr.name}registry"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.pe_zone_group_conn_name}${var.resource_name}"
    private_dns_zone_ids = var.private_dns_zone_ids
  }

  tags = var.tags
  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

########## Create cluster and kubelet user-assigned managed identities and necessary role assignments
##########

## Create a user-assigned managed identity which will be used by the cluster
##
resource "azurerm_user_assigned_identity" "cluster_identity" {
  name                = "umicluster${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet_identity" {
  name                = "umiakskubelet${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

## Sleep for 10 seconds while the new managed identities replicate
##
resource "null_resource" "cluster_umi_creation" {
  depends_on = [ 
    azurerm_user_assigned_identity.cluster_identity,
    azurerm_user_assigned_identity.kubelet_identity
  ]

  provisioner "local-exec" {
    command = "sleep 10"
  }
}

## Create a role assignment granting the AKS cluster user-assigned managed identity
## the Network Contributor role on the subnet that will be delegated to the CNI
resource "azurerm_role_assignment" "umi_aks_cni_subnet_network_contributor" {
  depends_on = [
    null_resource.cluster_umi_creation
  ]

  name                = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${var.subnet_id_aks}${azurerm_user_assigned_identity.cluster_identity.name}netcont")
  scope                = var.subnet_id_aks
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster_identity.principal_id
}

## Create a role assigment granting the AKS cluster user-assigned managed identity
## the Private DNS Zone Contributor role on the Private DNS Zone used for AKS
resource "azurerm_role_assignment" "umi_aks_dns_private_dns_zone_contributor" {
  depends_on = [
    null_resource.cluster_umi_creation
  ]

  name                = uuidv5("dns", "${azurerm_resource_group.rgwork.name}/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.${var.region}.azmk8s.io${azurerm_user_assigned_identity.cluster_identity.name}pdnszonecont")
  scope               = "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.${var.region}.azmk8s.io"
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster_identity.principal_id
}

## Create a role assigment granting the AKS kubelet identity AcrPull on the ACR instance
##
resource "azurerm_role_assignment" "umi_aks_kubelet_acr_pull" {
  depends_on = [ 
    azurerm_user_assigned_identity.kubelet_identity 
  ]

  name               = uuidv5("dns", "${azurerm_resource_group.rgwork.name}${module.container_registry_aks.id}${azurerm_user_assigned_identity.kubelet_identity.name}acrpull")
  scope              = module.container_registry_aks.id
  role_definition_name = "AcrPull"
  principal_id       = azurerm_user_assigned_identity.kubelet_identity.principal_id
}

## Sleep for 120 seconds while the role assignments take effect
##
resource "null_resource" "cluster_umi_role_assignment" {
  depends_on = [
    azurerm_role_assignment.umi_aks_cni_subnet_network_contributor,
    azurerm_role_assignment.umi_aks_dns_private_dns_zone_contributor,
    azurerm_role_assignment.umi_aks_kubelet_acr_pull
  ]
  provisioner "local-exec" {
    command = "sleep 120"
  }
}

########## Create an Azure Kubernetes Cluster and Private Endpoint
##########

## Create cluster with overlay
##
resource "azapi_resource" "aks_cluster" {
  depends_on = [
    private_endpoint_container_registry_aks,
    null_resource.cluster_umi_role_assignment
  ]

  type                      = "Microsoft.ContainerService/managedClusters@2025-07-01"
  name                      = "aksoverlay${var.region_code}${var.random_string}"
  parent_id                 = azurerm_resource_group.rgwork.id
  location                  = var.region
  schema_validation_enabled = true

  body = {

    # Set the cluster identity to use a user-assigned managed identity
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.cluster_identity.id}" = {}
      }
    }

    # Not relevant for non-GUI deployments but setting anyway
    kind = "Base"

    properties = {
      ##### Operational settings
      # Set the cluster version
      kubernetesVersion = var.kubernetes_version
      # Set the unique DNS name of the cluster
      #dnsPrefix = "aks${var.region_code}${var.random_string}"
      # Set the custom subdomain of the cluster
      #fqdnSubdomain = "lab"

      ##### Identity settings
      # Enable local authentication
      disableLocalAccounts = false
      # Enable Kubernetes RBAC
      enableRBAC = true
      # Set the kubelet identity
      identityProfile = {
        kubeletidentity = {
          resourceId = azurerm_user_assigned_identity.kubelet_identity.id
        }
      }

      ##### Network settings
      networkProfile = {

        # CNI-specific settings
        networkPlugin = "azure"
        networkPluginMode = "overlay"
        podCidr = var.pod_cidr
        serviceCidr = var.service_cidr
        dnsServiceIp = cidrhost(var.service_cidr, 10)
        ipFamilies = ["IPv4"]

        # Network Policy settings
        networkPolicy = "azure"
        networkDataplane = "azure"

        loadBalancerSku = "Standard"
        outboundType = "userDefinedRouting"
      }

      ##### Kubernetes API Server settings
      apiServerAccessProfile = {
        enablePrivateCluster = true
        privateDnsZone = "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.${var.region}.azmk8s.io"
      }

      ##### Create first node pool
      agentPoolProfiles = [
        {
          name = "pool1"
          count = 1
          vmSize = var.vm_sku
          vnetSubnetId = var.subnet_id_aks

          # Horizontal node Autoscaler settings
          enableAutoScaling = true
          scaleDownMode = "Delete"
          minCount = 1
          maxCount = 3

          # Set max Pods
          maxPods = 250

          # OS-specific settings
          osType = "Linux"
          mode = "System"
          osSku = "Ubuntu"
          osDiskSizeGB = 150
          osDiskType = "Ephemeral"

        }
      ]

      ##### Node-specific OS-level settings
      linuxProfile = {
            adminUsername = "localadmin"
            ssh = {
                publicKeys = [
                    {
                        keyData = var.ssh_public_key
                    }
                ]
            }
      }

      ##### Registry-specific settings
      bootstrapProfile = {
        artifactSource = "Direct"
        containerRegistryId = azurerm_container_registry.acr.id
      }

      ##### Cluster security features
      securityProfile = {

        # Enable workload identity
        workloadIdentity = {
          enabled = true
        }
      }
    }
    tags = var.tags
  }
}

## Create Private Endpoint for cluster
##
module "private_endpoint_cr_aks" {
  depends_on = [
    azapi_resource.aks_cluster
  ]

  source              = "../../modules/private-endpoint"
  random_string       = var.random_string
  location            = var.region
  location_code       = var.region_code
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  resource_name    = azapi_resource.aks_cluster.name
  resource_id      = azapi_resource.aks_cluster.id
  subresource_name = "management"

  subnet_id = var.subnet_id_pe
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_dns}/resourceGroups/${var.resource_group_name_dns}/providers/Microsoft.Network/privateDnsZones/privatelink.${var.region}.azmk8s.io"
  ]
}
