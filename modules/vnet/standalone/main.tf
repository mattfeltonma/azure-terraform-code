## Create virtual network and subnets
##
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.vnet_name}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  address_space = [var.address_space_vnet]
  dns_servers   = var.dns_servers

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag-base" {
  name                       = "diag-base"
  target_resource_id         = azurerm_virtual_network.vnet.id
  log_analytics_workspace_id = var.law_resource_id


  enabled_log {
    category = "VMProtectionAlerts"
  }
}

resource "azurerm_subnet" "subnet_app" {

  name                              = local.subnet_name_app
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_app]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_svc" {

  name                              = local.subnet_name_svc
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_svc]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

## Create route tables
##

module "route_table_app" {
  source              = "../../route-table"
  purpose             = "${var.purpose}app"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
  ]
}

module "route_table_svc" {
  source              = "../../route-table"
  purpose             = "${var.purpose}svc"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
  ]
}

## Create network security groups
##
module "nsg_app" {
  source              = "../../network-security-group"
  purpose             = "${var.purpose}app"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_svc" {
  source              = "../../network-security-group"
  purpose             = "${var.purpose}svc"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

## Associate network security groups with subnets
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    module.nsg_app
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = module.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    module.nsg_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = module.nsg_svc.id
}

## Associate route tables with subnets
##
resource "azurerm_subnet_route_table_association" "route_table_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_app,
    module.route_table_app
  ]

  subnet_id      = azurerm_subnet.subnet_app.id
  route_table_id = module.route_table_app.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc,
    module.route_table_svc
  ]

  subnet_id      = azurerm_subnet.subnet_svc.id
  route_table_id = module.route_table_svc.id
}

## Create a user-assigned managed identity
##
module "managed_identity" {
  source              = "../../managed-identity"
  purpose             = var.purpose
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

## Create the flow log and enable traffic analytics
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "${local.flow_logs_name}${local.vnet_name}${var.purpose}${var.location_code}${var.random_string}"
  network_watcher_name = var.network_watcher_name
  resource_group_name  = var.network_watcher_resource_group_name

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet.id

  # Enable VNet Flow Logs and use version 2
  enabled = true
  version = 2

  # Send the flow logs to a storage account and retain them for 7 days
  storage_account_id = var.storage_account_id_flow_logs
  retention_policy {
    enabled = true
    days    = 7
  }

  # Send the flow logs to Traffic Analytics and send every 10 minutes
  traffic_analytics {
    enabled = true
    workspace_id = var.traffic_analytics_workspace_guid
    workspace_region = var.traffic_analytics_workspace_location
    workspace_resource_id = var.traffic_analytics_workspace_id
    interval_in_minutes = 10
  }


  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}


## Creat a Linux web server
##
module "linux_web_server" {
  depends_on = [ 
    azurerm_subnet_route_table_association.route_table_association_app,
    azurerm_subnet_route_table_association.route_table_association_svc
  ]

  source              = "../../virtual-machine/ubuntu-tools"
  random_string       = var.random_string
  location            = var.location
  location_code = var.location_code
  resource_group_name = var.resource_group_name

  purpose = "${var.purpose}tool"
  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size = var.vm_size_web
  image_reference = {
    publisher = local.image_preference_publisher
    offer     = local.image_preference_offer
    sku       = local.image_preference_sku
    version   = local.image_preference_version
  }

  subnet_id = azurerm_subnet.subnet_app.id
  private_ip_address_allocation = "Static"
  nic_private_ip_address = cidrhost(var.subnet_cidr_app, 20)

  law_resource_id = var.traffic_analytics_workspace_id
  dce_id = var.dce_id
  dcr_id = var.dcr_id_linux

  tags                = var.tags
}
