## Create virtual network
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

resource "azurerm_subnet" "subnet_agw" {

  name                              = local.subnet_name_agw
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_agw]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_amlcpt" {

  name                              = local.subnet_name_amlcpt
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_amlcpt]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_apim" {

  name                              = local.subnet_name_apim
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_apim]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_app" {

  name                              = local.subnet_name_app
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_app]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_data" {

  name                              = local.subnet_name_data
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_data]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_mgmt" {

  name                              = local.subnet_name_mgmt
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_mgmt]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_svc" {

  name                              = local.subnet_name_svc
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_svc]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

resource "azurerm_subnet" "subnet_vint" {

  name                              = local.subnet_name_vint
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [var.subnet_cidr_vint]
  private_endpoint_network_policies = local.private_endpoint_network_policies
}

## Peer the virtual network with the hub virtual network
##
resource "azurerm_virtual_network_peering" "vnet_peering_to_hub" {
  name                         = "peer-${local.vnet_name}${local.vnet_purpose}${var.location_code}${var.random_string}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = var.vnet_id_hub
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_to_spoke" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_hub
  ]

  name                         = "peer-hub-to-${local.vnet_name}${local.vnet_purpose}${var.location_code}${var.random_string}"
  resource_group_name          = var.resource_group_name_hub
  virtual_network_name         = var.name_hub
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

## Create route tables
##

module "route_table_agw" {
  source              = "../../../route-table"
  purpose             = "agwwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name           = "udr-default"
      address_prefix = "0.0.0.0/0"
      next_hop_type  = "Internet"
    },
    {
      name                   = "udr-rfc1918-1"
      address_prefix         = "10.0.0.0/8"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    },
    {
      name                   = "udr-rfc1918-2"
      address_prefix         = "172.16.0.0/12"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    },
    {
      name                   = "udr-rfc1918-3"
      address_prefix         = "192.168.0.0/16"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_amlcpt" {
  source              = "../../../route-table"
  purpose             = "amlcptwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_apim" {
  source              = "../../../route-table"
  purpose             = "apimwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    },
    {
      name           = "udr-api-management"
      address_prefix = "ApiManagement"
      next_hop_type  = "Internet"
    }
  ]
}

module "route_table_app" {
  source              = "../../../route-table"
  purpose             = "appwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_data" {
  source              = "../../../route-table"
  purpose             = "datawl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_mgmt" {
  source              = "../../../route-table"
  purpose             = "mgmtwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
    {
      name                   = "udr-default"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.fw_private_ip
    }
  ]
}

module "route_table_vint" {
  source              = "../../../route-table"
  purpose             = "vintwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  bgp_route_propagation_enabled = false
  routes = [
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

module "nsg_agw" {
  source              = "../../../network-security-group"
  purpose             = "agwwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
    {
      name                       = "AllowHttpInboundFromInternet"
      description                = "Allow inbound HTTP to Application Gateway Internet"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 80
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowHttpsInboundFromInternet"
      description                = "Allow inbound HTTPS to Application Gateway Internet"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 443
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                    = "AllowHttpHttpsInboundFromIntranet"
      description             = "Allow inbound HTTP/HTTPS to Application Gateway from Intranet"
      priority                = 1020
      direction               = "Inbound"
      access                  = "Allow"
      protocol                = "Tcp"
      source_port_range       = "*"
      destination_port_ranges = [80, 443]
      source_address_prefixes = [
        "192.168.0.0/16",
        "172.16.0.0/12",
        "10.0.0.0/8"
      ]
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow inbound Application Gateway Manager Traffic"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "65200-65535"
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound traffic from Azure Load Balancer to support probes"
      priority                   = 1040
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
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
    }
  ]
}

module "nsg_amlcpt" {
  source              = "../../../network-security-group"
  purpose             = "amlcptwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_apim" {
  source              = "../../../network-security-group"
  purpose             = "apimwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
    {
      name                   = "AllowHttpsInboundFromRfc1918"
      description            = "Allow inbound HTTP from RFC1918"
      priority               = 1000
      direction              = "Inbound"
      access                 = "Allow"
      protocol               = "Tcp"
      source_port_range      = "*"
      destination_port_range = 443
      source_address_prefixes = [
        "192.168.0.0/16",
        "172.16.0.0/12",
        "10.0.0.0/8"
      ]
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowApiManagementManagerService"
      description                = "Allow inbound management of API Management instancest"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 3443
      source_address_prefix      = "ApiManagement"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow inbound traffic from Azure Load Balancer to support probes"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 6390
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowApiManagementSyncCachePolicies"
      description                = "Allow instances within API Management Service to sync cache policies"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = 4290
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name              = "AllowApiManagementSyncRateLimits"
      description       = "Allow instances within API Management Service to sync rate limits"
      priority          = 1040
      direction         = "Inbound"
      access            = "Allow"
      protocol          = "Tcp"
      source_port_range = "*"
      destination_port_ranges = [
        "6380",
        "6381-6383"
      ]
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
    }
  ]
}

module "nsg_app" {
  source              = "../../../network-security-group"
  purpose             = "appwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_data" {
  source              = "../../../network-security-group"
  purpose             = "datawl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
  ]
}

module "nsg_mgmt" {
  source              = "../../../network-security-group"
  purpose             = "mgmtwl${var.workload_number}"
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
  source              = "../../../network-security-group"
  purpose             = "svcwl${var.workload_number}"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id = var.law_resource_id
  security_rules = [
    {
      name                       = "AllowInboundFromRfc1918"
      description                = "Allow inbound traffic from RFC1918 address space"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefixes    = [
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12"
      ]
      destination_address_prefix = "*"
    }
  ]
}

module "nsg_vint" {
  source              = "../../../network-security-group"
  purpose             = "vintwl${var.workload_number}"
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
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_agw" {
  depends_on = [
    azurerm_subnet.subnet_agw,
    module.nsg_agw,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_agw.id
  network_security_group_id = module.nsg_agw.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_amlcpt" {
  depends_on = [
    azurerm_subnet.subnet_amlcpt,
    module.nsg_amlcpt,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_amlcpt.id
  network_security_group_id = module.nsg_amlcpt.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_apim" {
  depends_on = [
    azurerm_subnet.subnet_apim,
    module.nsg_apim,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_apim.id
  network_security_group_id = module.nsg_apim.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    module.nsg_app,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = module.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_data" {
  depends_on = [
    azurerm_subnet.subnet_data,
    module.nsg_data,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_data.id
  network_security_group_id = module.nsg_data.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_mgmt" {
  depends_on = [
    azurerm_subnet.subnet_mgmt,
    module.nsg_mgmt,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_mgmt.id
  network_security_group_id = module.nsg_mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    module.nsg_svc,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = module.nsg_svc.id
} 

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_vint" {
  depends_on = [
    azurerm_subnet.subnet_vint,
    module.nsg_vint,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id                 = azurerm_subnet.subnet_vint.id
  network_security_group_id = module.nsg_vint.id
}

## Associate route tables with subnets
##
resource "azurerm_subnet_route_table_association" "route_table_association_agw" {
  depends_on = [
    azurerm_subnet.subnet_agw,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_agw,
    module.route_table_agw,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_agw.id
  route_table_id = module.route_table_agw.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_amlcpt" {
  depends_on = [
    azurerm_subnet.subnet_amlcpt,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_amlcpt,
    module.route_table_amlcpt,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_amlcpt.id
  route_table_id = module.route_table_amlcpt.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_apim" {
  depends_on = [
    azurerm_subnet.subnet_apim,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_apim,
    module.route_table_apim,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_apim.id
  route_table_id = module.route_table_apim.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_app,
    module.route_table_app,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_app.id
  route_table_id = module.route_table_app.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_data" {
  depends_on = [
    azurerm_subnet.subnet_data,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_data,
    module.route_table_data,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_data.id
  route_table_id = module.route_table_data.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_mgmt" {
  depends_on = [
    azurerm_subnet.subnet_mgmt,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_mgmt,
    module.route_table_mgmt,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_mgmt.id
  route_table_id = module.route_table_mgmt.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_vint" {
  depends_on = [
    azurerm_subnet.subnet_vint,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_vint,
    module.route_table_vint,
    azurerm_virtual_network_peering.vnet_peering_to_hub,
    azurerm_virtual_network_peering.vnet_peering_to_spoke
  ]

  subnet_id      = azurerm_subnet.subnet_vint.id
  route_table_id = module.route_table_vint.id
}

## Create a user-assigned managed identity
##
module "managed_identity" {
  source              = "../../../managed-identity"
  purpose             = "wl${var.workload_number}p"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

## Create a Key Vault instance
##
module "key_vault" {
  depends_on = [
    module.managed_identity
  ]

  source              = "../../../key-vault"
  purpose             = "wl${var.workload_number}p"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  law_resource_id    = var.law_resource_id
  kv_admin_object_id = module.managed_identity.principal_id

  firewall_default_action = "Allow"
  firewall_bypass         = "AzureServices"
}

## Create a Private Endpoint for the Key Vault
##
module "private_endpoint_kv" {
  source              = "../../../private-endpoint"
  random_string       = var.random_string
  location            = var.location
    location_code = var.location_code
  resource_group_name = var.resource_group_name
  tags                = var.tags

  resource_name    = module.key_vault.name
  resource_id      = module.key_vault.id
  subresource_name = "vault"


  subnet_id = azurerm_subnet.subnet_svc.id
  private_dns_zone_ids = [
    "/subscriptions/${var.sub_id_shared}/resourceGroups/${var.resource_group_name_shared}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  ]
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
