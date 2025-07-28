## Create transit virtual network
##
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.vnet_name}${local.vnet_purpose}${var.location_code}${var.random_string}"
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
  log_analytics_workspace_id = var.traffic_analytics_workspace_id


  enabled_log {
    category = "VMProtectionAlerts"
  }
}

## Create the flow log and enable traffic analytics
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "${local.flow_logs_name}${local.vnet_purpose}${var.location_code}${var.random_string}"
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
    workspace_id = var.traffic_analytics_workspace_id
    workspace_region = var.traffic_analytics_workspace_location
    workspace_resource_id = var.traffic_analytics_workspace_guid
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

## Create Network Security Groups for firewall subnets
##
module "nsg_firewall_public" {
  source              = "../../../network-security-group"
  purpose             = "fwpub"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.traffic_analytics_workspace_id
  security_rules = [
  ]
}

module "nsg_firewall_private" {
  source              = "../../../network-security-group"
  purpose             = "fwpri"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.traffic_analytics_workspace_id
  security_rules = [
    {
      name                   = "AllowAllInbound"
      description            = "Allown all inbound traffic from RFC1918"
      priority               = 1000
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "*"
      source_port_range      = "*"
      destination_port_range = "*"
      source_address_prefixes = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
      ]
      destination_address_prefix = "*"
    }
  ]
}

## Create the subnets for the NVAs
resource "azurerm_subnet" "subnet_firewall_public" {
  name                              = local.subnet_name_firewall_public
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_firewall_public]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_firewall_private" {

  depends_on = [
    azurerm_subnet.subnet_firewall_public
  ]

  name                              = local.subnet_name_firewall_private
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_firewall_private]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

## Associate Network Security Groups to the subnets
##
resource "azurerm_subnet_network_security_group_association" "nsg_association_firewall_public" {
  depends_on = [
    module.nsg_firewall_public,
    azurerm_subnet.subnet_firewall_public
  ]

  subnet_id                 = azurerm_subnet.subnet_firewall_public.id
  network_security_group_id = module.nsg_firewall_public.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_firewall_private" {
  depends_on = [
    module.nsg_firewall_private,
    azurerm_subnet.subnet_firewall_private,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_public
  ]

  subnet_id                 = azurerm_subnet.subnet_firewall_private.id
  network_security_group_id = module.nsg_firewall_private.id
}

## Create the Azure Load Balancers used to sit in front of the NVAs
##
module "elb" {
  depends_on = [
    azurerm_subnet.subnet_firewall_public,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_public
  ]

  source              = "../../../load-balancer/nva-external"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  purpose             = "enva"

  law_resource_id = var.traffic_analytics_workspace_id
  tags            = var.tags
}

module "ilb" {
  depends_on = [
    azurerm_subnet.subnet_firewall_private,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_public,
    module.elb
  ]

  source              = "../../../load-balancer/nva-internal"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  purpose             = "inva"

  subnet_id          = azurerm_subnet.subnet_firewall_private.id
  private_ip_address = cidrhost(var.subnet_cidr_firewall_private, 10)

  law_resource_id = var.traffic_analytics_workspace_id
  tags            = var.tags
}

module "route_table_firewall_private" {
  depends_on = [
    module.ilb
  ]

  source              = "../../../route-table"
  purpose             = "pri"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags


  bgp_route_propagation_enabled = true
  routes = [
    {
      name           = "udr-public"
      address_prefix = var.subnet_cidr_firewall_public
      next_hop_type  = "None"
    },
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = cidrhost(var.subnet_cidr_firewall_private, 10)
    }
  ]
}

module "route_table_firewall_public" {
  depends_on = [
    module.elb
  ]

  source              = "../../../route-table"
  purpose             = "pub"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name           = "udr-ss"
      address_prefix = var.vnet_cidr_ss
      next_hop_type  = "None"
    },
    {
      name           = "udr-spoke1"
      address_prefix = var.vnet_cidr_wl1
      next_hop_type  = "None"
    },
    {
      name           = "udr-spoke2"
      address_prefix = var.vnet_cidr_wl2
      next_hop_type  = "None"
    },
    {
      name           = "udr-on-prem"
      address_prefix = var.address_space_onpremises
      next_hop_type  = "None"
    },
    {
      name           = "udr-private"
      address_prefix = var.subnet_cidr_firewall_private
      next_hop_type  = "None"
    }
  ]
}

## Associate route tables with subnets
##
resource "azurerm_subnet_route_table_association" "route_table_association_public" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_gateway,
    azurerm_subnet.subnet_firewall_public,
    module.route_table_firewall_public,
    module.elb
  ]

  subnet_id      = azurerm_subnet.subnet_firewall_public.id
  route_table_id = module.route_table_firewall_public.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_private" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_public,
    azurerm_subnet.subnet_firewall_private,
    module.route_table_firewall_private,
    module.ilb
  ]

  subnet_id      = azurerm_subnet.subnet_firewall_private.id
  route_table_id = module.route_table_firewall_private.id
}

## Create the network virtual appliances
##
module "nva" {
  depends_on = [
    module.elb,
    module.ilb,
    azurerm_subnet_route_table_association.route_table_association_private,
    azurerm_subnet_route_table_association.route_table_association_public
  ]

  source              = "../../../virtual-machine/ubuntu-nva"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name

  count = var.nva_count

  purpose        = "nva${count.index + 1}"
  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size = var.vm_size_nva

  image_reference = {
    publisher = local.image_preference_publisher
    offer     = local.image_preference_offer
    sku       = local.image_preference_sku
    version   = local.image_preference_version
  }

  address_space_cloud_region = var.address_space_azure
  address_space_on_prem      = var.address_space_onpremises

  nic_private_private_ip_address = cidrhost(var.subnet_cidr_firewall_private, (count.index + 20))
  nic_public_private_ip_address  = cidrhost(var.subnet_cidr_firewall_public, (count.index + 20))
  asn_router                     = var.asn_router

  subnet_id_private = azurerm_subnet.subnet_firewall_private.id
  subnet_id_public  = azurerm_subnet.subnet_firewall_public.id

  ip_inner_gateway        = cidrhost(var.subnet_cidr_firewall_private, 1)
  ip_outer_gateway        = cidrhost(var.subnet_cidr_firewall_public, 1)
  be_address_pool_priv_id = module.ilb.backend_pool_id
  be_address_pool_pub_id  = module.elb.backend_pool_id

  law_resource_id = var.traffic_analytics_workspace_id
  dce_id          = var.dce_id
  dcr_id          = var.dcr_id_linux

  tags = var.tags
}

## Create a connection to the virtual WAN hub
##
module "vwan_connection" {

  source = "../../../vwan-resources/vwan-connection"

  hub_id    = var.vwan_hub_id
  vnet_id   = azurerm_virtual_network.vnet.id
  vnet_name = azurerm_virtual_network.vnet.name

  secure_hub              = false
  propagate_default_route = true
  associated_route_table  = var.vwan_associated_route_table_id
  propagate_route_labels  = var.vwan_propagate_route_labels
  propagate_route_tables  = var.vwan_propagate_route_table_ids
  static_routes           = [
    {
      name                   = "sr-transit"
      address_prefixes       = [
        var.vnet_cidr_ss,
        var.vnet_cidr_wl1,
        var.vnet_cidr_wl2
      ],
      next_hop_ip_address    = module.ilb.ip_address
    }
  ]
}
