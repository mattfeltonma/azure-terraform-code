## Create virtual network and subnets
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
  log_analytics_workspace_id = var.law_resource_id


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

resource "azurerm_subnet" "subnet_bastion" {

  name                              = local.subnet_name_bastion
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_bastion]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_dnsin" {

  name                              = local.subnet_name_dnsin
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_dnsin]
  private_endpoint_network_policies = local.private_endpoint_network_policies

  ## Delegation must be added because redeployment will fail without it.
  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_subnet" "subnet_dnsout" {

  name                              = local.subnet_name_dnsout
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_dnsout]
  private_endpoint_network_policies = local.private_endpoint_network_policies

  ## Delegation must be added because redeployment will fail without it.
  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

resource "azurerm_subnet" "subnet_pe" {

  name                              = local.subnet_name_pe
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_pe]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_tools" {

  name                              = local.subnet_name_tools
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_tools]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

## Peer the virtual network with the hub virtual network if hub and spoke
##
resource "azurerm_virtual_network_peering" "vnet_peering-to-hub" {
  count = var.hub_and_spoke == true ? 1 : 0

  name                         = "peer-${local.vnet_name}${local.vnet_purpose}${var.location_code}${var.random_string}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = var.vnet_id_hub
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "vnet_peering" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering-to-hub
  ]

  count = var.hub_and_spoke == true ? 1 : 0

  name                         = "peer-hub-to-${local.vnet_name}${local.vnet_purpose}${var.location_code}${var.random_string}"
  resource_group_name          = var.resource_group_name_hub
  virtual_network_name         = var.name_hub
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

## Peer the virtual network with a VWAN hub if using VWAN
##
module "vwan_connection" {
  count = var.hub_and_spoke == false ? 1 : 0

  source = "../../../vwan-resources/vwan-connection"

  hub_id    = var.vwan_hub_id
  vnet_id   = azurerm_virtual_network.vnet.id
  vnet_name = azurerm_virtual_network.vnet.name

  secure_hub              = var.vwan_secure_hub
  propagate_default_route = var.vwan_propagate_default_route
  associated_route_table  = var.vwan_associated_route_table
  propagate_route_labels  = var.vwan_propagate_route_labels
  propagate_route_tables  = var.vwan_propagate_route_tables
  inbound_route_map_id    = var.vwan_inbound_route_map_id
  outbound_route_map_id   = var.vwan_outbound_route_map_id
  static_routes           = var.vwan_static_routes
}

## Create route tables
##
module "route_table_dnsin" {
  source              = "../../../route-table"
  purpose             = "din"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = var.fw_private_ip == null ? true : false
  routes = var.fw_private_ip == null ? [] : [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_dnsout" {
  source              = "../../../route-table"
  purpose             = "dou"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = var.fw_private_ip == null ? true : false
  routes = var.fw_private_ip == null ? [] : [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_tools" {
  source              = "../../../route-table"
  purpose             = "too"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = var.fw_private_ip == null ? true : false
  routes = var.fw_private_ip == null ? [] : [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

## Create network security groups
##
module "nsg_bastion" {
  source              = "../../../network-security-group"
  purpose             = "bst"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow inbound HTTPS to allow for connections to Bastion"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow inbound HTTPS to allow for managemen of Bastion instances"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound HTTPS to allow Azure Load Balancer health probes"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowBastionHostCommunication"
      description                = "Allow data plane communication between Bastion hosts"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [8080, 5701]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all inbound traffic"
      priority                   = 2000
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowSshRdpOutbound"
      description                = "Allow Bastion hosts to SSH and RDP to virtual machines"
      priority                   = 1100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [22, 2222, 3389, 3390]
      source_address_prefix      = "*"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureCloudOutbound"
      description                = "Allow Bastion to connect to dependent services in Azure"
      priority                   = 1110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "*"
      destination_address_prefix = "AzureCloud"
    },
    {
      name                       = "AllowBastionCommunication"
      description                = "Allow data plane communication between Bastion hosts"
      priority                   = 1120
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_ranges    = [8080, 5701]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowHttpOutbound"
      description                = "Allow Bastion to connect to dependent services on the Internet"
      priority                   = 1130
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = 80
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    },
    {
      name                       = "DenyAllOutbound"
      description                = "Deny all outbound traffic"
      priority                   = 2100
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

module "nsg_dnsin" {
  source              = "../../../network-security-group"
  purpose             = "din"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
    {
      name                   = "AllowTcpDnsInbound"
      description            = "Allow TCP DNS traffic"
      priority               = 1000
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      source_port_range      = "*"
      destination_port_range = 53
      source_address_prefixes = [
        var.address_space_azure,
        var.address_space_onpremises
      ]
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowUdppDnsInbound"
      description                = "Allow UDP DNS traffic"
      priority                   = 1100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = 53
      source_address_prefixes = [
        var.address_space_azure,
        var.address_space_onpremises
      ]
      destination_address_prefix = "*"
    }
  ]
}

module "nsg_dnsout" {
  source              = "../../../network-security-group"
  purpose             = "dou"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_pe" {
  source              = "../../../network-security-group"
  purpose             = "pe"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_tools" {
  source              = "../../../network-security-group"
  purpose             = "too"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

## Associate network security groups and route tables with subnets
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_bastion" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering,
    azurerm_subnet.subnet_bastion,
    module.nsg_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_bastion.id
  network_security_group_id = module.nsg_bastion.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_dnsin" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering,
    azurerm_subnet.subnet_dnsin,
    module.nsg_dnsin
  ]

  subnet_id                 = azurerm_subnet.subnet_dnsin.id
  network_security_group_id = module.nsg_dnsin.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_dnsout" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering,
    azurerm_subnet.subnet_dnsout,
    module.nsg_dnsout
  ]
  subnet_id                 = azurerm_subnet.subnet_dnsout.id
  network_security_group_id = module.nsg_dnsout.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_pe" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering,
    azurerm_subnet.subnet_pe,
    module.nsg_pe
  ]
  subnet_id                 = azurerm_subnet.subnet_pe.id
  network_security_group_id = module.nsg_pe.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_tools" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering,
    azurerm_subnet.subnet_tools,
    module.nsg_tools
  ]
  subnet_id                 = azurerm_subnet.subnet_tools.id
  network_security_group_id = module.nsg_tools.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_dnsin" {
  depends_on = [
    azurerm_subnet.subnet_dnsin,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_dnsin,
    module.route_table_dnsin,
    azurerm_virtual_network_peering.vnet_peering,
    module.vwan_connection
  ]

  subnet_id      = azurerm_subnet.subnet_dnsin.id
  route_table_id = module.route_table_dnsin.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_dnsout" {
  depends_on = [
    azurerm_subnet.subnet_dnsout,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_dnsout,
    module.route_table_dnsout,
    azurerm_virtual_network_peering.vnet_peering,
    module.vwan_connection
  ]

  subnet_id      = azurerm_subnet.subnet_dnsout.id
  route_table_id = module.route_table_dnsout.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_tools" {
  depends_on = [
    azurerm_subnet.subnet_tools,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_tools,
    module.route_table_tools,
    azurerm_virtual_network_peering.vnet_peering,
    module.vwan_connection
  ]

  subnet_id      = azurerm_subnet.subnet_tools.id
  route_table_id = module.route_table_tools.id
}

## Create Private DNS Resolver and endpoints
##
module "dns_resolver" {
  depends_on = [
    azurerm_subnet.subnet_dnsin,
    azurerm_subnet.subnet_dnsout,
    azurerm_subnet_route_table_association.route_table_association_dnsin,
    azurerm_subnet_route_table_association.route_table_association_dnsout
  ]

  source              = "../../../dns/private-dns-resolver"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name

  vnet_id            = azurerm_virtual_network.vnet.id
  subnet_id_inbound  = azurerm_subnet.subnet_dnsin.id
  subnet_id_outbound = azurerm_subnet.subnet_dnsout.id

  tags = var.tags
}

## If a DNS Proxy is not used then set the virtual network to use the inbound endpoint in the vnet DHCP settings
##
resource "azurerm_virtual_network_dns_servers" "vnet_dns" {

  count = var.dns_proxy == false ? 1 : 0

  depends_on = [
    module.dns_resolver
  ]

  virtual_network_id = azurerm_virtual_network.vnet.id
  dns_servers = [
    module.dns_resolver.inbound_endpoint_ip
  ]
}

## Create Azure Bastion instance
##
module "bastion" {
  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion,
    module.dns_resolver
  ]

  source              = "../../../bastion"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name

  subnet_id       = azurerm_subnet.subnet_bastion.id
  law_resource_id = var.law_resource_id

  tags = var.tags
}

## Deploy a Windows or Linux virtual machine for tools and associate it to the DCE and DCR
##
module "windows_vm_tool" {
  depends_on = [
    module.dns_resolver
  ]

  source              = "../../../virtual-machine/windows-tools"
  purpose             = "too"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name

  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_size = var.sku_tools_size
  image_reference = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.sku_tools_os
    version   = "latest"
  }
  subnet_id = azurerm_subnet.subnet_tools.id

  dce_id = var.dce_id
  dcr_id_windows = var.dcr_id_windows

  tags = var.tags
}
